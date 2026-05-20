param(
    [int]$DurationSeconds = 90,
    [int]$IntervalSeconds = 5,
    [string]$Since = "10m",
    [string]$SummaryFile,
    [string]$OutputDir = ".\infra\load-tests\appointments\results\evidence"
)

$ErrorActionPreference = "Stop"

if ($DurationSeconds -lt 1 -or $IntervalSeconds -lt 1) {
    throw "DurationSeconds e IntervalSeconds deben ser mayores a cero."
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$runDir = Join-Path $OutputDir "monitor-loadtest-$stamp"
New-Item -ItemType Directory -Force -Path $runDir | Out-Null

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [AllowNull()][string]$Content
    )
    if ($null -eq $Content) {
        $Content = ""
    }
    [System.IO.File]::WriteAllText((Join-Path $runDir $Path), $Content, $utf8NoBom)
}

function Invoke-Capture {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Block
    )

    try {
        $output = & $Block 2>&1 | Out-String
        Write-Utf8NoBom -Path $Name -Content $output
    } catch {
        Write-Utf8NoBom -Path $Name -Content "ERROR: $($_.Exception.Message)"
    }
}

function Add-Sample {
    param([string]$Text)
    $path = Join-Path $runDir "samples.txt"
    [System.IO.File]::AppendAllText($path, $Text, $utf8NoBom)
}

function Get-MetricCount {
    param($Summary, [string]$Name)
    if ($Summary.metrics.$Name -and $Summary.metrics.$Name.values.count -ne $null) {
        return [int]$Summary.metrics.$Name.values.count
    }
    return 0
}

Write-Host "Collecting load-test monitor evidence in $runDir"

Invoke-Capture -Name "docker-compose-ps.initial.txt" -Block {
    docker compose ps
}

Invoke-Capture -Name "gateway-env.txt" -Block {
    docker compose exec -T api-gateway printenv |
        Select-String -Pattern "APPOINTMENT_SERVICE_URL|SCHEDULE_SERVICE_URL|PATIENT_SERVICE_URL|GATEWAY_CB|GATEWAY_TIMELIMITER|GATEWAY_BULKHEAD|RATE_LIMIT_APPOINTMENT"
}

Invoke-Capture -Name "appointment-env.txt" -Block {
    docker compose exec -T appointment-service printenv |
        Select-String -Pattern "PATIENT_SERVICE_URL|SCHEDULE_SERVICE_URL|HIKARI|LOADTEST|APPOINTMENT_CLIENT|APPOINTMENT_HOLD"
}

$end = (Get-Date).AddSeconds($DurationSeconds)
$sampleNumber = 0
while ((Get-Date) -lt $end) {
    $sampleNumber++
    Add-Sample "`n===== sample $sampleNumber $(Get-Date -Format o) =====`n"

    try {
        Add-Sample "`n--- docker stats ---`n"
        Add-Sample ((docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}" 2>&1 | Out-String))
    } catch {
        Add-Sample "docker stats error: $($_.Exception.Message)`n"
    }

    try {
        Add-Sample "`n--- pg_stat_activity ---`n"
        Add-Sample ((docker compose exec -T postgres psql -U mediqueue -d mediqueue -c "select state, wait_event_type, wait_event, count(*) from pg_stat_activity group by state, wait_event_type, wait_event order by count(*) desc;" 2>&1 | Out-String))
    } catch {
        Add-Sample "pg_stat_activity error: $($_.Exception.Message)`n"
    }

    try {
        Add-Sample "`n--- pg_locks summary ---`n"
        Add-Sample ((docker compose exec -T postgres psql -U mediqueue -d mediqueue -c "select mode, granted, count(*) from pg_locks group by mode, granted order by count(*) desc;" 2>&1 | Out-String))
    } catch {
        Add-Sample "pg_locks error: $($_.Exception.Message)`n"
    }

    try {
        Add-Sample "`n--- rabbitmq queues ---`n"
        Add-Sample ((docker compose exec -T rabbitmq rabbitmqctl list_queues name messages_ready messages_unacknowledged consumers 2>&1 | Out-String))
    } catch {
        Add-Sample "rabbitmq error: $($_.Exception.Message)`n"
    }

    Start-Sleep -Seconds $IntervalSeconds
}

Invoke-Capture -Name "docker-compose-ps.final.txt" -Block {
    docker compose ps
}

Invoke-Capture -Name "api-gateway.loadtest.log" -Block {
    docker compose logs --since $Since api-gateway |
        Select-String -Pattern "status=503 method=POST path=/api/appointments|gateway_fallback|BulkheadFullException|CallNotPermitted|Timeout|TimeoutException|ConnectException|connection refused|PrematureClose"
}

Invoke-Capture -Name "api-gateway-lb.log" -Block {
    docker compose logs --since $Since api-gateway-lb |
        Select-String -Pattern "DOWN|UP|503|504|timeout|api-gateway|No server is available|connection refused"
}

Invoke-Capture -Name "appointment-service.loadtest.log" -Block {
    docker compose logs --since $Since appointment-service |
        Select-String -Pattern "ERROR|WARN|Hikari|timeout|Timeout|hold_expiration_failed|LazyInitializationException|confirm_skipped"
}

Invoke-Capture -Name "appointment-lb.log" -Block {
    docker compose logs --since $Since appointment-lb |
        Select-String -Pattern "DOWN|UP|503|504|timeout|appointment-service|No server is available|connection refused"
}

Invoke-Capture -Name "schedule-lb.log" -Block {
    docker compose logs --since $Since schedule-lb |
        Select-String -Pattern "DOWN|UP|503|504|timeout|schedule-service|No server is available|connection refused"
}

Invoke-Capture -Name "patient-lb.log" -Block {
    docker compose logs --since $Since patient-lb |
        Select-String -Pattern "DOWN|UP|503|504|timeout|patient-service|No server is available|connection refused"
}

Invoke-Capture -Name "postgres-appointments.txt" -Block {
    docker compose exec -T postgres psql -U mediqueue -d mediqueue -c "select appointment_status, count(*) from appointment.appointments group by appointment_status order by appointment_status;"
    docker compose exec -T postgres psql -U mediqueue -d mediqueue -c "select slot_id, count(*) from appointment.appointments where appointment_status in ('PENDING_PAYMENT','CONFIRMED') group by slot_id having count(*) > 1 limit 20;"
    docker compose exec -T postgres psql -U mediqueue -d mediqueue -c "select publication_status, count(*) from appointment.outbox_events group by publication_status order by publication_status;"
}

if ($SummaryFile) {
    Invoke-Capture -Name "k6-summary.txt" -Block {
        $summary = Get-Content -Raw -LiteralPath $SummaryFile | ConvertFrom-Json
        "summary_file=$SummaryFile"
        "appointments_created=$(Get-MetricCount -Summary $summary -Name 'appointments_created')"
        "appointments_503=$(Get-MetricCount -Summary $summary -Name 'appointments_503')"
        "appointments_503_json_gateway=$(Get-MetricCount -Summary $summary -Name 'appointments_503_json_gateway')"
        "appointments_503_html_haproxy=$(Get-MetricCount -Summary $summary -Name 'appointments_503_html_haproxy')"
        "appointments_connection_refused=$(Get-MetricCount -Summary $summary -Name 'appointments_connection_refused')"
        "appointments_server_error=$(Get-MetricCount -Summary $summary -Name 'appointments_server_error')"
        "appointments_timeout=$(Get-MetricCount -Summary $summary -Name 'appointments_timeout')"
        "appointments_validation_error=$(Get-MetricCount -Summary $summary -Name 'appointments_validation_error')"
        "appointments_conflict=$(Get-MetricCount -Summary $summary -Name 'appointments_conflict')"
        "appointments_unexpected=$(Get-MetricCount -Summary $summary -Name 'appointments_unexpected')"
        "dropped_iterations=$(Get-MetricCount -Summary $summary -Name 'dropped_iterations')"
        "http_reqs=$(Get-MetricCount -Summary $summary -Name 'http_reqs')"
        if ($summary.metrics.http_req_duration) {
            "http_req_duration_p95=$($summary.metrics.http_req_duration.values.'p(95)')"
            "http_req_duration_p99=$($summary.metrics.http_req_duration.values.'p(99)')"
        }
    }
}

Write-Host "Evidence written to $runDir"

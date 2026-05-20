param(
    [string]$OutputDir = ".\infra\load-tests\appointments\results\evidence",
    [string]$Since = "30m",
    [string]$SummaryFile
)

$ErrorActionPreference = "Stop"

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$target = Join-Path $OutputDir "appointment-load-$stamp"
New-Item -ItemType Directory -Force -Path $target | Out-Null

function Write-Text {
    param(
        [string]$Name,
        [string]$Content
    )

    $path = Join-Path $target $Name
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($path, $Content, $utf8NoBom)
}

function Invoke-Capture {
    param(
        [string]$Name,
        [scriptblock]$Block
    )

    try {
        $content = & $Block | Out-String
        Write-Text -Name $Name -Content $content
    } catch {
        Write-Text -Name $Name -Content "FAILED: $($_.Exception.Message)"
    }
}

Invoke-Capture -Name "docker-compose-ps.txt" -Block {
    docker compose ps
}

Invoke-Capture -Name "api-gateway-503-count.txt" -Block {
    $matches = docker compose logs --since $Since api-gateway |
        Select-String -Pattern "status=503 method=POST path=/api/appointments"
    "gateway_503_count=$($matches.Count)"
}

Invoke-Capture -Name "api-gateway-503-first-50.log" -Block {
    docker compose logs --since $Since api-gateway |
        Select-String -Pattern "status=503 method=POST path=/api/appointments|gateway_fallback|CircuitBreaker|Timeout|exception" |
        Select-Object -First 50
}

Invoke-Capture -Name "appointment-service-errors.log" -Block {
    docker compose logs --since $Since appointment-service |
        Select-String -Pattern "ERROR|WARN|Exception|Hikari|LazyInitialization|hold_expiration_failed|validation_fallback|confirm_skipped"
}

Invoke-Capture -Name "schedule-service-errors.log" -Block {
    docker compose logs --since $Since schedule-service |
        Select-String -Pattern "ERROR|WARN|Exception|Hikari|Failed to validate connection|connection has been closed"
}

Invoke-Capture -Name "patient-service-errors.log" -Block {
    docker compose logs --since $Since patient-service |
        Select-String -Pattern "ERROR|WARN|Exception|Hikari|Failed to validate connection|connection has been closed"
}

Invoke-Capture -Name "rabbitmq-queues.txt" -Block {
    docker compose exec -T rabbitmq rabbitmqctl list_queues name messages_ready messages_unacknowledged consumers
}

Invoke-Capture -Name "rabbitmq-bindings.txt" -Block {
    docker compose exec -T rabbitmq rabbitmqctl list_bindings
}

Invoke-Capture -Name "db-appointments-by-status.txt" -Block {
    docker compose exec -T postgres psql -U mediqueue -d mediqueue -c "select appointment_status, count(*) from appointment.appointments group by appointment_status order by appointment_status;"
}

Invoke-Capture -Name "db-double-reservations.txt" -Block {
    docker compose exec -T postgres psql -U mediqueue -d mediqueue -c "select slot_id, count(*) from appointment.appointments where appointment_status in ('PENDING_PAYMENT','CONFIRMED') group by slot_id having count(*) > 1 order by count(*) desc limit 50;"
}

Invoke-Capture -Name "db-outbox-by-status.txt" -Block {
    docker compose exec -T postgres psql -U mediqueue -d mediqueue -c "select publication_status, count(*) from appointment.outbox_events group by publication_status order by publication_status;"
}

Invoke-Capture -Name "db-connection-counts.txt" -Block {
    docker compose exec -T postgres psql -U mediqueue -d mediqueue -c "select datname, usename, state, count(*) from pg_stat_activity group by datname, usename, state order by datname, usename, state;"
}

if ($SummaryFile -and (Test-Path -Path $SummaryFile)) {
    Copy-Item -LiteralPath $SummaryFile -Destination (Join-Path $target (Split-Path -Leaf $SummaryFile)) -Force
    Invoke-Capture -Name "k6-summary-counters.txt" -Block {
        $summary = Get-Content -Raw -Path $SummaryFile | ConvertFrom-Json
        @(
            "appointment_attempts=$($summary.metrics.appointment_attempts.values.count)"
            "appointments_created=$($summary.metrics.appointments_created.values.count)"
            "appointments_503=$($summary.metrics.appointments_503.values.count)"
            "appointments_server_error=$($summary.metrics.appointments_server_error.values.count)"
            "appointments_validation_error=$($summary.metrics.appointments_validation_error.values.count)"
            "appointments_unexpected=$($summary.metrics.appointments_unexpected.values.count)"
            "appointments_dataset_exhausted=$($summary.metrics.appointments_dataset_exhausted.values.count)"
            "dropped_iterations=$($summary.metrics.dropped_iterations.values.count)"
            "http_reqs=$($summary.metrics.http_reqs.values.count)"
            "http_req_duration_p95=$($summary.metrics.http_req_duration.values.'p(95)')"
        ) -join [Environment]::NewLine
    }
}

Write-Host "Evidence written to $target"

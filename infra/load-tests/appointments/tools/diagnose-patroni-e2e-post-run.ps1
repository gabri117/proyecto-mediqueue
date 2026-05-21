param(
    [ValidateSet("single", "patroni")]
    [string]$DatabaseTarget = "patroni",
    [string]$OutputDir = ".\infra\load-tests\appointments\results\evidence",
    [string]$Since = "20m",
    [string]$SummaryFile,
    [int]$Tail = 600,
    [switch]$UseE2EProfile,
    [int]$DockerCommandTimeoutSeconds = 12
)

$ErrorActionPreference = "Stop"

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$target = Join-Path $OutputDir "patroni-e2e-diagnosis-$stamp"
New-Item -ItemType Directory -Force -Path $target | Out-Null

$appointmentStages = @(
    "patient_validation_ms",
    "schedule_slot_validation_ms",
    "idempotency_lookup_ms",
    "slot_hold_or_lock_ms",
    "appointment_save_ms",
    "outbox_save_ms",
    "total_create_appointment_ms"
)

function Get-ComposeArgs {
    if ($DatabaseTarget -eq "patroni") {
        $args = @("compose", "-f", "docker-compose.yml", "-f", "docker-compose.patroni.yml", "-f", "docker-compose.patroni-apps.yml")
        if ($UseE2EProfile -and (Test-Path -Path "docker-compose.patroni-e2e.yml")) {
            $args += @("-f", "docker-compose.patroni-e2e.yml")
        }
        return $args
    }
    return @("compose")
}

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

function Invoke-CaptureWithTimeout {
    param(
        [string]$Name,
        [scriptblock]$Block,
        [int]$TimeoutSeconds = $DockerCommandTimeoutSeconds
    )

    $workDir = (Get-Location).Path
    $job = Start-Job -ArgumentList $workDir, $Block -ScriptBlock {
        param($JobWorkDir, $JobBlock)
        Set-Location -Path $JobWorkDir
        & $JobBlock
    }
    try {
        if (Wait-Job -Job $job -Timeout $TimeoutSeconds) {
            $content = Receive-Job -Job $job | Out-String
            Write-Text -Name $Name -Content $content
        } else {
            Stop-Job -Job $job -ErrorAction SilentlyContinue
            Write-Text -Name $Name -Content "TIMEOUT after $TimeoutSeconds seconds"
        }
    } catch {
        Write-Text -Name $Name -Content "FAILED: $($_.Exception.Message)"
    } finally {
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-DbCapture {
    param(
        [string]$Name,
        [string]$Sql
    )

    Invoke-Capture -Name $Name -Block {
        $composeArgs = Get-ComposeArgs
        if ($DatabaseTarget -eq "patroni") {
            $Sql | & docker @composeArgs exec -T -e PGPASSWORD=mediqueue patroni-postgres-1 psql -h patroni-postgres-lb -p 5432 -U mediqueue -d mediqueue -v ON_ERROR_STOP=1
        } else {
            $Sql | & docker @composeArgs exec -T postgres psql -U mediqueue -d mediqueue -v ON_ERROR_STOP=1
        }
    }
}

function Invoke-ContainerMetricCapture {
    param(
        [string]$Service,
        [string]$NamePrefix,
        [string[]]$MetricNames
    )

    $composeArgs = Get-ComposeArgs
    $containers = @(& docker @composeArgs ps -q $Service)
    if ($LASTEXITCODE -ne 0 -or $containers.Count -lt 1) {
        Write-Text -Name "$NamePrefix-actuator-metrics.txt" -Content "No containers found for $Service"
        return
    }

    $content = New-Object System.Collections.Generic.List[string]
    foreach ($container in $containers) {
        $content.Add("===== container=$container service=$Service =====")
        $content.Add("--- metric-inventory ---")
        try {
            $content.Add((& docker exec $container wget -T 3 -qO- "http://localhost:8080/actuator/metrics" 2>&1 | Out-String).Trim())
        } catch {
            $content.Add("FAILED metric-inventory error=$($_.Exception.Message)")
        }
        foreach ($metric in $MetricNames) {
            $content.Add("--- metric=$metric ---")
            try {
                $content.Add((& docker exec $container wget -T 3 -qO- "http://localhost:8080/actuator/metrics/$metric" 2>&1 | Out-String).Trim())
            } catch {
                $content.Add("FAILED metric=$metric error=$($_.Exception.Message)")
            }
        }
    }

    Write-Text -Name "$NamePrefix-actuator-metrics.txt" -Content ($content -join [Environment]::NewLine)
}

function Invoke-AppointmentStageMetrics {
    $composeArgs = Get-ComposeArgs
    $containers = @(& docker @composeArgs ps -q appointment-service)
    if ($LASTEXITCODE -ne 0 -or $containers.Count -lt 1) {
        Write-Text -Name "appointment-stage-metrics.txt" -Content "No appointment-service containers found."
        return
    }

    $content = New-Object System.Collections.Generic.List[string]
    foreach ($container in $containers) {
        $content.Add("===== container=$container service=appointment-service =====")
        foreach ($stage in $appointmentStages) {
            $encodedStage = "stage:$stage"
            $content.Add("--- mediqueue.appointment.create.stage.duration $encodedStage ---")
            try {
                $content.Add((& docker exec $container wget -T 3 -qO- "http://localhost:8080/actuator/metrics/mediqueue.appointment.create.stage.duration?tag=$encodedStage" 2>&1 | Out-String).Trim())
            } catch {
                $content.Add("FAILED stage=$stage error=$($_.Exception.Message)")
            }
        }
    }

    Write-Text -Name "appointment-stage-metrics.txt" -Content ($content -join [Environment]::NewLine)
}

$composeArgsText = (Get-ComposeArgs) -join " "
Write-Text -Name "diagnosis-context.txt" -Content @"
DatabaseTarget=$DatabaseTarget
Since=$Since
Tail=$Tail
Compose=docker $composeArgsText
SummaryFile=$SummaryFile
UseE2EProfile=$UseE2EProfile
"@

Invoke-CaptureWithTimeout -Name "docker-compose-ps.txt" -Block {
    docker compose -f docker-compose.yml -f docker-compose.patroni.yml -f docker-compose.patroni-apps.yml -f docker-compose.patroni-e2e.yml ps
}

Invoke-CaptureWithTimeout -Name "docker-stats-snapshot.txt" -Block {
    docker stats --no-stream
}

Invoke-Capture -Name "api-gateway-fallback-and-timeouts.log" -Block {
    $composeArgs = Get-ComposeArgs
    & docker @composeArgs logs --since $Since --tail $Tail api-gateway |
        Select-String -Pattern "gateway_fallback|status=503 method=POST path=/api/appointments|BulkheadFullException|Timeout|TimeoutException|CallNotPermitted|PrematureClose|Pool|pending|ConnectException|exception="
}

Invoke-Capture -Name "api-gateway-fallback-summary.txt" -Block {
    $composeArgs = Get-ComposeArgs
    $lines = & docker @composeArgs logs --since $Since --tail $Tail api-gateway |
        Select-String -Pattern "gateway_fallback" |
        ForEach-Object { $_.Line }
    $total = @($lines).Count
    "total_gateway_fallback=$total"
    ""
    "by_failureKind"
    $lines |
        ForEach-Object {
            if ($_ -match "failureKind=([^ ]+)") { $Matches[1] } else { "unknown" }
        } |
        Group-Object |
        Sort-Object Count -Descending |
        ForEach-Object { "$($_.Name)=$($_.Count)" }
    ""
    "by_exception"
    $lines |
        ForEach-Object {
            if ($_ -match "exception=([^ ]+)") { $Matches[1] } else { "unknown" }
        } |
        Group-Object |
        Sort-Object Count -Descending |
        ForEach-Object { "$($_.Name)=$($_.Count)" }
}

Invoke-Capture -Name "appointment-service-errors-and-slow.log" -Block {
    $composeArgs = Get-ComposeArgs
    & docker @composeArgs logs --since $Since --tail $Tail appointment-service |
        Select-String -Pattern "appointment_create_timing|ERROR|WARN|Exception|Hikari|timeout|timed out|lock|deadlock|outbox|idempotency|confirm_skipped"
}

Invoke-Capture -Name "gateway-env.txt" -Block {
    $composeArgs = Get-ComposeArgs
    & docker @composeArgs exec -T api-gateway printenv |
        Select-String -Pattern "GATEWAY_HTTPCLIENT|GATEWAY_CB|GATEWAY_TIMELIMITER|GATEWAY_BULKHEAD|RATE_LIMIT_APPOINTMENT|APPOINTMENT_SERVICE_URL"
}

Invoke-Capture -Name "appointment-env.txt" -Block {
    $composeArgs = Get-ComposeArgs
    & docker @composeArgs exec -T appointment-service printenv |
        Select-String -Pattern "HIKARI|TOMCAT|LOADTEST|OUTBOX|APPOINTMENT_CREATE|APPOINTMENT_CLIENT|PATIENT_SERVICE_URL|SCHEDULE_SERVICE_URL"
}

Invoke-ContainerMetricCapture -Service "appointment-service" -NamePrefix "appointment" -MetricNames @(
    "hikaricp.connections.active",
    "hikaricp.connections.idle",
    "hikaricp.connections.pending",
    "hikaricp.connections.max",
    "hikaricp.connections.timeout",
    "tomcat.threads.busy",
    "tomcat.threads.current",
    "tomcat.threads.config.max",
    "jvm.memory.used",
    "process.cpu.usage"
)

Invoke-ContainerMetricCapture -Service "api-gateway" -NamePrefix "gateway" -MetricNames @(
    "http.server.requests",
    "spring.cloud.gateway.requests",
    "reactor.netty.connection.provider.active.connections",
    "reactor.netty.connection.provider.pending.connections",
    "reactor.netty.connection.provider.max.connections",
    "jvm.memory.used",
    "process.cpu.usage"
)

Invoke-AppointmentStageMetrics

Invoke-DbCapture -Name "pg-stat-activity.txt" -Sql @"
select datname, usename, state, wait_event_type, wait_event, count(*)
from pg_stat_activity
group by datname, usename, state, wait_event_type, wait_event
order by count(*) desc;
"@

Invoke-DbCapture -Name "pg-active-queries.txt" -Sql @"
select pid, usename, state, wait_event_type, wait_event, now() - query_start as age, left(query, 240) as query
from pg_stat_activity
where datname = 'mediqueue' and state <> 'idle'
order by age desc
limit 60;
"@

Invoke-DbCapture -Name "pg-connections.txt" -Sql @"
show max_connections;
select count(*) as total_connections,
       count(*) filter (where state = 'active') as active_connections,
       count(*) filter (where wait_event_type is not null) as waiting_connections
from pg_stat_activity;
"@

Invoke-DbCapture -Name "pg-locks.txt" -Sql @"
select locktype, mode, granted, count(*)
from pg_locks
group by locktype, mode, granted
order by count(*) desc;
"@

Invoke-DbCapture -Name "runtime-counts.txt" -Sql @"
select 'appointment.appointments' as table_name, count(*) from appointment.appointments
union all select 'appointment.appointment_holds', count(*) from appointment.appointment_holds
union all select 'appointment.outbox_events', count(*) from appointment.outbox_events
union all select 'payment.payments', count(*) from payment.payments
union all select 'payment.payment_events_outbox', count(*) from payment.payment_events_outbox
union all select 'notification.notifications', count(*) from notification.notifications
order by table_name;

select appointment_status, count(*) from appointment.appointments group by appointment_status order by count(*) desc;
select publication_status, count(*) from appointment.outbox_events group by publication_status order by publication_status;
select publication_status, count(*) from payment.payment_events_outbox group by publication_status order by publication_status;
"@

Invoke-Capture -Name "rabbitmq-queues.txt" -Block {
    $composeArgs = Get-ComposeArgs
    & docker @composeArgs exec -T rabbitmq rabbitmqctl list_queues name messages_ready messages_unacknowledged consumers
}

if ($SummaryFile -and (Test-Path -Path $SummaryFile)) {
    Copy-Item -LiteralPath $SummaryFile -Destination (Join-Path $target (Split-Path -Leaf $SummaryFile)) -Force
    Invoke-Capture -Name "k6-summary-counters.txt" -Block {
        $summary = Get-Content -Raw -Path $SummaryFile | ConvertFrom-Json
        @(
            "appointment_attempts=$($summary.metrics.appointment_attempts.values.count)"
            "appointments_created=$($summary.metrics.appointments_created.values.count)"
            "appointments_503=$($summary.metrics.appointments_503.values.count)"
            "appointments_503_json_gateway=$($summary.metrics.appointments_503_json_gateway.values.count)"
            "appointments_server_error=$($summary.metrics.appointments_server_error.values.count)"
            "appointments_timeout=$($summary.metrics.appointments_timeout.values.count)"
            "appointments_validation_error=$($summary.metrics.appointments_validation_error.values.count)"
            "appointments_conflict=$($summary.metrics.appointments_conflict.values.count)"
            "appointments_rate_limited=$($summary.metrics.appointments_rate_limited.values.count)"
            "dropped_iterations=$($summary.metrics.dropped_iterations.values.count)"
            "http_reqs=$($summary.metrics.http_reqs.values.count)"
            "http_req_duration_p95=$($summary.metrics.http_req_duration.values.'p(95)')"
            "http_req_duration_p99=$($summary.metrics.http_req_duration.values.'p(99)')"
        ) -join [Environment]::NewLine
    }
}

Write-Host "Patroni E2E diagnostics written to $target"

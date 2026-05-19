param(
    [string]$OutputDir = ".\infra\load-tests\appointments\results\evidence",
    [string]$Since = "15m",
    [string]$SummaryFile,
    [int]$SampleSeconds = 0,
    [int]$SampleIntervalSeconds = 5
)

$ErrorActionPreference = "Stop"

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$target = Join-Path $OutputDir "scaled-routing-$stamp"
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

Invoke-Capture -Name "docker-stats-snapshot.txt" -Block {
    docker stats --no-stream
}

Invoke-Capture -Name "gateway-env.txt" -Block {
    docker compose exec -T api-gateway printenv |
        Select-String -Pattern "APPOINTMENT_SERVICE_URL|SCHEDULE_SERVICE_URL|PATIENT_SERVICE_URL|GATEWAY_CB|GATEWAY_TIMELIMITER|GATEWAY_BULKHEAD|RATE_LIMIT_APPOINTMENT"
}

Invoke-Capture -Name "appointment-env.txt" -Block {
    docker compose exec -T appointment-service printenv |
        Select-String -Pattern "PATIENT_SERVICE_URL|SCHEDULE_SERVICE_URL|APPOINTMENT_CLIENT_CB|HIKARI|APPOINTMENT_HOLD"
}

Invoke-Capture -Name "api-gateway-fallback.log" -Block {
    docker compose logs --since $Since api-gateway |
        Select-String -Pattern "gateway_fallback|BulkheadFullException|CallNotPermitted|Timeout|TimeoutException|ConnectException|WebClient|PrematureClose|status=503 method=POST path=/api/appointments|CircuitBreaker" |
        Select-Object -First 300
}

Invoke-Capture -Name "api-gateway-503-count.txt" -Block {
    $matches = docker compose logs --since $Since api-gateway |
        Select-String -Pattern "status=503 method=POST path=/api/appointments"
    "gateway_503_count=$($matches.Count)"
}

Invoke-Capture -Name "appointment-lb.log" -Block {
    docker compose logs --since $Since appointment-lb |
        Select-String -Pattern "appointment_backend|DOWN|UP|Layer7|503|504|sD|SD|SC|PR|actuator|POST|health" |
        Select-Object -First 500
}

Invoke-Capture -Name "schedule-lb.log" -Block {
    docker compose logs --since $Since schedule-lb |
        Select-String -Pattern "schedule_backend|DOWN|UP|Layer7|503|504|sD|SD|SC|PR|actuator|GET|POST|health" |
        Select-Object -First 500
}

Invoke-Capture -Name "patient-lb.log" -Block {
    docker compose logs --since $Since patient-lb |
        Select-String -Pattern "patient_backend|DOWN|UP|Layer7|503|504|sD|SD|SC|PR|actuator|GET|POST|health" |
        Select-Object -First 500
}

Invoke-Capture -Name "appointment-service-errors.log" -Block {
    docker compose logs --since $Since appointment-service |
        Select-String -Pattern "ERROR|WARN|Exception|Hikari|timeout|timed out|CallNotPermitted|Connection refused|idempotency|outbox|lock|deadlock|confirm_skipped" |
        Select-Object -First 500
}

Invoke-Capture -Name "appointment-service-traffic-by-replica.txt" -Block {
    docker compose logs --since $Since appointment-service |
        Select-String -Pattern "Request completed|POST|/appointments|Created|appointment" |
        ForEach-Object {
            if ($_.Line -match '^([^ ]+)\s+\|') { $matches[1] }
        } |
        Group-Object |
        Sort-Object Name |
        Format-Table Name,Count -AutoSize
}

Invoke-Capture -Name "lb-health.txt" -Block {
    @(
        "appointment-lb:"
        docker compose exec -T appointment-lb wget -qO- http://127.0.0.1:8080/actuator/health
        ""
        "schedule-lb:"
        docker compose exec -T schedule-lb wget -qO- http://127.0.0.1:8080/actuator/health
        ""
        "patient-lb:"
        docker compose exec -T patient-lb wget -qO- http://127.0.0.1:8080/actuator/health
    )
}

Invoke-Capture -Name "pg-stat-activity.txt" -Block {
    docker compose exec -T postgres psql -U mediqueue -d mediqueue -c "select datname, usename, state, wait_event_type, wait_event, count(*) from pg_stat_activity group by datname, usename, state, wait_event_type, wait_event order by count(*) desc;"
}

Invoke-Capture -Name "pg-active-queries.txt" -Block {
    docker compose exec -T postgres psql -U mediqueue -d mediqueue -c "select pid, usename, state, wait_event_type, wait_event, now() - query_start as age, left(query, 220) as query from pg_stat_activity where datname = 'mediqueue' and state <> 'idle' order by age desc limit 50;"
}

Invoke-Capture -Name "pg-connections.txt" -Block {
    docker compose exec -T postgres psql -U mediqueue -d mediqueue -c "show max_connections; select count(*) as total_connections, count(*) filter (where state = 'active') as active_connections, count(*) filter (where wait_event_type is not null) as waiting_connections from pg_stat_activity;"
}

Invoke-Capture -Name "pg-locks.txt" -Block {
    docker compose exec -T postgres psql -U mediqueue -d mediqueue -c "select locktype, mode, granted, count(*) from pg_locks group by locktype, mode, granted order by count(*) desc;"
}

Invoke-Capture -Name "rabbitmq-queues.txt" -Block {
    docker compose exec -T rabbitmq rabbitmqctl list_queues name messages_ready messages_unacknowledged consumers
}

if ($SampleSeconds -gt 0) {
    $samplePath = Join-Path $target "live-samples.txt"
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($samplePath, "", $utf8NoBom)
    $deadline = (Get-Date).AddSeconds($SampleSeconds)
    $sample = 0

    while ((Get-Date) -lt $deadline) {
        $sample++
        Add-Content -Encoding utf8 -Path $samplePath -Value "===== sample $sample $(Get-Date -Format o) ====="
        Add-Content -Encoding utf8 -Path $samplePath -Value "--- docker stats ---"
        docker stats --no-stream | Out-String | Add-Content -Encoding utf8 -Path $samplePath
        Add-Content -Encoding utf8 -Path $samplePath -Value "--- pg connections/activity ---"
        docker compose exec -T postgres psql -U mediqueue -d mediqueue -c "select state, wait_event_type, wait_event, count(*) from pg_stat_activity group by state, wait_event_type, wait_event order by count(*) desc; select count(*) as total, count(*) filter (where state='active') as active from pg_stat_activity;" | Out-String | Add-Content -Encoding utf8 -Path $samplePath
        Add-Content -Encoding utf8 -Path $samplePath -Value "--- pg locks ---"
        docker compose exec -T postgres psql -U mediqueue -d mediqueue -c "select locktype, mode, granted, count(*) from pg_locks group by locktype, mode, granted order by count(*) desc;" | Out-String | Add-Content -Encoding utf8 -Path $samplePath
        Add-Content -Encoding utf8 -Path $samplePath -Value "--- rabbitmq queues ---"
        docker compose exec -T rabbitmq rabbitmqctl list_queues name messages_ready messages_unacknowledged consumers | Out-String | Add-Content -Encoding utf8 -Path $samplePath
        Start-Sleep -Seconds $SampleIntervalSeconds
    }
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
            "appointments_timeout=$($summary.metrics.appointments_timeout.values.count)"
            "appointments_validation_error=$($summary.metrics.appointments_validation_error.values.count)"
            "appointments_conflict=$($summary.metrics.appointments_conflict.values.count)"
            "appointments_rate_limited=$($summary.metrics.appointments_rate_limited.values.count)"
            "appointments_dataset_exhausted=$($summary.metrics.appointments_dataset_exhausted.values.count)"
            "dropped_iterations=$($summary.metrics.dropped_iterations.values.count)"
            "http_reqs=$($summary.metrics.http_reqs.values.count)"
            "http_req_duration_p95=$($summary.metrics.http_req_duration.values.'p(95)')"
            "http_req_duration_p99=$($summary.metrics.http_req_duration.values.'p(99)')"
        ) -join [Environment]::NewLine
    }
}

Write-Host "Scaled routing diagnostics written to $target"

param(
    [ValidateSet("single", "patroni")]
    [string]$DatabaseTarget = "single",
    [switch]$PurgeRabbitMqQueues,
    [switch]$ConfirmClean
)

$ErrorActionPreference = "Stop"

$candidateTables = @(
    "notification.notifications",
    "payment.payment_events_outbox",
    "payment.payment_idempotency",
    "payment.payments",
    "appointment.appointment_audit",
    "appointment.appointment_holds",
    "appointment.idempotency_keys",
    "appointment.outbox_events",
    "appointment.appointments",
    "schedule.dentist_slots",
    "schedule.dentists",
    "patient.patients"
)

$rabbitQueues = @(
    "payment.appointment-held.queue",
    "payment.succeeded",
    "payment.failed",
    "payment.succeeded.queue",
    "payment.failed.queue",
    "appointment.confirmed",
    "appointment.expired",
    "appointment.cancelled",
    "appointment.confirmed.queue",
    "appointment.expired.queue",
    "appointment.cancelled.queue",
    "notification.appointment.queue",
    "notification.payment.queue",
    "schedule.appointment.held",
    "schedule.appointment.confirmed",
    "schedule.appointment.expired",
    "schedule.appointment.cancelled"
)

function Get-ComposeArgs {
    if ($DatabaseTarget -eq "patroni") {
        return @("compose", "-f", "docker-compose.yml", "-f", "docker-compose.patroni.yml")
    }
    return @("compose")
}

function Invoke-DbRows {
    param([string]$Sql)

    $composeArgs = Get-ComposeArgs
    if ($DatabaseTarget -eq "patroni") {
        $output = $Sql | & docker @composeArgs exec -T -e PGPASSWORD=mediqueue patroni-postgres-1 psql -h patroni-postgres-lb -p 5432 -U mediqueue -d mediqueue -v ON_ERROR_STOP=1 -q -t -A -F "`t"
    } else {
        $output = $Sql | & docker @composeArgs exec -T postgres psql -U mediqueue -d mediqueue -v ON_ERROR_STOP=1 -q -t -A -F "`t"
    }

    if ($LASTEXITCODE -ne 0) {
        throw "psql query fallo con exit code $LASTEXITCODE"
    }
    return @($output | Where-Object { $_ -and $_.Trim().Length -gt 0 })
}

function Invoke-DbSql {
    param([string]$Sql)

    $composeArgs = Get-ComposeArgs
    if ($DatabaseTarget -eq "patroni") {
        $output = $Sql | & docker @composeArgs exec -T -e PGPASSWORD=mediqueue patroni-postgres-1 psql -h patroni-postgres-lb -p 5432 -U mediqueue -d mediqueue -v ON_ERROR_STOP=1 -q
    } else {
        $output = $Sql | & docker @composeArgs exec -T postgres psql -U mediqueue -d mediqueue -v ON_ERROR_STOP=1 -q
    }

    if ($LASTEXITCODE -ne 0) {
        throw "psql fallo con exit code $LASTEXITCODE"
    }
    return $output
}

function Assert-WriterReady {
    if ($DatabaseTarget -ne "patroni") {
        return
    }

    $rows = @(Invoke-DbRows -Sql "select pg_is_in_recovery();")
    if ($rows.Count -lt 1) {
        throw "No se pudo validar pg_is_in_recovery() contra Patroni writer."
    }

    $value = $rows[0].Trim().ToLowerInvariant()
    if ($value -ne "f" -and $value -ne "false") {
        throw "Patroni writer no esta listo para limpieza. pg_is_in_recovery()=$($rows[0])"
    }

    Write-Host "PATRONI_WRITER_PG_IS_IN_RECOVERY=false"
}

function Get-ExistingRuntimeTables {
    $values = ($candidateTables | ForEach-Object { "('$_')" }) -join ","
    $rows = Invoke-DbRows -Sql "select table_name from (values $values) as candidate(table_name) where to_regclass(candidate.table_name) is not null order by array_position(array[$(($candidateTables | ForEach-Object { "'$_'" }) -join "," )]::text[], table_name);"
    return @($rows)
}

function Get-TableCounts {
    param([string[]]$Tables)

    $counts = @()
    foreach ($table in $Tables) {
        if ($candidateTables -notcontains $table) {
            throw "Tabla no permitida para conteo runtime: $table"
        }
        $countRows = @(Invoke-DbRows -Sql "select count(*) from $table;")
        if ($countRows.Count -lt 1) {
            throw "No se pudo contar tabla runtime: $table"
        }
        $counts += [pscustomobject][ordered]@{
            table = $table
            rows = [int64]$countRows[0]
        }
    }
    return @($counts)
}

function Write-Counts {
    param(
        [string]$Label,
        [object[]]$Counts
    )

    Write-Host $Label
    foreach ($item in $Counts) {
        Write-Host "$($item.table)=$($item.rows)"
    }
}

function Invoke-RabbitMqPurge {
    if (-not $PurgeRabbitMqQueues) {
        return
    }

    if (-not $ConfirmClean) {
        Write-Host "RABBITMQ_DRY_RUN=True"
        Write-Host "RabbitMQ queues would be purged only with -ConfirmClean."
        foreach ($queue in $rabbitQueues) {
            Write-Host "RABBITMQ_QUEUE_PLAN=$queue"
        }
        return
    }

    Write-Host "Purging RabbitMQ queues. This removes pending async test messages."
    $composeArgs = Get-ComposeArgs
    $existingQueues = @(& docker @composeArgs exec -T rabbitmq rabbitmqctl list_queues -q name)
    if ($LASTEXITCODE -ne 0) {
        throw "No se pudieron listar colas RabbitMQ. exit code $LASTEXITCODE"
    }

    foreach ($queue in $rabbitQueues) {
        if ($existingQueues -contains $queue) {
            & docker @composeArgs exec -T rabbitmq rabbitmqctl purge_queue $queue | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "No se pudo purgar RabbitMQ queue=$queue exit_code=$LASTEXITCODE"
            }
            Write-Host "RABBITMQ_QUEUE_PURGED=$queue"
        } else {
            Write-Host "RABBITMQ_QUEUE_SKIPPED_NOT_FOUND=$queue"
        }
    }
}

Write-Host "Appointment runtime cleanup"
Write-Host "DatabaseTarget=$DatabaseTarget"
Write-Host "DryRun=$(-not $ConfirmClean)"
Write-Host "PurgeRabbitMqQueues=$($PurgeRabbitMqQueues.IsPresent)"

Assert-WriterReady

$existingTables = @(Get-ExistingRuntimeTables)
if ($existingTables.Count -lt 1) {
    Write-Host "No runtime/base tables were found. Nothing to clean."
    Invoke-RabbitMqPurge
    exit 0
}

$beforeCounts = @(Get-TableCounts -Tables $existingTables)
Write-Counts -Label "COUNTS_BEFORE" -Counts $beforeCounts

$tablesSql = $existingTables -join ", "
$truncateSql = @"
BEGIN;
TRUNCATE TABLE $tablesSql RESTART IDENTITY CASCADE;
COMMIT;
"@

Write-Host "TRUNCATE_PLAN_BEGIN"
Write-Host $truncateSql
Write-Host "TRUNCATE_PLAN_END"

if (-not $ConfirmClean) {
    Write-Host "CLEANUP_STATUS=DRY_RUN"
    Write-Host "No data was deleted. Re-run with -ConfirmClean to execute."
    Invoke-RabbitMqPurge
    exit 0
}

if ($PurgeRabbitMqQueues) {
    Write-Host "Purging RabbitMQ queues before database cleanup to avoid old async messages recreating runtime rows."
    Invoke-RabbitMqPurge
}

Write-Host "Executing runtime cleanup with TRUNCATE ... CASCADE."
Invoke-DbSql -Sql $truncateSql | Out-Null

$afterCounts = @(Get-TableCounts -Tables $existingTables)
Write-Counts -Label "COUNTS_AFTER" -Counts $afterCounts

if ($PurgeRabbitMqQueues) {
    Write-Host "Purging RabbitMQ queues after database cleanup to remove messages published during cleanup."
    Invoke-RabbitMqPurge
}

Write-Host "Runtime cleanup complete."

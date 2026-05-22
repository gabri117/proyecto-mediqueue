param(
    [switch]$PlanOnly,
    [switch]$UseLatestDump,
    [switch]$Execute,
    [switch]$RecreateDestination,
    [switch]$ConfirmRecreateDestination,
    [string]$DumpPath,
    [string]$SourceService = "postgres",
    [string]$SourceDatabase = "mediqueue",
    [string]$SourceUser = "mediqueue",
    [string]$TargetDatabase = "mediqueue",
    [string]$TargetAdminUser = "postgres",
    [string]$TargetAdminPassword = "postgres",
    [string]$TargetAppUser = "mediqueue",
    [string]$BackupScript = "infra\backups\scripts\backup-pgdump.ps1",
    [string]$DumpDirectory = "infra\backups\dumps"
)

$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..\..\..")
$mainComposeArgs = @("-f", "docker-compose.yml")
$patroniComposeArgs = @("-f", "docker-compose.yml", "-f", "docker-compose.patroni.yml")
$appSchemas = @("patient", "schedule", "appointment", "payment", "notification")

function Write-Step {
    param([string]$Message)
    Write-Host "MIGRATION_STEP $Message"
}

function Invoke-ComposeChecked {
    param(
        [string[]]$ComposeArgs,
        [string[]]$CommandArgs,
        [string]$Label
    )

    Write-Step "$Label start"
    docker compose @ComposeArgs @CommandArgs
    if ($LASTEXITCODE -ne 0) {
        throw "$Label failed with exit code $LASTEXITCODE"
    }
    Write-Step "$Label ok"
}

function Invoke-ComposeOutputChecked {
    param(
        [string[]]$ComposeArgs,
        [string[]]$CommandArgs,
        [string]$Label
    )

    Write-Step "$Label start"
    $output = docker compose @ComposeArgs @CommandArgs
    if ($LASTEXITCODE -ne 0) {
        $output | ForEach-Object { Write-Host $_ }
        throw "$Label failed with exit code $LASTEXITCODE"
    }
    Write-Step "$Label ok"
    return @($output)
}

function Get-LatestDump {
    $dumpRoot = Join-Path $root $DumpDirectory
    $latest = Get-ChildItem -Path $dumpRoot -Filter "*.dump" -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if (-not $latest) {
        throw "No pg_dump files found in $dumpRoot"
    }

    return $latest.FullName
}

function Resolve-DumpPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $null
    }

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return $Path
    }

    return (Join-Path $root $Path)
}

function Assert-DumpFile {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Dump file does not exist: $Path"
    }

    $item = Get-Item -LiteralPath $Path
    if ($item.Length -le 0) {
        throw "Dump file is empty: $Path"
    }

    Write-Host "MIGRATION_DUMP file=$Path bytes=$($item.Length)"
}

function Invoke-TargetSql {
    param(
        [string]$Database,
        [string]$Sql,
        [string]$Label
    )

    $Sql | docker compose @patroniComposeArgs exec -T -e "PGPASSWORD=$TargetAdminPassword" patroni-postgres-1 `
        psql -h patroni-postgres-lb -p 5432 -U $TargetAdminUser -d $Database -v ON_ERROR_STOP=1

    if ($LASTEXITCODE -ne 0) {
        throw "$Label failed with exit code $LASTEXITCODE"
    }
}

Push-Location $root
try {
    if ($PlanOnly -and $Execute) {
        throw "Use -PlanOnly or -Execute, not both."
    }

    if (-not $PlanOnly -and -not $Execute) {
        $PlanOnly = $true
    }

    if ($RecreateDestination -and -not $ConfirmRecreateDestination) {
        throw "Recreating destination requires -ConfirmRecreateDestination."
    }

    Write-Host "MIGRATION_MODE plan_only=$PlanOnly execute=$Execute use_latest_dump=$UseLatestDump recreate_destination=$RecreateDestination"

    Invoke-ComposeChecked -ComposeArgs $mainComposeArgs -CommandArgs @("config", "--quiet") -Label "compose-main-config"
    Invoke-ComposeChecked -ComposeArgs $patroniComposeArgs -CommandArgs @("config", "--quiet") -Label "compose-patroni-config"

    Invoke-ComposeChecked -ComposeArgs $mainComposeArgs -CommandArgs @("exec", "-T", $SourceService, "pg_isready", "-U", $SourceUser, "-d", $SourceDatabase) -Label "source-postgres-ready"

    $writerRows = Invoke-ComposeOutputChecked -ComposeArgs $patroniComposeArgs -CommandArgs @(
        "exec", "-T", "-e", "PGPASSWORD=$TargetAdminPassword", "patroni-postgres-1",
        "psql", "-h", "patroni-postgres-lb", "-p", "5432", "-U", $TargetAdminUser, "-d", "postgres",
        "-tAc", "SELECT CASE WHEN pg_is_in_recovery() THEN 'replica' ELSE 'leader' END"
    ) -Label "patroni-writer-role"

    $writerRole = ($writerRows | Where-Object { $_ -match "\S" } | Select-Object -Last 1).Trim()
    Write-Host "MIGRATION_WRITER_ROLE=$writerRole"
    if ($writerRole -ne "leader") {
        throw "patroni-postgres-lb writer is not pointing to a leader."
    }

    $selectedDump = Resolve-DumpPath -Path $DumpPath
    if ($UseLatestDump) {
        $selectedDump = Get-LatestDump
    }

    if (-not $selectedDump -and $PlanOnly) {
        Write-Host "MIGRATION_PLAN dump_source=generate_new_pg_dump script=$BackupScript"
    }
    elseif ($selectedDump) {
        Assert-DumpFile -Path $selectedDump
        Write-Host "MIGRATION_PLAN dump_source=selected_dump"
    }

    if ($PlanOnly) {
        Write-Host "MIGRATION_PLAN restore_will_run=False reason=PlanOnly"
        Write-Host "MIGRATION_PLAN stop_apps_before_execute=True"
        Write-Host "MIGRATION_PLAN target_writer=patroni-postgres-lb:5432 database=$TargetDatabase"
        Write-Host "MIGRATION_STATUS=PLAN_ONLY"
        exit 0
    }

    if (-not $selectedDump) {
        $backupScriptPath = Join-Path $root $BackupScript
        if (-not (Test-Path -LiteralPath $backupScriptPath)) {
            throw "Backup script does not exist: $backupScriptPath"
        }

        Write-Step "generate-pg-dump start"
        & $backupScriptPath
        if ($LASTEXITCODE -ne 0) {
            throw "backup-pgdump failed with exit code $LASTEXITCODE"
        }
        Write-Step "generate-pg-dump ok"
        $selectedDump = Get-LatestDump
    }

    Assert-DumpFile -Path $selectedDump

    $targetContainerDump = "/tmp/mediqueue_migration.dump"
    Invoke-ComposeChecked -ComposeArgs $patroniComposeArgs -CommandArgs @("cp", $selectedDump, "patroni-postgres-1:$targetContainerDump") -Label "copy-dump-to-patroni"

    if ($RecreateDestination) {
        Write-Host "MIGRATION_DESTINATION_RECREATE_CONFIRMED=True database=$TargetDatabase"
        $recreateSql = @"
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE datname = '$TargetDatabase'
  AND pid <> pg_backend_pid();
DROP DATABASE IF EXISTS "$TargetDatabase";
CREATE DATABASE "$TargetDatabase" OWNER "$TargetAppUser";
"@
        Invoke-TargetSql -Database "postgres" -Sql $recreateSql -Label "recreate-target-database"
    }

    Write-Step "restore-dump-to-patroni start"
    docker compose @patroniComposeArgs exec -T -e "PGPASSWORD=$TargetAdminPassword" patroni-postgres-1 `
        pg_restore -h patroni-postgres-lb -p 5432 -U $TargetAdminUser -d $TargetDatabase --no-owner --role $TargetAppUser --verbose $targetContainerDump
    if ($LASTEXITCODE -ne 0) {
        throw "pg_restore failed with exit code $LASTEXITCODE"
    }
    Write-Step "restore-dump-to-patroni ok"

    $validationSql = @"
SELECT 'writer_recovery', pg_is_in_recovery()::text;
SELECT 'schemas', string_agg(schema_name, ',' ORDER BY schema_name)
FROM information_schema.schemata
WHERE schema_name IN ('patient','schedule','appointment','payment','notification');
SELECT 'patient.patients' AS table_name, count(*)::bigint AS rows FROM patient.patients
UNION ALL SELECT 'schedule.dentists', count(*)::bigint FROM schedule.dentists
UNION ALL SELECT 'schedule.dentist_working_hours', count(*)::bigint FROM schedule.dentist_working_hours
UNION ALL SELECT 'schedule.dentist_slots', count(*)::bigint FROM schedule.dentist_slots
UNION ALL SELECT 'appointment.appointments', count(*)::bigint FROM appointment.appointments
UNION ALL SELECT 'appointment.appointment_holds', count(*)::bigint FROM appointment.appointment_holds
UNION ALL SELECT 'appointment.appointment_audit', count(*)::bigint FROM appointment.appointment_audit
UNION ALL SELECT 'appointment.idempotency_keys', count(*)::bigint FROM appointment.idempotency_keys
UNION ALL SELECT 'appointment.outbox_events', count(*)::bigint FROM appointment.outbox_events
UNION ALL SELECT 'payment.payments', count(*)::bigint FROM payment.payments
UNION ALL SELECT 'payment.payment_idempotency', count(*)::bigint FROM payment.payment_idempotency
UNION ALL SELECT 'payment.payment_events_outbox', count(*)::bigint FROM payment.payment_events_outbox
UNION ALL SELECT 'notification.notifications', count(*)::bigint FROM notification.notifications
ORDER BY table_name;
"@
    Invoke-TargetSql -Database $TargetDatabase -Sql $validationSql -Label "post-migration-validation"

    Invoke-ComposeChecked -ComposeArgs $patroniComposeArgs -CommandArgs @("exec", "-T", "patroni-postgres-1", "patronictl", "-c", "/etc/patroni/patroni.yml", "list") -Label "patronictl-list"

    Invoke-ComposeChecked -ComposeArgs $patroniComposeArgs -CommandArgs @("exec", "-T", "patroni-postgres-1", "rm", "-f", $targetContainerDump) -Label "cleanup-target-temp-dump"
    Write-Host "MIGRATION_STATUS=OK"
}
catch {
    Write-Host "MIGRATION_STATUS=ERROR message=$($_.Exception.Message)"
    exit 1
}
finally {
    Pop-Location
}

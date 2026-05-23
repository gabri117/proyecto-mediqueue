param(
    [string]$DumpFile,
    [string]$PostgresService = $env:MEDIQUEUE_BACKUP_POSTGRES_SERVICE,
    [string]$DatabaseUser = $env:MEDIQUEUE_BACKUP_DB_USER,
    [string]$BackupRoot = $env:MEDIQUEUE_BACKUP_ROOT,
    [string]$TestDatabaseName = "mediqueue_restore_test",
    [switch]$KeepDatabase
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\backup-common.ps1"
$cfg = Get-MediQueueBackupConfig
if (-not $PostgresService) { $PostgresService = $cfg.PostgresService }
if (-not $DatabaseUser) { $DatabaseUser = $cfg.DatabaseUser }
if (-not $BackupRoot) { $BackupRoot = $cfg.BackupRoot }
$BackupMode = $cfg.BackupMode

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logDir = Join-Path $BackupRoot "logs"
$restoreDir = Join-Path $BackupRoot "restore-test"
New-Item -ItemType Directory -Force -Path $logDir, $restoreDir | Out-Null
$logFile = Join-Path $logDir "restore-pgdump-test-$stamp.log"

function Write-Log {
    param([string]$Message)
    $line = "$(Get-Date -Format o) $Message"
    Write-Host $line
    Add-Content -Path $logFile -Value $line -Encoding utf8
}

function Invoke-Checked {
    param([string]$Label, [scriptblock]$Block)
    Write-Log "START $Label"
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        & $Block 2>&1 | Tee-Object -FilePath $logFile -Append
        $code = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    Write-Log "EXIT $Label code=$code"
    if ($null -ne $code -and $code -ne 0) {
        throw "$Label fallo con exit code $code"
    }
}

try {
    if (-not $DumpFile) {
        $DumpFile = Get-ChildItem -LiteralPath (Join-Path $BackupRoot "dumps") -File -Filter "mediqueue_dump_*.dump" |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1 |
            ForEach-Object { $_.FullName }
    }
    if (-not $DumpFile -or -not (Test-Path -LiteralPath $DumpFile)) {
        throw "DumpFile no encontrado. Especifica -DumpFile o crea un pg_dump primero."
    }

    Write-Log "BACKUP_MODE=$BackupMode"
    Invoke-Checked "docker info" { docker info }
    if ($BackupMode -eq "patroni") {
        Invoke-Checked "docker compose patroni ps" { docker compose -f docker-compose.yml -f docker-compose.patroni.yml ps }
        $PostgresService = Select-MediQueuePatroniRunnerService -Config $cfg
        Write-Log "PATRONI_RESTORE_RUNNER_SERVICE=$PostgresService"
        $writerRecovery = Invoke-MediQueueBackupDockerCompose -BackupMode $BackupMode -CommandArgs @("exec", "-T", "-e", "PGPASSWORD=$($cfg.PatroniAdminPassword)", $PostgresService, "psql", "-h", "patroni-postgres-lb", "-p", "5432", "-U", $($cfg.PatroniAdminUser), "-d", $($cfg.DatabaseName), "-At", "-v", "ON_ERROR_STOP=1", "-c", "SELECT pg_is_in_recovery();")
        if ($LASTEXITCODE -ne 0) {
            throw "No se pudo validar Patroni writer para restore test."
        }
        $writerRecovery = ([string]$writerRecovery).Trim()
        Write-Log "PATRONI_WRITER_PG_IS_IN_RECOVERY=$writerRecovery"
        if ($writerRecovery -ne "f") {
            throw "Patroni writer apunta a una replica; se aborta restore test."
        }
    } elseif ($BackupMode -eq "single") {
        Invoke-Checked "docker compose ps" { docker compose ps }
    } else {
        throw "BackupMode invalido: $BackupMode. Use single o patroni."
    }

    $testDb = $TestDatabaseName
    $containerDump = "/tmp/mediqueue_restore_test_$stamp.dump"
    $criticalCountsSql = @"
select 'appointment.appointments' as table_name, count(*) as row_count from appointment.appointments
union all
select 'patient.patients' as table_name, count(*) as row_count from patient.patients
union all
select 'payment.payments' as table_name, count(*) as row_count from payment.payments
union all
select 'schedule.dentist_slots' as table_name, count(*) as row_count from schedule.dentist_slots
order by table_name;
"@

    if ($BackupMode -eq "patroni") {
        $composeMode = $BackupMode
        $adminUser = $cfg.PatroniAdminUser
        $adminPassword = $cfg.PatroniAdminPassword
        Invoke-Checked "copy dump into patroni runner container" { Copy-MediQueueBackupToContainer -BackupMode $composeMode -Service $PostgresService -HostPath $DumpFile -ContainerPath $containerDump }
        Invoke-Checked "drop existing restore test database via writer" { Invoke-MediQueueBackupDockerCompose -BackupMode $composeMode -CommandArgs @("exec", "-T", "-e", "PGPASSWORD=$adminPassword", "-e", "PGOPTIONS=-c client_min_messages=warning", $PostgresService, "psql", "-h", "patroni-postgres-lb", "-p", "5432", "-U", $adminUser, "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-c", "DROP DATABASE IF EXISTS $testDb WITH (FORCE);") }
        Invoke-Checked "create restore test database via writer" { Invoke-MediQueueBackupDockerCompose -BackupMode $composeMode -CommandArgs @("exec", "-T", "-e", "PGPASSWORD=$adminPassword", $PostgresService, "psql", "-h", "patroni-postgres-lb", "-p", "5432", "-U", $adminUser, "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-c", "CREATE DATABASE $testDb;") }
        Invoke-Checked "restore pg_dump into test database via writer" { Invoke-MediQueueBackupDockerCompose -BackupMode $composeMode -CommandArgs @("exec", "-T", "-e", "PGPASSWORD=$adminPassword", $PostgresService, "pg_restore", "-h", "patroni-postgres-lb", "-p", "5432", "-U", $adminUser, "-d", $testDb, "--no-owner", $containerDump) }
        Invoke-Checked "verify restored schemas via writer" { Invoke-MediQueueBackupDockerCompose -BackupMode $composeMode -CommandArgs @("exec", "-T", "-e", "PGPASSWORD=$adminPassword", $PostgresService, "psql", "-h", "patroni-postgres-lb", "-p", "5432", "-U", $adminUser, "-d", $testDb, "-c", "select table_schema, count(*) from information_schema.tables where table_schema in ('appointment','patient','schedule','payment','notification') group by table_schema order by table_schema;") }
        Invoke-Checked "verify critical table counts via writer" {
            Invoke-MediQueueBackupDockerCompose -BackupMode $composeMode -CommandArgs @("exec", "-T", "-e", "PGPASSWORD=$adminPassword", $PostgresService, "psql", "-h", "patroni-postgres-lb", "-p", "5432", "-U", $adminUser, "-d", $testDb, "-v", "ON_ERROR_STOP=1", "-c", $criticalCountsSql)
        }
    } else {
        Invoke-Checked "copy dump into postgres container" { Copy-MediQueueBackupToContainer -BackupMode $BackupMode -Service $PostgresService -HostPath $DumpFile -ContainerPath $containerDump }
        Invoke-Checked "drop existing restore test database" { docker compose exec -T $PostgresService dropdb -U $DatabaseUser --if-exists $testDb }
        Invoke-Checked "create restore test database" { docker compose exec -T $PostgresService createdb -U $DatabaseUser $testDb }
        Invoke-Checked "restore pg_dump into test database" { docker compose exec -T $PostgresService pg_restore -U $DatabaseUser -d $testDb --no-owner $containerDump }
        Invoke-Checked "verify restored schemas" { docker compose exec -T $PostgresService psql -U $DatabaseUser -d $testDb -c "select table_schema, count(*) from information_schema.tables where table_schema in ('appointment','patient','schedule','payment','notification') group by table_schema order by table_schema;" }
        Invoke-Checked "verify critical table counts" {
            docker compose exec -T $PostgresService psql -U $DatabaseUser -d $testDb -v "ON_ERROR_STOP=1" -c $criticalCountsSql
        }
    }

    if (-not $KeepDatabase) {
        if ($BackupMode -eq "patroni") {
            Invoke-Checked "drop restore test database via writer" { Invoke-MediQueueBackupDockerCompose -BackupMode $BackupMode -CommandArgs @("exec", "-T", "-e", "PGPASSWORD=$($cfg.PatroniAdminPassword)", "-e", "PGOPTIONS=-c client_min_messages=warning", $PostgresService, "psql", "-h", "patroni-postgres-lb", "-p", "5432", "-U", $($cfg.PatroniAdminUser), "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-c", "DROP DATABASE IF EXISTS $testDb WITH (FORCE);") }
        } else {
            Invoke-Checked "drop restore test database" { docker compose exec -T $PostgresService dropdb -U $DatabaseUser $testDb }
        }
    } else {
        Write-Log "KEEP_DATABASE name=$testDb"
    }
    if ($BackupMode -eq "patroni") {
        Invoke-Checked "cleanup patroni runner temp dump" { Invoke-MediQueueBackupDockerCompose -BackupMode $BackupMode -CommandArgs @("exec", "-T", "-u", "root", $PostgresService, "rm", "-f", $containerDump) }
    } else {
        Invoke-Checked "cleanup container temp dump" { docker compose exec -T -u root $PostgresService rm -f $containerDump }
    }

    Write-Log "RESTORE_PGDUMP_TEST_OK dump=$DumpFile"
    exit 0
} catch {
    Write-Log "ERROR $($_.Exception.Message)"
    exit 1
}

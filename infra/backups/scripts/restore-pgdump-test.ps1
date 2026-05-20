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
    & $Block 2>&1 | Tee-Object -FilePath $logFile -Append
    $code = $LASTEXITCODE
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

    Invoke-Checked "docker info" { docker info }
    Invoke-Checked "docker compose ps" { docker compose ps }

    $testDb = $TestDatabaseName
    $containerDump = "/tmp/mediqueue_restore_test_$stamp.dump"

    Invoke-Checked "copy dump into postgres container" { docker compose cp $DumpFile "${PostgresService}:$containerDump" }
    Invoke-Checked "drop existing restore test database" { docker compose exec -T $PostgresService dropdb -U $DatabaseUser --if-exists $testDb }
    Invoke-Checked "create restore test database" { docker compose exec -T $PostgresService createdb -U $DatabaseUser $testDb }
    Invoke-Checked "restore pg_dump into test database" { docker compose exec -T $PostgresService pg_restore -U $DatabaseUser -d $testDb --no-owner $containerDump }
    Invoke-Checked "verify restored schemas" { docker compose exec -T $PostgresService psql -U $DatabaseUser -d $testDb -c "select table_schema, count(*) from information_schema.tables where table_schema in ('appointment','patient','schedule','payment','notification') group by table_schema order by table_schema;" }
    Invoke-Checked "verify critical table counts" {
        docker compose exec -T $PostgresService bash -lc "set -e; for t in appointment.appointments patient.patients schedule.dentist_slots payment.payments; do exists=`$(psql -U '$DatabaseUser' -d '$testDb' -Atc `"select to_regclass('$t');`"); if [ -n `"`$exists`" ]; then psql -U '$DatabaseUser' -d '$testDb' -c `"select '$t' as table_name, count(*) from $t;`"; else echo `"MISSING table=$t`"; fi; done"
    }

    if (-not $KeepDatabase) {
        Invoke-Checked "drop restore test database" { docker compose exec -T $PostgresService dropdb -U $DatabaseUser $testDb }
    } else {
        Write-Log "KEEP_DATABASE name=$testDb"
    }
    Invoke-Checked "cleanup container temp dump" { docker compose exec -T $PostgresService rm -f $containerDump }

    Write-Log "RESTORE_PGDUMP_TEST_OK dump=$DumpFile"
    exit 0
} catch {
    Write-Log "ERROR $($_.Exception.Message)"
    exit 1
}

param(
    [string]$PostgresService = $env:MEDIQUEUE_BACKUP_POSTGRES_SERVICE,
    [string]$DatabaseName = $env:MEDIQUEUE_BACKUP_DB_NAME,
    [string]$DatabaseUser = $env:MEDIQUEUE_BACKUP_DB_USER,
    [string]$BackupRoot = $env:MEDIQUEUE_BACKUP_ROOT,
    [string]$GoogleDrivePath = $env:MEDIQUEUE_BACKUP_GOOGLE_DRIVE_PATH
)

$ErrorActionPreference = "Stop"
if (-not $PostgresService) { $PostgresService = "postgres" }
if (-not $DatabaseName) { $DatabaseName = "mediqueue" }
if (-not $DatabaseUser) { $DatabaseUser = "mediqueue" }
if (-not $BackupRoot) { $BackupRoot = ".\infra\backups" }

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logDir = Join-Path $BackupRoot "logs"
$dumpDir = Join-Path $BackupRoot "dumps"
New-Item -ItemType Directory -Force -Path $logDir, $dumpDir | Out-Null
$logFile = Join-Path $logDir "backup-pgdump-$stamp.log"

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
    Invoke-Checked "docker info" { docker info }
    Invoke-Checked "docker compose ps" { docker compose ps }
    Invoke-Checked "postgres readiness" { docker compose exec -T $PostgresService pg_isready -U $DatabaseUser -d $DatabaseName }

    $containerDump = "/tmp/mediqueue_dump_$stamp.dump"
    $localDump = Join-Path $dumpDir "mediqueue_dump_$stamp.dump"
    $cmd = "set -euo pipefail; rm -f '$containerDump'; export PGPASSWORD=`"`$POSTGRES_PASSWORD`"; pg_dump -U '$DatabaseUser' -d '$DatabaseName' -Fc -f '$containerDump'; test -s '$containerDump'; pg_restore -l '$containerDump' >/tmp/mediqueue_dump_$stamp.list"

    Invoke-Checked "pg_dump custom format" { docker compose exec -T $PostgresService bash -lc $cmd }
    Invoke-Checked "copy pg_dump to host" { docker compose cp "${PostgresService}:$containerDump" $localDump }
    Invoke-Checked "cleanup container temp dump" { docker compose exec -T $PostgresService bash -lc "rm -f '$containerDump' /tmp/mediqueue_dump_$stamp.list" }

    if (-not (Test-Path -LiteralPath $localDump) -or (Get-Item -LiteralPath $localDump).Length -le 0) {
        throw "pg_dump no fue creado o esta vacio: $localDump"
    }

    Write-Log "PGDUMP_OK file=$localDump bytes=$((Get-Item -LiteralPath $localDump).Length)"

    if ($GoogleDrivePath) {
        New-Item -ItemType Directory -Force -Path $GoogleDrivePath | Out-Null
        Copy-Item -LiteralPath $localDump -Destination $GoogleDrivePath -Force
        Write-Log "GOOGLE_DRIVE_COPY_OK destination=$GoogleDrivePath"
    }

    exit 0
} catch {
    Write-Log "ERROR $($_.Exception.Message)"
    exit 1
}

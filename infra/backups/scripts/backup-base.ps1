param(
    [string]$PostgresService = $env:MEDIQUEUE_BACKUP_POSTGRES_SERVICE,
    [string]$DatabaseName = $env:MEDIQUEUE_BACKUP_DB_NAME,
    [string]$DatabaseUser = $env:MEDIQUEUE_BACKUP_DB_USER,
    [string]$BackupRoot = $env:MEDIQUEUE_BACKUP_ROOT,
    [string]$GoogleDrivePath = $env:MEDIQUEUE_BACKUP_GOOGLE_DRIVE_PATH
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\backup-common.ps1"
$cfg = Get-MediQueueBackupConfig
if (-not $PostgresService) { $PostgresService = $cfg.PostgresService }
if (-not $DatabaseName) { $DatabaseName = $cfg.DatabaseName }
if (-not $DatabaseUser) { $DatabaseUser = $cfg.DatabaseUser }
if (-not $BackupRoot) { $BackupRoot = $cfg.BackupRoot }
if (-not $GoogleDrivePath) { $GoogleDrivePath = $cfg.GoogleDriveBackupPath }

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logDir = Join-Path $BackupRoot "logs"
$localDir = Join-Path $BackupRoot "local"
New-Item -ItemType Directory -Force -Path $logDir, $localDir | Out-Null
$logFile = Join-Path $logDir "backup-base-$stamp.log"

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

    $containerDir = "/backups/mediqueue_base_$stamp"
    $localBackupDir = Join-Path $localDir "mediqueue_base_$stamp"

    $cmd = "set -euo pipefail; rm -rf '$containerDir'; mkdir -p '$containerDir'; export PGPASSWORD=`"`$POSTGRES_PASSWORD`"; pg_basebackup -U '$DatabaseUser' -D '$containerDir' -Ft -z -X stream -c fast --manifest-checksums=SHA256; test -s '$containerDir/base.tar.gz'; test -s '$containerDir/backup_manifest'; sha256sum '$containerDir'/* > '$containerDir/SHA256SUMS'"
    Invoke-Checked "pg_basebackup physical base backup" { docker compose exec -T $PostgresService bash -lc $cmd }

    if (-not (Test-Path -LiteralPath $localBackupDir)) {
        throw "Backup base no fue creado: $localBackupDir"
    }

    $baseTar = Join-Path $localBackupDir "base.tar.gz"
    $manifest = Join-Path $localBackupDir "backup_manifest"
    if (-not (Test-Path -LiteralPath $baseTar) -or (Get-Item -LiteralPath $baseTar).Length -le 0) {
        throw "base.tar.gz no fue creado o esta vacio: $baseTar"
    }
    if (-not (Test-Path -LiteralPath $manifest) -or (Get-Item -LiteralPath $manifest).Length -le 0) {
        throw "backup_manifest no fue creado o esta vacio: $manifest"
    }

    Write-Log "BASE_BACKUP_OK dir=$localBackupDir baseTarBytes=$((Get-Item -LiteralPath $baseTar).Length)"

    if ($GoogleDrivePath) {
        New-Item -ItemType Directory -Force -Path $GoogleDrivePath | Out-Null
        Copy-Item -LiteralPath $localBackupDir -Destination $GoogleDrivePath -Recurse -Force
        Write-Log "GOOGLE_DRIVE_COPY_OK destination=$GoogleDrivePath"
    }

    exit 0
} catch {
    Write-Log "ERROR $($_.Exception.Message)"
    exit 1
}

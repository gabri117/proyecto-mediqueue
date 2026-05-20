param(
    [string]$BaseBackupFile,
    [string]$WalArchiveDir,
    [string]$BackupRoot = $env:MEDIQUEUE_BACKUP_ROOT,
    [datetime]$RecoveryTargetTime,
    [switch]$PlanOnly
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\backup-common.ps1"
$cfg = Get-MediQueueBackupConfig
if (-not $BackupRoot) { $BackupRoot = $cfg.BackupRoot }

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logDir = Join-Path $BackupRoot "logs"
$restoreDir = Join-Path $BackupRoot "restore-test"
New-Item -ItemType Directory -Force -Path $logDir, $restoreDir | Out-Null
$logFile = Join-Path $logDir "restore-pitr-test-$stamp.log"

function Write-Log {
    param([string]$Message)
    $line = "$(Get-Date -Format o) $Message"
    Write-Host $line
    Add-Content -Path $logFile -Value $line -Encoding utf8
}

try {
    if (-not $BaseBackupFile) {
        $BaseBackupFile = Get-ChildItem -LiteralPath (Join-Path $BackupRoot "local") -Directory -Filter "mediqueue_base_*" |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1 |
            ForEach-Object { $_.FullName }
    }
    if (-not $WalArchiveDir) {
        $WalArchiveDir = Get-ChildItem -LiteralPath (Join-Path $BackupRoot "wal-archive") -Directory -Filter "wal_*" |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1 |
            ForEach-Object { $_.FullName }
    }

    if (-not $BaseBackupFile -or -not (Test-Path -LiteralPath $BaseBackupFile)) {
        throw "No existe backup base para PITR."
    }
    if (-not $WalArchiveDir -or -not (Test-Path -LiteralPath $WalArchiveDir)) {
        throw "No existe directorio WAL para PITR."
    }

    $walFiles = Get-ChildItem -LiteralPath $WalArchiveDir -File -Recurse | Where-Object { $_.Name -ne ".gitkeep" }
    if ($walFiles.Count -lt 1) {
        throw "El directorio WAL no contiene archivos."
    }

    $baseItem = Get-Item -LiteralPath $BaseBackupFile
    $baseTar = if ($baseItem.PSIsContainer) { Join-Path $baseItem.FullName "base.tar.gz" } else { $baseItem.FullName }
    $manifest = if ($baseItem.PSIsContainer) { Join-Path $baseItem.FullName "backup_manifest" } else { $null }
    if (-not (Test-Path -LiteralPath $baseTar)) {
        throw "No se encontro base.tar.gz en el backup base: $BaseBackupFile"
    }
    if ($manifest -and -not (Test-Path -LiteralPath $manifest)) {
        throw "No se encontro backup_manifest en el backup base: $BaseBackupFile"
    }

    $pitrDir = Join-Path $restoreDir "pitr_$stamp"
    New-Item -ItemType Directory -Force -Path $pitrDir | Out-Null
    $planFile = Join-Path $pitrDir "PITR_PLAN.txt"

    Write-Log "PITR_INPUT_OK base=$BaseBackupFile walDir=$WalArchiveDir walFiles=$($walFiles.Count)"
    if ($RecoveryTargetTime) {
        Write-Log "RECOVERY_TARGET_TIME=$($RecoveryTargetTime.ToString('o'))"
    }

    $targetLine = if ($RecoveryTargetTime) {
        "recovery_target_time = '$($RecoveryTargetTime.ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ss")) UTC'"
    } else {
        "# recovery_target_time not set; PostgreSQL will recover to latest available WAL"
    }

    $plan = @"
PITR restore test plan:
1. Create an isolated restore directory, never the production compose volume:
   $pitrDir

2. Extract the physical base backup:
   tar -xzf "$baseTar" -C "$pitrDir\pgdata"

3. If present, extract pg_wal.tar.gz into pgdata\pg_wal.

4. Create pgdata\recovery.signal.

5. Append to pgdata\postgresql.auto.conf:
   restore_command = 'copy "$WalArchiveDir\%f" "%p"'
   $targetLine

6. Start an isolated PostgreSQL 16 container with pgdata mounted as PGDATA.

7. Verify schemas/tables, then remove the test container and restore directory if the test passed.

This script validates PITR inputs and writes this plan. It does not start a restore container automatically in this phase, to avoid touching production Docker volumes by mistake.
"@
    Write-Log $plan
    [System.IO.File]::WriteAllText($planFile, $plan, (New-Object System.Text.UTF8Encoding($false)))
    Write-Log "PITR_PLAN_WRITTEN file=$planFile"

    if (-not $PlanOnly) {
        Write-Log "PITR_FULL_RESTORE_NOT_AUTOMATED Para evitar tocar volumenes reales, ejecuta el plan mensual en un entorno aislado."
    }

    exit 0
} catch {
    Write-Log "ERROR $($_.Exception.Message)"
    exit 1
}

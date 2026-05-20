param(
    [string]$BackupRoot = $env:MEDIQUEUE_BACKUP_ROOT,
    [int]$BaseRetentionDays = $(if ($env:MEDIQUEUE_BASE_RETENTION_DAYS) { [int]$env:MEDIQUEUE_BASE_RETENTION_DAYS } else { 14 }),
    [int]$WalRetentionDays = $(if ($env:MEDIQUEUE_WAL_RETENTION_DAYS) { [int]$env:MEDIQUEUE_WAL_RETENTION_DAYS } else { 14 }),
    [int]$DumpRetentionDays = $(if ($env:MEDIQUEUE_DUMP_RETENTION_DAYS) { [int]$env:MEDIQUEUE_DUMP_RETENTION_DAYS } else { 30 }),
    [int]$WeeklyRetentionDays = 56,
    [int]$MonthlyRetentionDays = 365,
    [switch]$DryRun,
    [switch]$WhatIfOnly,
    [switch]$ConfirmDelete
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\backup-common.ps1"
$cfg = Get-MediQueueBackupConfig
if (-not $BackupRoot) { $BackupRoot = $cfg.BackupRoot }

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logDir = Join-Path $BackupRoot "logs"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$logFile = Join-Path $logDir "cleanup-backups-$stamp.log"

function Write-Log {
    param([string]$Message)
    $line = "$(Get-Date -Format o) $Message"
    Write-Host $line
    Add-Content -Path $logFile -Value $line -Encoding utf8
}

function Remove-OldItems {
    param(
        [string]$Path,
        [string]$Pattern,
        [int]$RetentionDays,
        [switch]$Directory
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Log "SKIP missing path=$Path"
        return
    }

    $cutoff = (Get-Date).AddDays(-$RetentionDays)
    $today = (Get-Date).Date
    $items = if ($Directory) {
        Get-ChildItem -LiteralPath $Path -Directory -Filter $Pattern -ErrorAction Stop
    } else {
        Get-ChildItem -LiteralPath $Path -File -Filter $Pattern -ErrorAction Stop
    }

    foreach ($item in $items | Where-Object { $_.LastWriteTime -lt $cutoff -and $_.LastWriteTime.Date -lt $today -and $_.Name -ne ".gitkeep" }) {
        Write-Log "DELETE_CANDIDATE path=$($item.FullName) lastWrite=$($item.LastWriteTime) retentionDays=$RetentionDays"
        if ($ConfirmDelete -and -not $DryRun -and -not $WhatIfOnly) {
            Remove-Item -LiteralPath $item.FullName -Recurse -Force
            Write-Log "DELETED path=$($item.FullName)"
        } else {
            Write-Log "DRY_RUN_KEEP path=$($item.FullName)"
        }
    }
}

try {
    if (-not $ConfirmDelete) {
        Write-Log "SAFE_MODE dry-run activo. Para eliminar usa -ConfirmDelete. Tambien puedes pasar -DryRun explicitamente."
    }
    Remove-OldItems -Path (Join-Path $BackupRoot "local") -Pattern "mediqueue_base_*" -RetentionDays $BaseRetentionDays -Directory
    Remove-OldItems -Path (Join-Path $BackupRoot "dumps") -Pattern "mediqueue_dump_*.dump" -RetentionDays $DumpRetentionDays
    Remove-OldItems -Path (Join-Path $BackupRoot "dumps") -Pattern "mediqueue_dump_*.dump.sha256" -RetentionDays $DumpRetentionDays
    Remove-OldItems -Path (Join-Path $BackupRoot "dumps") -Pattern "mediqueue_dump_*.dump.gpg" -RetentionDays $DumpRetentionDays
    Remove-OldItems -Path (Join-Path $BackupRoot "wal-archive") -Pattern "wal_*" -RetentionDays $WalRetentionDays -Directory
    Remove-OldItems -Path (Join-Path $BackupRoot "weekly") -Pattern "*" -RetentionDays $WeeklyRetentionDays -Directory
    Remove-OldItems -Path (Join-Path $BackupRoot "monthly") -Pattern "*" -RetentionDays $MonthlyRetentionDays -Directory
    Write-Log "CLEANUP_OK dryRun=$($DryRun -or $WhatIfOnly -or -not $ConfirmDelete) confirmDelete=$ConfirmDelete"
    exit 0
} catch {
    Write-Log "ERROR $($_.Exception.Message)"
    exit 1
}

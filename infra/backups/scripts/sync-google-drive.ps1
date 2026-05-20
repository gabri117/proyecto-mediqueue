param(
    [string]$BackupRoot,
    [string]$DestinationPath,
    [string]$RcloneRemote = $env:MEDIQUEUE_BACKUP_RCLONE_REMOTE,
    [switch]$VerifyOnly,
    [switch]$OpenDestination
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\backup-common.ps1"
$cfg = Get-MediQueueBackupConfig
if (-not $BackupRoot) { $BackupRoot = $cfg.BackupRoot }
if (-not $DestinationPath) { $DestinationPath = $cfg.GoogleDriveBackupPath }

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logDir = Join-Path $BackupRoot "logs"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$logFile = Join-Path $logDir "sync-google-drive-$stamp.log"

function Write-Log {
    param([string]$Message)
    $line = "$(Get-Date -Format o) $Message"
    Write-Host $line
    Add-Content -Path $logFile -Value $line -Encoding utf8
}

function Copy-BackupFolder {
    param([string]$Name)
    $source = Join-Path $BackupRoot $Name
    $destination = Join-Path $DestinationPath $Name
    if (-not (Test-Path -LiteralPath $source)) {
        Write-Log "SKIP missing source=$source"
        return
    }
    New-Item -ItemType Directory -Force -Path $destination | Out-Null
    if (-not $VerifyOnly) {
        $items = Get-ChildItem -LiteralPath $source -Force -ErrorAction SilentlyContinue
        foreach ($item in $items) {
            Copy-Item -LiteralPath $item.FullName -Destination $destination -Recurse -Force
        }
        Write-Log "COPIED folder=$Name destination=$destination"
    } else {
        Write-Log "VERIFY_ONLY folder=$Name destination=$destination"
    }
}

function Test-DriveContents {
    $sourceTotal = [ordered]@{ Count = 0; Bytes = 0 }
    $destTotal = [ordered]@{ Count = 0; Bytes = 0 }
    foreach ($folder in @("dumps", "local", "wal-archive", "logs")) {
        $sourceStats = Get-DirectoryStats -Path (Join-Path $BackupRoot $folder)
        $destStats = Get-DirectoryStats -Path (Join-Path $DestinationPath $folder)
        Write-Log "FOLDER_STATS folder=$folder source_count=$($sourceStats.Count) dest_count=$($destStats.Count) source_bytes=$($sourceStats.Bytes) dest_bytes=$($destStats.Bytes)"
        $sourceTotal.Count += $sourceStats.Count
        $sourceTotal.Bytes += $sourceStats.Bytes
        $destTotal.Count += $destStats.Count
        $destTotal.Bytes += $destStats.Bytes
    }

    Write-Log "SOURCE_COUNT=$($sourceTotal.Count)"
    Write-Log "DEST_COUNT=$($destTotal.Count)"
    Write-Log "SOURCE_BYTES=$($sourceTotal.Bytes)"
    Write-Log "DEST_BYTES=$($destTotal.Bytes)"

    $lastFiles = Get-ChildItem -LiteralPath $DestinationPath -File -Recurse -Force |
        Where-Object { $_.Name -ne ".gitkeep" } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 10
    Write-Log "LAST_COPIED_FILES_START"
    foreach ($file in $lastFiles) {
        Write-Log "LAST_COPIED_FILE path=$($file.FullName) bytes=$($file.Length) lastWrite=$($file.LastWriteTime)"
    }
    Write-Log "LAST_COPIED_FILES_END"

    $hasDump = [bool](Get-ChildItem -LiteralPath (Join-Path $DestinationPath "dumps") -File -Filter "*.dump" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1)
    $hasChecksum = [bool](Get-ChildItem -LiteralPath (Join-Path $DestinationPath "dumps") -File -Filter "*.sha256" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1)
    $hasBase = [bool](Get-ChildItem -LiteralPath (Join-Path $DestinationPath "local") -Directory -Filter "mediqueue_base_*" -ErrorAction SilentlyContinue | Select-Object -First 1)
    $recentWal = Get-ChildItem -LiteralPath (Join-Path $DestinationPath "wal-archive") -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne ".gitkeep" } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    $hasRecentWal = $null -ne $recentWal -and $recentWal.LastWriteTime -ge (Get-Date).AddMinutes(-30)

    Write-Log "HAS_DUMP=$hasDump"
    Write-Log "HAS_SHA256=$hasChecksum"
    Write-Log "HAS_BASE_BACKUP=$hasBase"
    Write-Log "HAS_RECENT_WAL=$hasRecentWal"

    if ($destTotal.Count -lt 1 -or $destTotal.Bytes -lt 1) {
        throw "Destino Google Drive local quedo vacio: $DestinationPath"
    }
    if (-not $hasDump) { throw "No se encontro ningun .dump en destino." }
    if (-not $hasChecksum) { throw "No se encontro ningun .sha256 en destino." }
    if (-not $hasBase) { throw "No se encontro backup base en destino." }
    if (-not $hasRecentWal) { Write-Log "WARN No se encontro WAL reciente en destino." }
}

try {
    if ($RcloneRemote) {
        $rclone = Get-Command rclone -ErrorAction SilentlyContinue
        if (-not $rclone) { throw "MEDIQUEUE_BACKUP_RCLONE_REMOTE esta definido, pero rclone no esta en PATH." }
        if ($VerifyOnly) { throw "-VerifyOnly no esta soportado para rclone en esta fase." }
        foreach ($folder in @("dumps", "local", "wal-archive", "logs")) {
            $source = Join-Path $BackupRoot $folder
            if (Test-Path -LiteralPath $source) {
                Write-Log "RCLONE_SYNC source=$source remote=$RcloneRemote/$folder"
                rclone sync $source "$RcloneRemote/$folder"
                if ($LASTEXITCODE -ne 0) { throw "rclone sync fallo para $folder" }
            }
        }
        Write-Log "SYNC_OK mode=rclone remote=$RcloneRemote"
        exit 0
    }

    if (-not $DestinationPath) {
        throw "Define `$GoogleDriveBackupPath en infra/backups/config/backup.local.ps1 o pasa -DestinationPath."
    }

    New-Item -ItemType Directory -Force -Path $DestinationPath | Out-Null
    foreach ($folder in @("dumps", "local", "wal-archive", "logs")) {
        Copy-BackupFolder -Name $folder
    }

    Test-DriveContents
    Write-Log "SYNC_OK mode=local-google-drive-folder destination=$DestinationPath"

    if ($OpenDestination) {
        Start-Process explorer.exe -ArgumentList $DestinationPath
    }
    exit 0
} catch {
    Write-Log "ERROR $($_.Exception.Message)"
    if ($OpenDestination -and $DestinationPath -and (Test-Path -LiteralPath $DestinationPath)) {
        Start-Process explorer.exe -ArgumentList $DestinationPath
    }
    exit 1
}

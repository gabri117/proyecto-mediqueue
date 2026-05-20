param(
    [string]$BackupRoot = $env:MEDIQUEUE_BACKUP_ROOT,
    [string]$GoogleDrivePath = $(if ($env:GOOGLE_DRIVE_BACKUP_PATH) { $env:GOOGLE_DRIVE_BACKUP_PATH } else { $env:MEDIQUEUE_BACKUP_GOOGLE_DRIVE_PATH }),
    [string]$RcloneRemote = $env:MEDIQUEUE_BACKUP_RCLONE_REMOTE
)

$ErrorActionPreference = "Stop"
if (-not $BackupRoot) { $BackupRoot = ".\infra\backups" }

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
    param([string]$Name, [string]$DestinationRoot)
    $source = Join-Path $BackupRoot $Name
    if (-not (Test-Path -LiteralPath $source)) {
        Write-Log "SKIP missing source=$source"
        return
    }
    $destination = Join-Path $DestinationRoot $Name
    New-Item -ItemType Directory -Force -Path $destination | Out-Null
    Copy-Item -LiteralPath (Join-Path $source "*") -Destination $destination -Recurse -Force
    Write-Log "COPIED folder=$Name destination=$destination"
}

try {
    if ($RcloneRemote) {
        $rclone = Get-Command rclone -ErrorAction SilentlyContinue
        if (-not $rclone) {
            throw "MEDIQUEUE_BACKUP_RCLONE_REMOTE esta definido, pero rclone no esta en PATH."
        }
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

    if (-not $GoogleDrivePath) {
        throw "Define GOOGLE_DRIVE_BACKUP_PATH o MEDIQUEUE_BACKUP_GOOGLE_DRIVE_PATH apuntando a una carpeta local sincronizada por Google Drive Desktop, o MEDIQUEUE_BACKUP_RCLONE_REMOTE para rclone."
    }

    New-Item -ItemType Directory -Force -Path $GoogleDrivePath | Out-Null
    foreach ($folder in @("dumps", "local", "wal-archive", "logs")) {
        Copy-BackupFolder -Name $folder -DestinationRoot $GoogleDrivePath
    }

    Write-Log "SYNC_OK mode=local-google-drive-folder destination=$GoogleDrivePath"
    exit 0
} catch {
    Write-Log "ERROR $($_.Exception.Message)"
    exit 1
}

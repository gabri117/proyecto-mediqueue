param(
    [string]$PostgresService = $env:MEDIQUEUE_BACKUP_POSTGRES_SERVICE,
    [string]$DatabaseName = $env:MEDIQUEUE_BACKUP_DB_NAME,
    [string]$DatabaseUser = $env:MEDIQUEUE_BACKUP_DB_USER,
    [string]$BackupRoot = $env:MEDIQUEUE_BACKUP_ROOT,
    [string]$ContainerWalArchiveDir = "/var/lib/postgresql/wal-archive",
    [string]$GoogleDrivePath = $env:MEDIQUEUE_BACKUP_GOOGLE_DRIVE_PATH
)

$ErrorActionPreference = "Stop"
if (-not $PostgresService) { $PostgresService = "postgres" }
if (-not $DatabaseName) { $DatabaseName = "mediqueue" }
if (-not $DatabaseUser) { $DatabaseUser = "mediqueue" }
if (-not $BackupRoot) { $BackupRoot = ".\infra\backups" }

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logDir = Join-Path $BackupRoot "logs"
$walRoot = Join-Path $BackupRoot "wal-archive"
$walDir = Join-Path $walRoot "wal_$stamp"
New-Item -ItemType Directory -Force -Path $logDir, $walDir | Out-Null
$logFile = Join-Path $logDir "backup-wal-archive-$stamp.log"

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

    $archiveMode = docker compose exec -T $PostgresService psql -U $DatabaseUser -d $DatabaseName -Atc "show archive_mode;"
    $archiveCommand = docker compose exec -T $PostgresService psql -U $DatabaseUser -d $DatabaseName -Atc "show archive_command;"
    $archiveTimeout = docker compose exec -T $PostgresService psql -U $DatabaseUser -d $DatabaseName -Atc "show archive_timeout;"
    Write-Log "archive_mode=$archiveMode"
    Write-Log "archive_command=$archiveCommand"
    Write-Log "archive_timeout=$archiveTimeout"

    if ($archiveMode.Trim() -ne "on") {
        throw "WAL archiving no esta activo. Para RPO <= 5 minutos se requiere archive_mode=on, archive_command hacia un directorio persistente y archive_timeout=5min."
    }

    Invoke-Checked "check container WAL archive dir" { docker compose exec -T $PostgresService bash -lc "test -d '$ContainerWalArchiveDir' && find '$ContainerWalArchiveDir' -maxdepth 1 -type f | head -1 | grep -q ." }

    $liveFiles = Get-ChildItem -LiteralPath $walRoot -File | Where-Object { $_.Name -ne ".gitkeep" }
    foreach ($file in $liveFiles) {
        Copy-Item -LiteralPath $file.FullName -Destination $walDir -Force
    }

    $files = Get-ChildItem -LiteralPath $walDir -File
    if ($files.Count -lt 1) {
        throw "No se copiaron WAL files a $walDir"
    }

    Write-Log "WAL_ARCHIVE_COPY_OK dir=$walDir files=$($files.Count)"

    if ($GoogleDrivePath) {
        $dest = Join-Path $GoogleDrivePath "wal_$stamp"
        New-Item -ItemType Directory -Force -Path $dest | Out-Null
        Copy-Item -LiteralPath (Join-Path $walDir "*") -Destination $dest -Recurse -Force
        Write-Log "GOOGLE_DRIVE_COPY_OK destination=$dest"
    }

    exit 0
} catch {
    Write-Log "ERROR $($_.Exception.Message)"
    exit 1
}

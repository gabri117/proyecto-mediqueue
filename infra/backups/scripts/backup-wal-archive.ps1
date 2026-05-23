param(
    [string]$PostgresService = $env:MEDIQUEUE_BACKUP_POSTGRES_SERVICE,
    [string]$DatabaseName = $env:MEDIQUEUE_BACKUP_DB_NAME,
    [string]$DatabaseUser = $env:MEDIQUEUE_BACKUP_DB_USER,
    [string]$BackupRoot = $env:MEDIQUEUE_BACKUP_ROOT,
    [string]$ContainerWalArchiveDir = "/var/lib/postgresql/wal-archive",
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
$BackupMode = $cfg.BackupMode
if ($BackupMode -eq "patroni" -and $ContainerWalArchiveDir -eq "/var/lib/postgresql/wal-archive") {
    $ContainerWalArchiveDir = "/var/lib/postgresql/wal-archive/patroni"
}

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logDir = Join-Path $BackupRoot "logs"
$walRoot = Join-Path $BackupRoot "wal-archive"
$walSourceDir = if ($BackupMode -eq "patroni") { Join-Path $walRoot "patroni" } else { $walRoot }
$walDir = Join-Path $walSourceDir "wal_$stamp"
New-Item -ItemType Directory -Force -Path $logDir, $walSourceDir, $walDir | Out-Null
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
    Write-Log "BACKUP_MODE=$BackupMode"
    if ($BackupMode -eq "patroni") {
        $PostgresService = Select-MediQueuePatroniLeaderService -Config $cfg
        Write-Log "PATRONI_WAL_LEADER_SERVICE=$PostgresService archive_dir=$ContainerWalArchiveDir"
    } elseif ($BackupMode -ne "single") {
        throw "BackupMode invalido: $BackupMode. Use single o patroni."
    }

    Invoke-Checked "docker info" { docker info }
    if ($BackupMode -eq "patroni") {
        Invoke-Checked "docker compose patroni ps" { docker compose -f docker-compose.yml -f docker-compose.patroni.yml ps }
        Invoke-Checked "patroni postgres readiness" { Invoke-MediQueueBackupDockerCompose -BackupMode $BackupMode -CommandArgs @("exec", "-T", $PostgresService, "pg_isready", "-U", $($cfg.PatroniAdminUser), "-d", $DatabaseName) }
    } else {
        Invoke-Checked "docker compose ps" { docker compose ps }
        Invoke-Checked "postgres readiness" { docker compose exec -T $PostgresService pg_isready -U $DatabaseUser -d $DatabaseName }
    }

    if ($BackupMode -eq "patroni") {
        $psqlPrefix = @("exec", "-T", "-e", "PGPASSWORD=$($cfg.PatroniAdminPassword)", $PostgresService, "psql", "-U", $($cfg.PatroniAdminUser), "-d", $DatabaseName, "-Atc")
        $archiveMode = Invoke-MediQueueBackupDockerCompose -BackupMode $BackupMode -CommandArgs ($psqlPrefix + "show archive_mode;")
        $archiveCommand = Invoke-MediQueueBackupDockerCompose -BackupMode $BackupMode -CommandArgs ($psqlPrefix + "show archive_command;")
        $archiveTimeout = Invoke-MediQueueBackupDockerCompose -BackupMode $BackupMode -CommandArgs ($psqlPrefix + "show archive_timeout;")
    } else {
        $archiveMode = docker compose exec -T $PostgresService psql -U $DatabaseUser -d $DatabaseName -Atc "show archive_mode;"
        $archiveCommand = docker compose exec -T $PostgresService psql -U $DatabaseUser -d $DatabaseName -Atc "show archive_command;"
        $archiveTimeout = docker compose exec -T $PostgresService psql -U $DatabaseUser -d $DatabaseName -Atc "show archive_timeout;"
    }
    Write-Log "archive_mode=$archiveMode"
    Write-Log "archive_command=$archiveCommand"
    Write-Log "archive_timeout=$archiveTimeout"

    if ($archiveMode.Trim() -ne "on") {
        throw "WAL archiving no esta activo. Para RPO <= 5 minutos se requiere archive_mode=on, archive_command hacia un directorio persistente y archive_timeout=5min."
    }

    if ($BackupMode -eq "patroni") {
        Invoke-Checked "check patroni container WAL archive dir" { Invoke-MediQueueBackupDockerCompose -BackupMode $BackupMode -CommandArgs @("exec", "-T", $PostgresService, "bash", "-lc", "test -d '$ContainerWalArchiveDir' && find '$ContainerWalArchiveDir' -maxdepth 1 -type f | head -1 | grep -q .") }
    } else {
        Invoke-Checked "check container WAL archive dir" { docker compose exec -T $PostgresService bash -lc "test -d '$ContainerWalArchiveDir' && find '$ContainerWalArchiveDir' -maxdepth 1 -type f | head -1 | grep -q ." }
    }

    $liveFiles = Get-ChildItem -LiteralPath $walSourceDir -File | Where-Object { $_.Name -ne ".gitkeep" }
    foreach ($file in $liveFiles) {
        Copy-Item -LiteralPath $file.FullName -Destination $walDir -Force
    }

    $files = Get-ChildItem -LiteralPath $walDir -File
    if ($files.Count -lt 1) {
        throw "No se copiaron WAL files a $walDir"
    }

    Write-Log "WAL_ARCHIVE_COPY_OK source=$walSourceDir dir=$walDir files=$($files.Count)"

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

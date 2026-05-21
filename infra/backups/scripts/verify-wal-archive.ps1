param(
    [string]$PostgresService = $env:MEDIQUEUE_BACKUP_POSTGRES_SERVICE,
    [string]$DatabaseName = $env:MEDIQUEUE_BACKUP_DB_NAME,
    [string]$DatabaseUser = $env:MEDIQUEUE_BACKUP_DB_USER,
    [string]$BackupRoot = $env:MEDIQUEUE_BACKUP_ROOT,
    [string]$ContainerWalArchiveDir = "/var/lib/postgresql/wal-archive",
    [int]$WaitSeconds = 90,
    [int]$RecentWalMinutes = 10
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\backup-common.ps1"
$cfg = Get-MediQueueBackupConfig
if (-not $PostgresService) { $PostgresService = $cfg.PostgresService }
if (-not $DatabaseName) { $DatabaseName = $cfg.DatabaseName }
if (-not $DatabaseUser) { $DatabaseUser = $cfg.DatabaseUser }
if (-not $BackupRoot) { $BackupRoot = $cfg.BackupRoot }
$BackupMode = $cfg.BackupMode
if ($BackupMode -eq "patroni" -and $ContainerWalArchiveDir -eq "/var/lib/postgresql/wal-archive") {
    $ContainerWalArchiveDir = "/var/lib/postgresql/wal-archive/patroni"
}

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logDir = Join-Path $BackupRoot "logs"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$logFile = Join-Path $logDir "verify-wal-archive-$stamp.log"

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

function Get-ComposeArgs {
    if ($BackupMode -eq "patroni") {
        return @("-f", "docker-compose.yml", "-f", "docker-compose.patroni.yml")
    }
    return @()
}

function Get-PatroniLeaderService {
    $definitions = @(
        @{ Service = "$($cfg.PatroniDockerServicePrefix)-1"; Port = 18008 },
        @{ Service = "$($cfg.PatroniDockerServicePrefix)-2"; Port = 18009 },
        @{ Service = "$($cfg.PatroniDockerServicePrefix)-3"; Port = 18010 }
    )
    foreach ($definition in $definitions) {
        try {
            $status = Invoke-RestMethod -Uri "http://127.0.0.1:$($definition.Port)/patroni" -TimeoutSec 3
            if ($status.role -in @("master", "primary")) {
                return $definition.Service
            }
        }
        catch {
            continue
        }
    }
    throw "No se encontro lider Patroni para verificar WAL."
}

function Invoke-DockerCompose {
    param([string[]]$CommandArgs)
    $composeArgs = Get-ComposeArgs
    docker compose @composeArgs @CommandArgs
}

function Invoke-PsqlScalar {
    param([string]$Sql)
    if ($BackupMode -eq "patroni") {
        $value = Invoke-DockerCompose -CommandArgs @("exec", "-T", "-e", "PGPASSWORD=$($cfg.PatroniAdminPassword)", $PostgresService, "psql", "-U", $($cfg.PatroniAdminUser), "-d", $DatabaseName, "-Atc", $Sql)
    } else {
        $value = docker compose exec -T $PostgresService psql -U $DatabaseUser -d $DatabaseName -Atc $Sql
    }
    if ($LASTEXITCODE -ne 0) {
        throw "psql fallo ejecutando: $Sql"
    }
    return ([string]$value).Trim()
}

function Get-WalCount {
    $count = Invoke-DockerCompose -CommandArgs @("exec", "-T", $PostgresService, "bash", "-lc", "mkdir -p '$ContainerWalArchiveDir'; find '$ContainerWalArchiveDir' -maxdepth 1 -type f | wc -l")
    if ($LASTEXITCODE -ne 0) {
        throw "No se pudo contar WAL en $ContainerWalArchiveDir"
    }
    return [int](([string]$count).Trim())
}

function Get-ArchiverStats {
    if ($BackupMode -eq "patroni") {
        $raw = Invoke-DockerCompose -CommandArgs @("exec", "-T", "-e", "PGPASSWORD=$($cfg.PatroniAdminPassword)", $PostgresService, "psql", "-U", $($cfg.PatroniAdminUser), "-d", $DatabaseName, "-Atc", "select archived_count, failed_count, coalesce(last_archived_wal,''), coalesce(last_archived_time::text,''), coalesce(last_failed_wal,''), coalesce(last_failed_time::text,'') from pg_stat_archiver;")
    } else {
        $raw = docker compose exec -T $PostgresService psql -U $DatabaseUser -d $DatabaseName -Atc "select archived_count, failed_count, coalesce(last_archived_wal,''), coalesce(last_archived_time::text,''), coalesce(last_failed_wal,''), coalesce(last_failed_time::text,'') from pg_stat_archiver;"
    }
    if ($LASTEXITCODE -ne 0) {
        throw "No se pudo consultar pg_stat_archiver."
    }
    $parts = ([string]$raw).Trim() -split "\|", 6
    return [ordered]@{
        archived_count = [int64]$parts[0]
        failed_count = [int64]$parts[1]
        last_archived_wal = $parts[2]
        last_archived_time = $parts[3]
        last_failed_wal = $parts[4]
        last_failed_time = $parts[5]
    }
}

function Get-LatestWalInfo {
    $raw = Invoke-DockerCompose -CommandArgs @("exec", "-T", $PostgresService, "bash", "-lc", "mkdir -p '$ContainerWalArchiveDir'; find '$ContainerWalArchiveDir' -maxdepth 1 -type f -printf '%T@|%f|%TY-%Tm-%Td %TH:%TM:%TS\n' 2>/dev/null | sort -nr | head -10")
    if ($LASTEXITCODE -ne 0) {
        throw "No se pudieron listar WAL en $ContainerWalArchiveDir"
    }
    return [string]$raw
}

function Test-RecentWal {
    $epoch = Invoke-DockerCompose -CommandArgs @("exec", "-T", $PostgresService, "bash", "-lc", "find '$ContainerWalArchiveDir' -maxdepth 1 -type f -printf '%T@\n' 2>/dev/null | sort -nr | head -1")
    if ($LASTEXITCODE -ne 0 -or -not ([string]$epoch).Trim()) {
        return $false
    }
    $latest = [DateTimeOffset]::FromUnixTimeSeconds([int64][double](([string]$epoch).Trim())).DateTime
    return $latest -ge (Get-Date).AddMinutes(-$RecentWalMinutes)
}

try {
    Write-Log "BACKUP_MODE=$BackupMode"
    if ($BackupMode -eq "patroni") {
        $PostgresService = Get-PatroniLeaderService
        Write-Log "PATRONI_WAL_LEADER_SERVICE=$PostgresService archive_dir=$ContainerWalArchiveDir"
    } elseif ($BackupMode -ne "single") {
        throw "BackupMode invalido: $BackupMode. Use single o patroni."
    }
    Invoke-Checked "docker info" { docker info }
    if ($BackupMode -eq "patroni") {
        Invoke-Checked "docker compose patroni ps" { docker compose -f docker-compose.yml -f docker-compose.patroni.yml ps }
        Invoke-Checked "patroni postgres readiness" { Invoke-DockerCompose -CommandArgs @("exec", "-T", $PostgresService, "pg_isready", "-U", $($cfg.PatroniAdminUser), "-d", $DatabaseName) }
    } else {
        Invoke-Checked "docker compose ps" { docker compose ps }
        Invoke-Checked "postgres readiness" { docker compose exec -T $PostgresService pg_isready -U $DatabaseUser -d $DatabaseName }
    }

    $walLevel = Invoke-PsqlScalar "show wal_level;"
    $archiveMode = Invoke-PsqlScalar "show archive_mode;"
    $archiveTimeout = Invoke-PsqlScalar "show archive_timeout;"
    $archiveCommand = Invoke-PsqlScalar "show archive_command;"

    Write-Log "wal_level=$walLevel"
    Write-Log "archive_mode=$archiveMode"
    Write-Log "archive_timeout=$archiveTimeout"
    Write-Log "archive_command=$archiveCommand"

    if ($walLevel -ne "replica" -and $walLevel -ne "logical") {
        throw "wal_level invalido para PITR: $walLevel"
    }
    if ($archiveMode -ne "on") {
        throw "archive_mode debe estar on para PITR. Actual=$archiveMode"
    }
    if ($archiveTimeout -ne "5min" -and $archiveTimeout -ne "300s") {
        Write-Log "WARN archive_timeout esperado 5min/300s, actual=$archiveTimeout"
    }
    if (-not $archiveCommand -or $archiveCommand -eq "(disabled)") {
        throw "archive_command no esta configurado."
    }

    $beforeCount = Get-WalCount
    $beforeStats = Get-ArchiverStats
    Write-Log "wal_count_before=$beforeCount"
    Write-Log "archiver_before archived_count=$($beforeStats.archived_count) failed_count=$($beforeStats.failed_count) last_archived_wal=$($beforeStats.last_archived_wal) last_archived_time=$($beforeStats.last_archived_time) last_failed_wal=$($beforeStats.last_failed_wal) last_failed_time=$($beforeStats.last_failed_time)"

    $switchedWal = Invoke-PsqlScalar "select pg_switch_wal();"
    Write-Log "pg_switch_wal=$switchedWal"

    $deadline = (Get-Date).AddSeconds($WaitSeconds)
    $afterCount = $beforeCount
    $afterStats = $beforeStats
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 2
        $afterCount = Get-WalCount
        $afterStats = Get-ArchiverStats
        if ($afterStats.archived_count -gt $beforeStats.archived_count -or
            $afterStats.last_archived_time -ne $beforeStats.last_archived_time -or
            $afterCount -gt $beforeCount) {
            break
        }
    }

    Write-Log "wal_count_after=$afterCount"
    Write-Log "archiver_after archived_count=$($afterStats.archived_count) failed_count=$($afterStats.failed_count) last_archived_wal=$($afterStats.last_archived_wal) last_archived_time=$($afterStats.last_archived_time) last_failed_wal=$($afterStats.last_failed_wal) last_failed_time=$($afterStats.last_failed_time)"
    Write-Log "latest_wal_files_start"
    Write-Log (Get-LatestWalInfo)
    Write-Log "latest_wal_files_end"

    if ($afterStats.failed_count -gt $beforeStats.failed_count) {
        throw "pg_stat_archiver reporta fallos nuevos. failed_count_before=$($beforeStats.failed_count) failed_count_after=$($afterStats.failed_count) last_failed_wal=$($afterStats.last_failed_wal)"
    }

    if ($afterStats.archived_count -gt $beforeStats.archived_count -or
        $afterStats.last_archived_time -ne $beforeStats.last_archived_time -or
        $afterCount -gt $beforeCount) {
        Write-Log "WAL_ARCHIVE_VERIFY_OK newFiles=$($afterCount - $beforeCount) archivedDelta=$($afterStats.archived_count - $beforeStats.archived_count) total=$afterCount"
        exit 0
    }

    Write-Log "WARN No cambio archived_count/last_archived_time despues de pg_switch_wal() dentro de ${WaitSeconds}s."
    if (Test-RecentWal) {
        Write-Log "WAL_ARCHIVE_VERIFY_WARNING recentWal=true failed_count_unchanged=true"
        exit 0
    }

    throw "No se archivo WAL nuevo y no hay WAL reciente dentro de ${RecentWalMinutes} minutos."
} catch {
    Write-Log "ERROR $($_.Exception.Message)"
    exit 1
}

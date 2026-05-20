param(
    [string]$PostgresService = $env:MEDIQUEUE_BACKUP_POSTGRES_SERVICE,
    [string]$DatabaseName = $env:MEDIQUEUE_BACKUP_DB_NAME,
    [string]$DatabaseUser = $env:MEDIQUEUE_BACKUP_DB_USER,
    [string]$BackupRoot = $env:MEDIQUEUE_BACKUP_ROOT,
    [string]$ContainerWalArchiveDir = "/var/lib/postgresql/wal-archive",
    [int]$WaitSeconds = 30
)

$ErrorActionPreference = "Stop"
if (-not $PostgresService) { $PostgresService = "postgres" }
if (-not $DatabaseName) { $DatabaseName = "mediqueue" }
if (-not $DatabaseUser) { $DatabaseUser = "mediqueue" }
if (-not $BackupRoot) { $BackupRoot = ".\infra\backups" }

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

function Invoke-PsqlScalar {
    param([string]$Sql)
    $value = docker compose exec -T $PostgresService psql -U $DatabaseUser -d $DatabaseName -Atc $Sql
    if ($LASTEXITCODE -ne 0) {
        throw "psql fallo ejecutando: $Sql"
    }
    return ([string]$value).Trim()
}

function Get-WalCount {
    $count = docker compose exec -T $PostgresService bash -lc "mkdir -p '$ContainerWalArchiveDir'; find '$ContainerWalArchiveDir' -maxdepth 1 -type f | wc -l"
    if ($LASTEXITCODE -ne 0) {
        throw "No se pudo contar WAL en $ContainerWalArchiveDir"
    }
    return [int](([string]$count).Trim())
}

try {
    Invoke-Checked "docker info" { docker info }
    Invoke-Checked "docker compose ps" { docker compose ps }
    Invoke-Checked "postgres readiness" { docker compose exec -T $PostgresService pg_isready -U $DatabaseUser -d $DatabaseName }

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
    Write-Log "wal_count_before=$beforeCount"

    $switchedWal = Invoke-PsqlScalar "select pg_switch_wal();"
    Write-Log "pg_switch_wal=$switchedWal"

    $deadline = (Get-Date).AddSeconds($WaitSeconds)
    $afterCount = $beforeCount
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 2
        $afterCount = Get-WalCount
        if ($afterCount -gt $beforeCount) {
            break
        }
    }

    Write-Log "wal_count_after=$afterCount"
    if ($afterCount -le $beforeCount) {
        throw "No aparecio un WAL nuevo despues de pg_switch_wal() dentro de ${WaitSeconds}s."
    }

    Write-Log "WAL_ARCHIVE_VERIFY_OK newFiles=$($afterCount - $beforeCount) total=$afterCount"
    exit 0
} catch {
    Write-Log "ERROR $($_.Exception.Message)"
    exit 1
}

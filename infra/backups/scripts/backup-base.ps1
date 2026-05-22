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
$BackupMode = $cfg.BackupMode

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

function Get-PatroniNodes {
    $definitions = @(
        @{ Service = "$($cfg.PatroniDockerServicePrefix)-1"; Port = 18008 },
        @{ Service = "$($cfg.PatroniDockerServicePrefix)-2"; Port = 18009 },
        @{ Service = "$($cfg.PatroniDockerServicePrefix)-3"; Port = 18010 }
    )

    $nodes = @()
    foreach ($definition in $definitions) {
        try {
            $status = Invoke-RestMethod -Uri "http://127.0.0.1:$($definition.Port)/patroni" -TimeoutSec 3
            $name = if ($status.name) { $status.name } else { $definition.Service }
            $nodes += [pscustomobject]@{
                Service = $definition.Service
                Name = $name
                Port = $definition.Port
                Role = $status.role
                State = $status.state
                Timeline = $status.timeline
                Healthy = ($status.state -eq "running" -and $status.role -in @("master", "primary", "replica", "standby_leader"))
            }
        }
        catch {
            $nodes += [pscustomobject]@{
                Service = $definition.Service
                Name = $definition.Service
                Port = $definition.Port
                Role = "unreachable"
                State = "unreachable"
                Timeline = ""
                Healthy = $false
            }
        }
    }

    return $nodes
}

function Select-PatroniBackupNode {
    $nodes = Get-PatroniNodes
    Write-Log "PATRONI_NODES $($nodes | ConvertTo-Json -Compress)"

    if ($cfg.PatroniBackupNode) {
        $selected = $nodes | Where-Object { $_.Service -eq $cfg.PatroniBackupNode -or $_.Name -eq $cfg.PatroniBackupNode } | Select-Object -First 1
        if (-not $selected) {
            throw "PatroniBackupNode no existe: $($cfg.PatroniBackupNode)"
        }
        if (-not $selected.Healthy) {
            throw "PatroniBackupNode no esta saludable: $($cfg.PatroniBackupNode)"
        }
        return $selected
    }

    $replica = $nodes | Where-Object { $_.Healthy -and $_.Role -in @("replica", "standby_leader") } | Select-Object -First 1
    if ($replica) {
        return $replica
    }

    $leader = $nodes | Where-Object { $_.Healthy -and $_.Role -in @("master", "primary") } | Select-Object -First 1
    if ($leader) {
        Write-Log "WARN No hay replica saludable; backup fisico Patroni usara el lider."
        return $leader
    }

    throw "No hay nodos Patroni saludables para backup fisico."
}

try {
    Write-Log "BACKUP_MODE=$BackupMode"
    Invoke-Checked "docker info" { docker info }
    if ($BackupMode -eq "patroni") {
        Invoke-Checked "docker compose patroni ps" { docker compose -f docker-compose.yml -f docker-compose.patroni.yml ps }
    } else {
        Invoke-Checked "docker compose ps" { docker compose ps }
        Invoke-Checked "postgres readiness" { docker compose exec -T $PostgresService pg_isready -U $DatabaseUser -d $DatabaseName }
    }

    $containerDir = "/backups/mediqueue_base_$stamp"
    $localBackupDir = Join-Path $localDir "mediqueue_base_$stamp"

    $patroniNode = $null
    if ($BackupMode -eq "patroni") {
        $patroniNode = Select-PatroniBackupNode
        $containerDir = "/tmp/mediqueue_base_$stamp"
        Write-Log "PATRONI_BASE_BACKUP_SOURCE scope=$($cfg.PatroniScope) node=$($patroniNode.Name) service=$($patroniNode.Service) role=$($patroniNode.Role) timeline=$($patroniNode.Timeline)"
        $cmd = "set -euo pipefail; rm -rf '$containerDir'; mkdir -p '$containerDir'; export PGPASSWORD='$($cfg.PatroniReplicationPassword)'; pg_basebackup -h 127.0.0.1 -p 5432 -U '$($cfg.PatroniReplicationUser)' -D '$containerDir' -Ft -z -X stream -c fast --manifest-checksums=SHA256; test -s '$containerDir/base.tar.gz'; test -s '$containerDir/pg_wal.tar.gz'; test -s '$containerDir/backup_manifest'; sha256sum '$containerDir'/base.tar.gz '$containerDir'/pg_wal.tar.gz > '$containerDir/SHA256SUMS'"
        Invoke-Checked "patroni pg_basebackup physical base backup" { docker compose -f docker-compose.yml -f docker-compose.patroni.yml exec -T $($patroniNode.Service) bash -lc $cmd }
        Invoke-Checked "copy patroni base backup to host" { docker compose -f docker-compose.yml -f docker-compose.patroni.yml cp "$($patroniNode.Service):$containerDir" $localBackupDir }
        Invoke-Checked "cleanup patroni temp base backup" { docker compose -f docker-compose.yml -f docker-compose.patroni.yml exec -T $($patroniNode.Service) bash -lc "rm -rf '$containerDir'" }
    } elseif ($BackupMode -eq "single") {
        $cmd = "set -euo pipefail; rm -rf '$containerDir'; mkdir -p '$containerDir'; export PGPASSWORD=`"`$POSTGRES_PASSWORD`"; pg_basebackup -U '$DatabaseUser' -D '$containerDir' -Ft -z -X stream -c fast --manifest-checksums=SHA256; test -s '$containerDir/base.tar.gz'; test -s '$containerDir/pg_wal.tar.gz'; test -s '$containerDir/backup_manifest'; sha256sum '$containerDir'/base.tar.gz '$containerDir'/pg_wal.tar.gz > '$containerDir/SHA256SUMS'"
        Invoke-Checked "pg_basebackup physical base backup" { docker compose exec -T $PostgresService bash -lc $cmd }
    } else {
        throw "BackupMode invalido: $BackupMode. Use single o patroni."
    }

    if (-not (Test-Path -LiteralPath $localBackupDir)) {
        throw "Backup base no fue creado: $localBackupDir"
    }

    $baseTar = Join-Path $localBackupDir "base.tar.gz"
    $manifest = Join-Path $localBackupDir "backup_manifest"
    $walTar = Join-Path $localBackupDir "pg_wal.tar.gz"
    if (-not (Test-Path -LiteralPath $baseTar) -or (Get-Item -LiteralPath $baseTar).Length -le 0) {
        throw "base.tar.gz no fue creado o esta vacio: $baseTar"
    }
    if (-not (Test-Path -LiteralPath $walTar) -or (Get-Item -LiteralPath $walTar).Length -le 0) {
        throw "pg_wal.tar.gz no fue creado o esta vacio: $walTar"
    }
    if (-not (Test-Path -LiteralPath $manifest) -or (Get-Item -LiteralPath $manifest).Length -le 0) {
        throw "backup_manifest no fue creado o esta vacio: $manifest"
    }

    $marker = Join-Path $localBackupDir "BACKUP_BASE_OK.txt"
    $metadata = @(
        "timestamp=$stamp",
        "backup_mode=$BackupMode",
        "database=$DatabaseName",
        "postgres_service=$PostgresService"
    )
    if ($patroniNode) {
        $metadata += "patroni_scope=$($cfg.PatroniScope)"
        $metadata += "patroni_node=$($patroniNode.Name)"
        $metadata += "patroni_service=$($patroniNode.Service)"
        $metadata += "patroni_role=$($patroniNode.Role)"
        $metadata += "patroni_timeline=$($patroniNode.Timeline)"
    }
    $metadata += "base_tar_bytes=$((Get-Item -LiteralPath $baseTar).Length)"
    $metadata += "pg_wal_tar_bytes=$((Get-Item -LiteralPath $walTar).Length)"
    $metadata | Set-Content -LiteralPath $marker -Encoding utf8

    Write-Log "BASE_BACKUP_OK dir=$localBackupDir baseTarBytes=$((Get-Item -LiteralPath $baseTar).Length) pgWalTarBytes=$((Get-Item -LiteralPath $walTar).Length)"
    Write-Log "CHECKSUM_OK file=$(Join-Path $localBackupDir 'SHA256SUMS')"

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

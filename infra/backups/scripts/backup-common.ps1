function Get-MediQueueRepoRoot {
    $scriptsDir = Split-Path -Parent $PSScriptRoot
    return (Resolve-Path (Join-Path $scriptsDir "..\..")).Path
}

function Get-MediQueueBackupConfig {
    $repoRoot = Get-MediQueueRepoRoot
    $backupRootDefault = Join-Path $repoRoot "infra\backups"
    $localConfigPath = Join-Path $backupRootDefault "config\backup.local.ps1"

    $local = @{
        BackupRoot = $null
        GoogleDriveBackupPath = $null
        DatabaseName = $null
        DatabaseUser = $null
        PostgresService = $null
        PostgresContainer = $null
        BackupMode = $null
        PatroniWriterHost = $null
        PatroniWriterPort = $null
        PatroniDockerServicePrefix = $null
        PatroniScope = $null
        PatroniBackupNode = $null
        PatroniReplicationUser = $null
        PatroniReplicationPassword = $null
        PatroniAdminUser = $null
        PatroniAdminPassword = $null
    }

    if (Test-Path -LiteralPath $localConfigPath) {
        . $localConfigPath
        $local.BackupRoot = if (Get-Variable -Name BackupRoot -ErrorAction SilentlyContinue) { $BackupRoot } else { $null }
        $local.GoogleDriveBackupPath = if (Get-Variable -Name GoogleDriveBackupPath -ErrorAction SilentlyContinue) { $GoogleDriveBackupPath } else { $null }
        $local.DatabaseName = if (Get-Variable -Name DatabaseName -ErrorAction SilentlyContinue) { $DatabaseName } else { $null }
        $local.DatabaseUser = if (Get-Variable -Name DatabaseUser -ErrorAction SilentlyContinue) { $DatabaseUser } else { $null }
        $local.PostgresService = if (Get-Variable -Name PostgresService -ErrorAction SilentlyContinue) { $PostgresService } else { $null }
        $local.PostgresContainer = if (Get-Variable -Name PostgresContainer -ErrorAction SilentlyContinue) { $PostgresContainer } else { $null }
        $local.BackupMode = if (Get-Variable -Name BackupMode -ErrorAction SilentlyContinue) { $BackupMode } else { $null }
        $local.PatroniWriterHost = if (Get-Variable -Name PatroniWriterHost -ErrorAction SilentlyContinue) { $PatroniWriterHost } else { $null }
        $local.PatroniWriterPort = if (Get-Variable -Name PatroniWriterPort -ErrorAction SilentlyContinue) { $PatroniWriterPort } else { $null }
        $local.PatroniDockerServicePrefix = if (Get-Variable -Name PatroniDockerServicePrefix -ErrorAction SilentlyContinue) { $PatroniDockerServicePrefix } else { $null }
        $local.PatroniScope = if (Get-Variable -Name PatroniScope -ErrorAction SilentlyContinue) { $PatroniScope } else { $null }
        $local.PatroniBackupNode = if (Get-Variable -Name PatroniBackupNode -ErrorAction SilentlyContinue) { $PatroniBackupNode } else { $null }
        $local.PatroniReplicationUser = if (Get-Variable -Name PatroniReplicationUser -ErrorAction SilentlyContinue) { $PatroniReplicationUser } else { $null }
        $local.PatroniReplicationPassword = if (Get-Variable -Name PatroniReplicationPassword -ErrorAction SilentlyContinue) { $PatroniReplicationPassword } else { $null }
        $local.PatroniAdminUser = if (Get-Variable -Name PatroniAdminUser -ErrorAction SilentlyContinue) { $PatroniAdminUser } else { $null }
        $local.PatroniAdminPassword = if (Get-Variable -Name PatroniAdminPassword -ErrorAction SilentlyContinue) { $PatroniAdminPassword } else { $null }
    } else {
        Write-Warning "No existe infra/backups/config/backup.local.ps1. Usando valores por defecto; las tareas programadas no deben depender de variables temporales de PowerShell."
    }

    return [ordered]@{
        RepoRoot = $repoRoot
        BackupRoot = if ($local.BackupRoot) { $local.BackupRoot } elseif ($env:MEDIQUEUE_BACKUP_ROOT) { $env:MEDIQUEUE_BACKUP_ROOT } else { $backupRootDefault }
        GoogleDriveBackupPath = if ($local.GoogleDriveBackupPath) { $local.GoogleDriveBackupPath } elseif ($env:GOOGLE_DRIVE_BACKUP_PATH) { $env:GOOGLE_DRIVE_BACKUP_PATH } else { $env:MEDIQUEUE_BACKUP_GOOGLE_DRIVE_PATH }
        DatabaseName = if ($local.DatabaseName) { $local.DatabaseName } elseif ($env:MEDIQUEUE_BACKUP_DB_NAME) { $env:MEDIQUEUE_BACKUP_DB_NAME } else { "mediqueue" }
        DatabaseUser = if ($local.DatabaseUser) { $local.DatabaseUser } elseif ($env:MEDIQUEUE_BACKUP_DB_USER) { $env:MEDIQUEUE_BACKUP_DB_USER } else { "mediqueue" }
        PostgresService = if ($local.PostgresService) { $local.PostgresService } elseif ($env:MEDIQUEUE_BACKUP_POSTGRES_SERVICE) { $env:MEDIQUEUE_BACKUP_POSTGRES_SERVICE } else { "postgres" }
        PostgresContainer = if ($local.PostgresContainer) { $local.PostgresContainer } else { "mediqueue-postgres" }
        BackupMode = if ($local.BackupMode) { $local.BackupMode } elseif ($env:MEDIQUEUE_BACKUP_MODE) { $env:MEDIQUEUE_BACKUP_MODE } else { "single" }
        PatroniWriterHost = if ($local.PatroniWriterHost) { $local.PatroniWriterHost } elseif ($env:MEDIQUEUE_BACKUP_PATRONI_WRITER_HOST) { $env:MEDIQUEUE_BACKUP_PATRONI_WRITER_HOST } else { "localhost" }
        PatroniWriterPort = if ($local.PatroniWriterPort) { [int]$local.PatroniWriterPort } elseif ($env:MEDIQUEUE_BACKUP_PATRONI_WRITER_PORT) { [int]$env:MEDIQUEUE_BACKUP_PATRONI_WRITER_PORT } else { 55432 }
        PatroniDockerServicePrefix = if ($local.PatroniDockerServicePrefix) { $local.PatroniDockerServicePrefix } elseif ($env:MEDIQUEUE_BACKUP_PATRONI_SERVICE_PREFIX) { $env:MEDIQUEUE_BACKUP_PATRONI_SERVICE_PREFIX } else { "patroni-postgres" }
        PatroniScope = if ($local.PatroniScope) { $local.PatroniScope } elseif ($env:MEDIQUEUE_BACKUP_PATRONI_SCOPE) { $env:MEDIQUEUE_BACKUP_PATRONI_SCOPE } else { "mediqueue-postgres-ha" }
        PatroniBackupNode = if ($local.PatroniBackupNode) { $local.PatroniBackupNode } elseif ($env:MEDIQUEUE_BACKUP_PATRONI_BACKUP_NODE) { $env:MEDIQUEUE_BACKUP_PATRONI_BACKUP_NODE } else { "" }
        PatroniReplicationUser = if ($local.PatroniReplicationUser) { $local.PatroniReplicationUser } elseif ($env:PATRONI_REPLICATION_USERNAME) { $env:PATRONI_REPLICATION_USERNAME } else { "replicator" }
        PatroniReplicationPassword = if ($local.PatroniReplicationPassword) { $local.PatroniReplicationPassword } elseif ($env:PATRONI_REPLICATION_PASSWORD) { $env:PATRONI_REPLICATION_PASSWORD } else { "replicator" }
        PatroniAdminUser = if ($local.PatroniAdminUser) { $local.PatroniAdminUser } elseif ($env:PATRONI_SUPERUSER_USERNAME) { $env:PATRONI_SUPERUSER_USERNAME } else { "postgres" }
        PatroniAdminPassword = if ($local.PatroniAdminPassword) { $local.PatroniAdminPassword } elseif ($env:PATRONI_SUPERUSER_PASSWORD) { $env:PATRONI_SUPERUSER_PASSWORD } else { "postgres" }
        LocalConfigPath = $localConfigPath
    }
}

function Get-DirectoryStats {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        return [ordered]@{ Count = 0; Bytes = 0 }
    }
    $files = Get-ChildItem -LiteralPath $Path -File -Recurse -Force | Where-Object { $_.Name -ne ".gitkeep" }
    $bytes = ($files | Measure-Object -Property Length -Sum).Sum
    if ($null -eq $bytes) { $bytes = 0 }
    return [ordered]@{ Count = @($files).Count; Bytes = [int64]$bytes }
}

function Get-MediQueueBackupComposeArgs {
    param([Parameter(Mandatory = $true)][string]$BackupMode)

    if ($BackupMode -eq "patroni") {
        return @("-f", "docker-compose.yml", "-f", "docker-compose.patroni.yml")
    }

    return @()
}

function Invoke-MediQueueBackupDockerCompose {
    param(
        [Parameter(Mandatory = $true)][string]$BackupMode,
        [Parameter(Mandatory = $true)][string[]]$CommandArgs
    )

    $composeArgs = Get-MediQueueBackupComposeArgs -BackupMode $BackupMode
    docker compose @composeArgs @CommandArgs
}

function Get-MediQueuePatroniNodeDefinitions {
    param([Parameter(Mandatory = $true)]$Config)

    return @(
        @{ Service = "$($Config.PatroniDockerServicePrefix)-1"; Port = 18008 },
        @{ Service = "$($Config.PatroniDockerServicePrefix)-2"; Port = 18009 },
        @{ Service = "$($Config.PatroniDockerServicePrefix)-3"; Port = 18010 }
    )
}

function Get-MediQueuePatroniNodes {
    param([Parameter(Mandatory = $true)]$Config)

    $nodes = @()
    foreach ($definition in (Get-MediQueuePatroniNodeDefinitions -Config $Config)) {
        try {
            $status = Invoke-RestMethod -Uri "http://127.0.0.1:$($definition.Port)/patroni" -TimeoutSec 3
            $nodes += [pscustomobject]@{
                Service = $definition.Service
                Name = if ($status.name) { $status.name } else { $definition.Service }
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

function Select-MediQueuePatroniRunnerService {
    param([Parameter(Mandatory = $true)]$Config)

    $nodes = Get-MediQueuePatroniNodes -Config $Config
    $runner = $nodes |
        Where-Object { $_.Healthy -and $_.Role -in @("master", "primary", "replica", "standby_leader") } |
        Sort-Object @{ Expression = { if ($_.Role -in @("replica", "standby_leader")) { 0 } else { 1 } } }, Service |
        Select-Object -First 1

    if (-not $runner) {
        throw "No hay nodos Patroni saludables para ejecutar herramientas PostgreSQL. Estado: $($nodes | ConvertTo-Json -Compress)"
    }

    return $runner.Service
}

function Select-MediQueuePatroniLeaderService {
    param([Parameter(Mandatory = $true)]$Config)

    $nodes = Get-MediQueuePatroniNodes -Config $Config
    $leader = $nodes |
        Where-Object { $_.Healthy -and $_.Role -in @("master", "primary") } |
        Select-Object -First 1

    if (-not $leader) {
        throw "No se encontro lider Patroni. Estado: $($nodes | ConvertTo-Json -Compress)"
    }

    return $leader.Service
}

function Get-MediQueueBackupContainerId {
    param(
        [Parameter(Mandatory = $true)][string]$BackupMode,
        [Parameter(Mandatory = $true)][string]$Service
    )

    $raw = Invoke-MediQueueBackupDockerCompose -BackupMode $BackupMode -CommandArgs @("ps", "-q", $Service)
    if ($LASTEXITCODE -ne 0) {
        throw "No se pudo resolver container id para service=$Service."
    }

    $containerId = ([string]$raw -split "\r?\n" | Where-Object { $_.Trim() } | Select-Object -First 1).Trim()
    if (-not $containerId) {
        throw "No hay contenedor activo para service=$Service."
    }

    return $containerId
}

function Copy-MediQueueBackupFromContainer {
    param(
        [Parameter(Mandatory = $true)][string]$BackupMode,
        [Parameter(Mandatory = $true)][string]$Service,
        [Parameter(Mandatory = $true)][string]$ContainerPath,
        [Parameter(Mandatory = $true)][string]$HostPath
    )

    $containerId = Get-MediQueueBackupContainerId -BackupMode $BackupMode -Service $Service
    docker cp "${containerId}:$ContainerPath" $HostPath
}

function Copy-MediQueueBackupToContainer {
    param(
        [Parameter(Mandatory = $true)][string]$BackupMode,
        [Parameter(Mandatory = $true)][string]$Service,
        [Parameter(Mandatory = $true)][string]$HostPath,
        [Parameter(Mandatory = $true)][string]$ContainerPath
    )

    $containerId = Get-MediQueueBackupContainerId -BackupMode $BackupMode -Service $Service
    docker cp $HostPath "${containerId}:$ContainerPath"
}

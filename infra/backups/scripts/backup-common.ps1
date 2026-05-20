$ErrorActionPreference = "Stop"

Set-StrictMode -Version 3.0

$Script:ScriptsRoot = $PSScriptRoot
$Script:BackupInfraRoot = (Resolve-Path (Join-Path $Script:ScriptsRoot "..")).Path
$Script:RepoRoot = (Resolve-Path (Join-Path $Script:BackupInfraRoot "..\..")).Path
$Script:CurrentLogFile = $null
$Script:ConfigLoaded = $false
$Script:ConfigPathLoaded = $null

function Initialize-BackupConfiguration {
    param(
        [string]$ConfigPath
    )

    $defaults = @{
        BackupRoot = ".\infra\backups"
        GoogleDriveBackupPath = ".\MediQueue Backups"
        DatabaseName = "mediqueue"
        DatabaseUser = "mediqueue"
        PostgresService = "postgres"
        PostgresContainer = "mediqueue-postgres"
        DockerComposeFile = ".\docker-compose.yml"
        WalArchiveIntervalMinutes = 5
        WalReceiveDurationSeconds = 290
        WalReplicationSlot = "mediqueue_backup_slot"
        BaseBackupRetentionDays = 14
        DumpRetentionDays = 30
        WalRetentionDays = 14
        LogRetentionDays = 30
        WeeklyRetentionWeeks = 8
        MonthlyRetentionMonths = 12
        RestoreTestDatabasePrefix = "mediqueue_restore_test"
        PitrTestPort = 55432
    }

    foreach ($key in $defaults.Keys) {
        if (-not (Get-Variable -Name $key -Scope Script -ErrorAction SilentlyContinue)) {
            Set-Variable -Name $key -Value $defaults[$key] -Scope Script
        }
    }

    if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
        $ConfigPath = Join-Path $Script:BackupInfraRoot "config\backup.local.ps1"
    }

    $resolvedConfig = Resolve-BackupPath -Path $ConfigPath -BasePath $Script:RepoRoot -MustExist:$false
    if (Test-Path -LiteralPath $resolvedConfig) {
        . $resolvedConfig
        foreach ($key in $defaults.Keys) {
            $localValue = Get-Variable -Name $key -Scope Local -ErrorAction SilentlyContinue
            if ($localValue) {
                Set-Variable -Name $key -Value $localValue.Value -Scope Script
            }
        }
        $Script:ConfigLoaded = $true
        $Script:ConfigPathLoaded = $resolvedConfig
    }
    else {
        $Script:ConfigLoaded = $false
        $Script:ConfigPathLoaded = $resolvedConfig
        Write-Warning "No se encontro backup.local.ps1 en '$resolvedConfig'. Se usaran valores por defecto; copia config/backup.local.example.ps1 para configurar rutas locales."
    }

    $Script:BackupRootFull = Resolve-BackupPath -Path $Script:BackupRoot -BasePath $Script:RepoRoot -MustExist:$false
    $Script:DockerComposeFileFull = Resolve-BackupPath -Path $Script:DockerComposeFile -BasePath $Script:RepoRoot -MustExist:$false
    $Script:GoogleDriveBackupPathFull = Resolve-BackupPath -Path $Script:GoogleDriveBackupPath -BasePath $Script:RepoRoot -MustExist:$false

    $Script:LocalBackupDir = Join-Path $Script:BackupRootFull "local"
    $Script:DumpDir = Join-Path $Script:BackupRootFull "dumps"
    $Script:WalArchiveDir = Join-Path $Script:BackupRootFull "wal-archive"
    $Script:LogDir = Join-Path $Script:BackupRootFull "logs"
    $Script:RestoreTestDir = Join-Path $Script:BackupRootFull "restore-test"
    $Script:WeeklyDir = Join-Path $Script:BackupRootFull "weekly"
    $Script:MonthlyDir = Join-Path $Script:BackupRootFull "monthly"

    @(
        $Script:BackupRootFull,
        $Script:LocalBackupDir,
        $Script:DumpDir,
        $Script:WalArchiveDir,
        $Script:LogDir,
        $Script:RestoreTestDir,
        $Script:WeeklyDir,
        $Script:MonthlyDir
    ) | ForEach-Object { New-Item -ItemType Directory -Force -Path $_ | Out-Null }
}

function Resolve-BackupPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$BasePath,
        [bool]$MustExist = $true
    )

    if ([System.IO.Path]::IsPathRooted($Path)) {
        $candidate = $Path
    }
    else {
        $candidate = Join-Path $BasePath $Path
    }

    if ($MustExist) {
        return (Resolve-Path -LiteralPath $candidate).Path
    }

    return [System.IO.Path]::GetFullPath($candidate)
}

function Start-BackupLog {
    param([Parameter(Mandatory = $true)][string]$Name)

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $Script:CurrentLogFile = Join-Path $Script:LogDir "$Name-$timestamp.log"
    New-Item -ItemType File -Force -Path $Script:CurrentLogFile | Out-Null
    Write-Log "Log iniciado: $Script:CurrentLogFile"
}

function Write-Log {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR", "OK")][string]$Level = "INFO"
    )

    $line = "{0} [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
    Write-Host $line
    if ($Script:CurrentLogFile) {
        Add-Content -LiteralPath $Script:CurrentLogFile -Value $line
    }
}

function Invoke-CheckedCommand {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$Arguments = @(),
        [int[]]$AllowedExitCodes = @(0),
        [string]$FailureMessage = "El comando fallo."
    )

    Write-Log ("Ejecutando: {0} {1}" -f $FilePath, ($Arguments -join " "))
    & $FilePath @Arguments
    $exitCode = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
    if ($AllowedExitCodes -notcontains $exitCode) {
        throw "$FailureMessage Exit code: $exitCode"
    }
    return $exitCode
}

function Invoke-DockerCompose {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [int[]]$AllowedExitCodes = @(0),
        [string]$FailureMessage = "docker compose fallo."
    )

    $fullArgs = @("compose", "-f", $Script:DockerComposeFileFull) + $Arguments
    return Invoke-CheckedCommand -FilePath "docker" -Arguments $fullArgs -AllowedExitCodes $AllowedExitCodes -FailureMessage $FailureMessage
}

function Get-CommandOutput {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$Arguments = @(),
        [int[]]$AllowedExitCodes = @(0),
        [string]$FailureMessage = "El comando fallo."
    )

    Write-Log ("Ejecutando: {0} {1}" -f $FilePath, ($Arguments -join " "))
    $output = & $FilePath @Arguments 2>&1
    $exitCode = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
    if ($AllowedExitCodes -notcontains $exitCode) {
        $text = ($output | Out-String).Trim()
        throw "$FailureMessage Exit code: $exitCode. Output: $text"
    }
    return ($output | Out-String).Trim()
}

function Get-DockerComposeOutput {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [int[]]$AllowedExitCodes = @(0),
        [string]$FailureMessage = "docker compose fallo."
    )

    $fullArgs = @("compose", "-f", $Script:DockerComposeFileFull) + $Arguments
    return Get-CommandOutput -FilePath "docker" -Arguments $fullArgs -AllowedExitCodes $AllowedExitCodes -FailureMessage $FailureMessage
}

function Assert-DockerAvailable {
    Invoke-CheckedCommand -FilePath "docker" -Arguments @("version", "--format", "{{.Server.Version}}") -FailureMessage "Docker no esta disponible."
    Invoke-CheckedCommand -FilePath "docker" -Arguments @("compose", "version") -FailureMessage "Docker Compose no esta disponible."
    if (-not (Test-Path -LiteralPath $Script:DockerComposeFileFull)) {
        throw "No existe el archivo Docker Compose: $Script:DockerComposeFileFull"
    }
}

function Assert-ComposeConfigValid {
    Invoke-DockerCompose -Arguments @("config", "--quiet") -FailureMessage "docker compose config --quiet fallo."
}

function Assert-PostgresAvailable {
    Invoke-DockerCompose -Arguments @(
        "exec", "-T", $Script:PostgresService,
        "pg_isready", "-U", $Script:DatabaseUser, "-d", $Script:DatabaseName
    ) -FailureMessage "PostgreSQL no esta disponible."
}

function Get-PostgresContainerId {
    $containerId = Get-DockerComposeOutput -Arguments @("ps", "-q", $Script:PostgresService) -FailureMessage "No se pudo obtener el contenedor PostgreSQL."
    if ([string]::IsNullOrWhiteSpace($containerId)) {
        throw "El servicio PostgreSQL '$Script:PostgresService' no tiene contenedor en ejecucion."
    }
    return $containerId.Trim()
}

function Invoke-PostgresSql {
    param(
        [Parameter(Mandatory = $true)][string]$Sql,
        [string]$Database = $Script:DatabaseName
    )

    return Get-DockerComposeOutput -Arguments @(
        "exec", "-T", $Script:PostgresService,
        "psql", "-v", "ON_ERROR_STOP=1", "-U", $Script:DatabaseUser, "-d", $Database, "-c", $Sql
    ) -FailureMessage "psql fallo."
}

function Get-LatestFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Filter
    )

    return Get-ChildItem -LiteralPath $Path -Filter $Filter -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}

function Assert-NotMainDatabase {
    param([Parameter(Mandatory = $true)][string]$Database)

    if ($Database -eq $Script:DatabaseName) {
        throw "Operacion bloqueada: no se permite restaurar sobre la base principal '$Script:DatabaseName'."
    }
}

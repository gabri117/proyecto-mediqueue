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
    }

    if (Test-Path -LiteralPath $localConfigPath) {
        . $localConfigPath
        $local.BackupRoot = if (Get-Variable -Name BackupRoot -ErrorAction SilentlyContinue) { $BackupRoot } else { $null }
        $local.GoogleDriveBackupPath = if (Get-Variable -Name GoogleDriveBackupPath -ErrorAction SilentlyContinue) { $GoogleDriveBackupPath } else { $null }
        $local.DatabaseName = if (Get-Variable -Name DatabaseName -ErrorAction SilentlyContinue) { $DatabaseName } else { $null }
        $local.DatabaseUser = if (Get-Variable -Name DatabaseUser -ErrorAction SilentlyContinue) { $DatabaseUser } else { $null }
        $local.PostgresService = if (Get-Variable -Name PostgresService -ErrorAction SilentlyContinue) { $PostgresService } else { $null }
        $local.PostgresContainer = if (Get-Variable -Name PostgresContainer -ErrorAction SilentlyContinue) { $PostgresContainer } else { $null }
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

param(
    [string]$ConfigPath
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "backup-common.ps1")

Initialize-BackupConfiguration -ConfigPath $ConfigPath
Start-BackupLog -Name "sync-google-drive"

try {
    New-Item -ItemType Directory -Force -Path $Script:GoogleDriveBackupPathFull | Out-Null

    $sources = @(
        @{ Name = "local"; Path = $Script:LocalBackupDir },
        @{ Name = "dumps"; Path = $Script:DumpDir },
        @{ Name = "wal-archive"; Path = $Script:WalArchiveDir },
        @{ Name = "weekly"; Path = $Script:WeeklyDir },
        @{ Name = "monthly"; Path = $Script:MonthlyDir },
        @{ Name = "logs"; Path = $Script:LogDir }
    )

    foreach ($source in $sources) {
        $target = Join-Path $Script:GoogleDriveBackupPathFull $source.Name
        New-Item -ItemType Directory -Force -Path $target | Out-Null
        Invoke-CheckedCommand -FilePath "robocopy" -Arguments @(
            $source.Path,
            $target,
            "/E",
            "/Z",
            "/R:2",
            "/W:5",
            "/XF",
            ".gitkeep"
        ) -AllowedExitCodes @(0, 1, 2, 3, 4, 5, 6, 7) -FailureMessage "robocopy fallo al sincronizar '$($source.Name)'."
    }

    Write-Log "Sincronizacion local para Google Drive Desktop completada: $Script:GoogleDriveBackupPathFull" "OK"
}
catch {
    Write-Log $_.Exception.Message "ERROR"
    throw
}

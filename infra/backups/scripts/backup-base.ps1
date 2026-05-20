param(
    [string]$ConfigPath
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "backup-common.ps1")

Initialize-BackupConfiguration -ConfigPath $ConfigPath
Start-BackupLog -Name "backup-base"

Assert-DockerAvailable
Assert-ComposeConfigValid
Assert-PostgresAvailable

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$baseName = "mediqueue-base-$timestamp"
$remoteDir = "/tmp/$baseName"
$remoteArchive = "/tmp/$baseName.tar.gz"
$localArchive = Join-Path $Script:LocalBackupDir "$baseName.tar.gz"
$weeklyArchive = Join-Path $Script:WeeklyDir "$baseName.tar.gz"
$monthlyArchive = Join-Path $Script:MonthlyDir "$baseName.tar.gz"

try {
    $backupCommand = "rm -rf '$remoteDir' '$remoteArchive' && mkdir -p '$remoteDir' && pg_basebackup -U '$Script:DatabaseUser' -D '$remoteDir' -Fp -Xs -P -c fast && tar -C /tmp -czf '$remoteArchive' '$baseName'"
    Invoke-DockerCompose -Arguments @("exec", "-T", $Script:PostgresService, "sh", "-lc", $backupCommand) -FailureMessage "El backup fisico/base fallo."

    $containerId = Get-PostgresContainerId
    Invoke-CheckedCommand -FilePath "docker" -Arguments @("cp", "$containerId`:$remoteArchive", $localArchive) -FailureMessage "No se pudo copiar el backup base al host."

    Invoke-DockerCompose -Arguments @("exec", "-T", $Script:PostgresService, "sh", "-lc", "rm -rf '$remoteDir' '$remoteArchive'") -FailureMessage "No se pudo limpiar el temporal del contenedor."

    if ((Get-Date).DayOfWeek -eq "Sunday") {
        Copy-Item -LiteralPath $localArchive -Destination $weeklyArchive -Force
        Write-Log "Copia semanal creada: $weeklyArchive" "OK"
    }

    if ((Get-Date).Day -eq 1) {
        Copy-Item -LiteralPath $localArchive -Destination $monthlyArchive -Force
        Write-Log "Copia mensual creada: $monthlyArchive" "OK"
    }

    Write-Log "Backup base creado: $localArchive" "OK"
}
catch {
    Write-Log $_.Exception.Message "ERROR"
    throw
}

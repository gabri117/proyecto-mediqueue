param(
    [string]$ConfigPath,
    [string]$TaskPrefix = "MediQueue Backup"
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "backup-common.ps1")

Initialize-BackupConfiguration -ConfigPath $ConfigPath
Start-BackupLog -Name "install-backup-tasks"

function New-BackupAction {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptName,
        [string[]]$ExtraArguments = @()
    )

    $scriptPath = Join-Path $PSScriptRoot $ScriptName
    $arguments = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$scriptPath`"")
    if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
        $arguments += @("-ConfigPath", "`"$ConfigPath`"")
    }
    $arguments += $ExtraArguments

    return New-ScheduledTaskAction -Execute "powershell.exe" -Argument ($arguments -join " ")
}

function Register-BackupTask {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)]$Action,
        [Parameter(Mandatory = $true)]$Trigger,
        [string]$Description
    )

    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 4)
    Register-ScheduledTask -TaskName $Name -Action $Action -Trigger $Trigger -Settings $settings -Description $Description -Force | Out-Null
    Write-Log "Tarea registrada: $Name" "OK"
}

$baseTrigger = New-ScheduledTaskTrigger -Daily -At "21:00"
$dumpTrigger = New-ScheduledTaskTrigger -Daily -At "22:00"
$walSnapshotTrigger = New-ScheduledTaskTrigger -Daily -At "22:20"
$syncTrigger = New-ScheduledTaskTrigger -Daily -At "22:30"
$cleanupTrigger = New-ScheduledTaskTrigger -Daily -At "23:00"
$verifyTrigger = New-ScheduledTaskTrigger -Daily -At "23:30"
$restoreTrigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At "23:45"

Register-BackupTask -Name "$TaskPrefix - Base diario 21:00" -Action (New-BackupAction -ScriptName "backup-base.ps1") -Trigger $baseTrigger -Description "Backup fisico/base diario despues del cierre."
Register-BackupTask -Name "$TaskPrefix - pg_dump diario 22:00" -Action (New-BackupAction -ScriptName "backup-pgdump.ps1") -Trigger $dumpTrigger -Description "Backup logico diario con pg_dump custom."
Register-BackupTask -Name "$TaskPrefix - WAL snapshot diario 22:20" -Action (New-BackupAction -ScriptName "backup-wal-archive.ps1") -Trigger $walSnapshotTrigger -Description "Snapshot local del WAL archivado por PostgreSQL."
Register-BackupTask -Name "$TaskPrefix - Sync Google Drive 22:30" -Action (New-BackupAction -ScriptName "sync-google-drive.ps1") -Trigger $syncTrigger -Description "Copia local a carpeta sincronizada por Google Drive Desktop."
Register-BackupTask -Name "$TaskPrefix - Cleanup dry-run 23:00" -Action (New-BackupAction -ScriptName "cleanup-backups.ps1" -ExtraArguments @("-DryRun")) -Trigger $cleanupTrigger -Description "Simulacion diaria de retencion; no elimina automaticamente."
Register-BackupTask -Name "$TaskPrefix - Verify diario 23:30" -Action (New-BackupAction -ScriptName "verify-backups.ps1") -Trigger $verifyTrigger -Description "Verificacion diaria de base, dump y WAL."
Register-BackupTask -Name "$TaskPrefix - Restore test domingo 23:45" -Action (New-BackupAction -ScriptName "restore-pgdump-test.ps1") -Trigger $restoreTrigger -Description "Restauracion logica semanal en base aislada."

Write-Log "Instalacion de tareas completada. La limpieza queda registrada en modo -DryRun." "OK"

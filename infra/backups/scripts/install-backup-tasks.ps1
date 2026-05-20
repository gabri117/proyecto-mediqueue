param(
    [string]$ConfigPath,
    [switch]$Create,
    [switch]$DeleteExisting,
    [switch]$WhatIf,
    [switch]$UsePipelineTask
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "backup-common.ps1")

Initialize-BackupConfiguration -ConfigPath $ConfigPath
Start-BackupLog -Name "install-backup-tasks"

$repoRoot = $Script:RepoRoot
$defaultConfigPath = Join-Path $Script:BackupInfraRoot "config\backup.local.ps1"
$taskConfigPath = if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $defaultConfigPath
}
else {
    Resolve-BackupPath -Path $ConfigPath -BasePath $repoRoot -MustExist:$false
}

$shellCommand = Get-Command "pwsh.exe" -ErrorAction SilentlyContinue
if (-not $shellCommand) {
    $shellCommand = Get-Command "powershell.exe" -ErrorAction Stop
}
$shellPath = $shellCommand.Source

if (-not (Test-Path -LiteralPath $taskConfigPath)) {
    Write-Log "backup.local.ps1 no existe en '$taskConfigPath'. Las tareas se pueden crear, pero sync-google-drive.ps1 fallara hasta que exista." "WARN"
}

function Join-TaskArgument {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptName,
        [string[]]$ExtraArguments = @()
    )

    $scriptPath = Join-Path $PSScriptRoot $ScriptName
    $arguments = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", "`"$scriptPath`"",
        "-ConfigPath", "`"$taskConfigPath`""
    ) + $ExtraArguments

    return ($arguments -join " ")
}

function New-BackupTaskSpec {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$ScriptName,
        [Parameter(Mandatory = $true)][string]$Schedule,
        [Parameter(Mandatory = $true)][string]$At,
        [string]$DaysOfWeek,
        [string[]]$ExtraArguments = @(),
        [string]$Description = ""
    )

    return [pscustomobject]@{
        Name = $Name
        ScriptName = $ScriptName
        Arguments = Join-TaskArgument -ScriptName $ScriptName -ExtraArguments $ExtraArguments
        Schedule = $Schedule
        At = $At
        DaysOfWeek = $DaysOfWeek
        Description = $Description
    }
}

function Get-TaskSpecs {
    $specs = @()

    if ($UsePipelineTask) {
        $specs += New-BackupTaskSpec -Name "MediQueue Daily Backup Pipeline" -ScriptName "run-daily-backup-pipeline.ps1" -Schedule "Daily" -At "21:00" -Description "Ejecuta backup base, pg_dump, WAL verify, sync y verificacion final."
        $specs += New-BackupTaskSpec -Name "MediQueue Cleanup Daily" -ScriptName "cleanup-backups.ps1" -Schedule "Daily" -At "23:00" -ExtraArguments @("-DryRun") -Description "Limpieza diaria en modo simulacion; no elimina automaticamente."
        $specs += New-BackupTaskSpec -Name "MediQueue Restore PgDump Test Weekly" -ScriptName "restore-pgdump-test.ps1" -Schedule "Weekly" -DaysOfWeek "Sunday" -At "23:45" -ExtraArguments @("-RecreateDatabase") -Description "Restauracion logica semanal en base aislada."
        return $specs
    }

    $specs += New-BackupTaskSpec -Name "MediQueue Backup Base Daily" -ScriptName "backup-base.ps1" -Schedule "Daily" -At "21:00" -Description "Backup fisico/base diario."
    $specs += New-BackupTaskSpec -Name "MediQueue PgDump Daily" -ScriptName "backup-pgdump.ps1" -Schedule "Daily" -At "22:00" -Description "Backup logico diario pg_dump -Fc."
    $specs += New-BackupTaskSpec -Name "MediQueue Sync Google Drive Daily" -ScriptName "sync-google-drive.ps1" -Schedule "Daily" -At "22:30" -Description "Copia local a carpeta sincronizada por Google Drive Desktop."
    $specs += New-BackupTaskSpec -Name "MediQueue Cleanup Daily" -ScriptName "cleanup-backups.ps1" -Schedule "Daily" -At "23:00" -ExtraArguments @("-DryRun") -Description "Limpieza diaria en modo simulacion; no elimina automaticamente."
    $specs += New-BackupTaskSpec -Name "MediQueue Verify Daily" -ScriptName "verify-backups.ps1" -Schedule "Daily" -At "23:30" -Description "Verificacion diaria de backups."
    $specs += New-BackupTaskSpec -Name "MediQueue Restore PgDump Test Weekly" -ScriptName "restore-pgdump-test.ps1" -Schedule "Weekly" -DaysOfWeek "Sunday" -At "23:45" -ExtraArguments @("-RecreateDatabase") -Description "Restauracion logica semanal en base aislada."
    return $specs
}

function New-TaskTriggerFromSpec {
    param([Parameter(Mandatory = $true)]$Spec)

    if ($Spec.Schedule -eq "Weekly") {
        return New-ScheduledTaskTrigger -Weekly -DaysOfWeek $Spec.DaysOfWeek -At $Spec.At
    }

    return New-ScheduledTaskTrigger -Daily -At $Spec.At
}

function Write-TaskPreview {
    param([Parameter(Mandatory = $true)]$Spec)

    Write-Host ""
    Write-Host "Task: $($Spec.Name)"
    Write-Host "Schedule: $($Spec.Schedule) $($Spec.DaysOfWeek) $($Spec.At)"
    Write-Host "WorkingDirectory: $repoRoot"
    Write-Host "Command:"
    Write-Host "  `"$shellPath`" $($Spec.Arguments)"
}

$taskSpecs = Get-TaskSpecs

Write-Log "PowerShell runtime seleccionado: $shellPath"
Write-Log "Repo root: $repoRoot"
Write-Log "ConfigPath para tareas: $taskConfigPath"

foreach ($spec in $taskSpecs) {
    Write-TaskPreview -Spec $spec
}

if (-not $Create) {
    Write-Log "Modo preview: no se crearon tareas. Usa -Create para registrar tareas." "WARN"
    Write-Host ""
    Write-Host "Crear tareas recomendadas:"
    Write-Host ".\infra\backups\scripts\install-backup-tasks.ps1 -Create -UsePipelineTask"
    exit 0
}

if ($WhatIf) {
    Write-Log "WhatIf activo: no se crearan ni eliminaran tareas." "WARN"
    exit 0
}

foreach ($spec in $taskSpecs) {
    if ($DeleteExisting) {
        $existingTask = Get-ScheduledTask -TaskName $spec.Name -ErrorAction SilentlyContinue
        if ($existingTask) {
            Unregister-ScheduledTask -TaskName $spec.Name -Confirm:$false
            Write-Log "Tarea existente eliminada: $($spec.Name)" "OK"
        }
    }

    $action = New-ScheduledTaskAction -Execute $shellPath -Argument $spec.Arguments -WorkingDirectory $repoRoot
    $trigger = New-TaskTriggerFromSpec -Spec $spec
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 6)

    Register-ScheduledTask -TaskName $spec.Name -Action $action -Trigger $trigger -Settings $settings -Description $spec.Description -Force | Out-Null
    Write-Log "Tarea registrada: $($spec.Name)" "OK"
}

Write-Log "Instalacion de tareas completada. Cleanup queda en -DryRun." "OK"

param(
    [switch]$Create,
    [switch]$DeleteExisting,
    [switch]$WhatIf,
    [switch]$UsePipelineTask
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\backup-common.ps1"
$cfg = Get-MediQueueBackupConfig
$repoRoot = (Resolve-Path -LiteralPath $cfg.RepoRoot).Path

function Get-PowerShellExecutable {
    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($pwsh) { return $pwsh.Source }
    return (Get-Command powershell.exe -ErrorAction Stop).Source
}

function New-BackupTaskSpec {
    param(
        [string]$Name,
        [string]$ScriptRelativePath,
        [string]$Time,
        [ValidateSet("Daily", "Weekly")]
        [string]$Schedule,
        [string]$DaysOfWeek,
        [string[]]$ExtraArguments = @()
    )

    $scriptPath = Join-Path $repoRoot $ScriptRelativePath
    if (-not (Test-Path -LiteralPath $scriptPath)) {
        throw "No existe script para tarea programada: $scriptPath"
    }

    return [ordered]@{
        Name = $Name
        ScriptPath = $scriptPath
        Time = $Time
        Schedule = $Schedule
        DaysOfWeek = $DaysOfWeek
        ExtraArguments = $ExtraArguments
    }
}

function Format-TaskArgument {
    param([string]$ScriptPath, [string[]]$ExtraArguments)
    $items = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$ScriptPath`"") + $ExtraArguments
    return ($items -join " ")
}

$powershellExe = Get-PowerShellExecutable

$tasks = New-Object System.Collections.Generic.List[object]
if ($UsePipelineTask) {
    $tasks.Add((New-BackupTaskSpec -Name "MediQueue Daily Backup Pipeline" -ScriptRelativePath "infra\backups\scripts\run-daily-backup-pipeline.ps1" -Time "21:00" -Schedule "Daily"))
    $tasks.Add((New-BackupTaskSpec -Name "MediQueue Cleanup Daily" -ScriptRelativePath "infra\backups\scripts\cleanup-backups.ps1" -Time "23:00" -Schedule "Daily" -ExtraArguments @("-ConfirmDelete")))
    $tasks.Add((New-BackupTaskSpec -Name "MediQueue Restore PgDump Test Weekly" -ScriptRelativePath "infra\backups\scripts\restore-pgdump-test.ps1" -Time "23:45" -Schedule "Weekly" -DaysOfWeek "Sunday"))
} else {
    $tasks.Add((New-BackupTaskSpec -Name "MediQueue Backup Base Daily" -ScriptRelativePath "infra\backups\scripts\backup-base.ps1" -Time "21:00" -Schedule "Daily"))
    $tasks.Add((New-BackupTaskSpec -Name "MediQueue PgDump Daily" -ScriptRelativePath "infra\backups\scripts\backup-pgdump.ps1" -Time "22:00" -Schedule "Daily"))
    $tasks.Add((New-BackupTaskSpec -Name "MediQueue Sync Google Drive Daily" -ScriptRelativePath "infra\backups\scripts\sync-google-drive.ps1" -Time "22:30" -Schedule "Daily"))
    $tasks.Add((New-BackupTaskSpec -Name "MediQueue Cleanup Daily" -ScriptRelativePath "infra\backups\scripts\cleanup-backups.ps1" -Time "23:00" -Schedule "Daily" -ExtraArguments @("-ConfirmDelete")))
    $tasks.Add((New-BackupTaskSpec -Name "MediQueue Verify Daily" -ScriptRelativePath "infra\backups\scripts\verify-backups.ps1" -Time "23:30" -Schedule "Daily"))
    $tasks.Add((New-BackupTaskSpec -Name "MediQueue Restore PgDump Test Weekly" -ScriptRelativePath "infra\backups\scripts\restore-pgdump-test.ps1" -Time "23:45" -Schedule "Weekly" -DaysOfWeek "Sunday"))
}

Write-Host "RepoRoot=$repoRoot"
Write-Host "PowerShell=$powershellExe"
Write-Host "WorkingDirectory=$repoRoot"
Write-Host "LocalConfig=$($cfg.LocalConfigPath)"
if (-not (Test-Path -LiteralPath $cfg.LocalConfigPath)) {
    Write-Warning "No existe backup.local.ps1. Las tareas se crearan, pero usaran valores por defecto hasta que configures ese archivo."
}
Write-Host ""

foreach ($task in $tasks) {
    $argument = Format-TaskArgument -ScriptPath $task.ScriptPath -ExtraArguments $task.ExtraArguments
    Write-Host "TASK name=$($task.Name) schedule=$($task.Schedule) time=$($task.Time)"
    Write-Host "  Execute: $powershellExe"
    Write-Host "  Argument: $argument"
    Write-Host "  WorkingDirectory: $repoRoot"

    if (-not $Create -or $WhatIf) {
        continue
    }

    $existing = Get-ScheduledTask -TaskName $task.Name -ErrorAction SilentlyContinue
    if ($existing) {
        if ($DeleteExisting) {
            Unregister-ScheduledTask -TaskName $task.Name -Confirm:$false
            Write-Host "  Deleted existing task."
        } else {
            throw "La tarea ya existe: $($task.Name). Usa -DeleteExisting para reemplazarla."
        }
    }

    $action = New-ScheduledTaskAction -Execute $powershellExe -Argument $argument -WorkingDirectory $repoRoot
    if ($task.Schedule -eq "Weekly") {
        $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek $task.DaysOfWeek -At $task.Time
    } else {
        $trigger = New-ScheduledTaskTrigger -Daily -At $task.Time
    }

    Register-ScheduledTask `
        -TaskName $task.Name `
        -Action $action `
        -Trigger $trigger `
        -Description "MediQueue PostgreSQL backup automation. Uses infra/backups/config/backup.local.ps1." | Out-Null

    Write-Host "  CREATED"
}

if (-not $Create -or $WhatIf) {
    Write-Host ""
    Write-Host "Dry-run: no se crearon tareas. Ejecuta con -Create para registrarlas."
    Write-Host "Ejemplo pipeline: .\infra\backups\scripts\install-backup-tasks.ps1 -Create -UsePipelineTask"
}

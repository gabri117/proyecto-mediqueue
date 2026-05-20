param(
    [string]$ProjectRoot = (Resolve-Path ".").Path,
    [switch]$Create,
    [string]$TaskPrefix = "MediQueue Backup"
)

$ErrorActionPreference = "Stop"

function New-TaskCommand {
    param([string]$ScriptRelativePath)
    $scriptPath = Join-Path $ProjectRoot $ScriptRelativePath
    return "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
}

$tasks = @(
    [ordered]@{ Name = "$TaskPrefix Base"; Schedule = "DAILY"; Day = $null; Time = "21:00"; Command = New-TaskCommand "infra\backups\scripts\backup-base.ps1" },
    [ordered]@{ Name = "$TaskPrefix PgDump"; Schedule = "DAILY"; Day = $null; Time = "22:00"; Command = New-TaskCommand "infra\backups\scripts\backup-pgdump.ps1" },
    [ordered]@{ Name = "$TaskPrefix Sync Google Drive"; Schedule = "DAILY"; Day = $null; Time = "22:30"; Command = New-TaskCommand "infra\backups\scripts\sync-google-drive.ps1" },
    [ordered]@{ Name = "$TaskPrefix Cleanup"; Schedule = "DAILY"; Day = $null; Time = "23:00"; Command = "$(New-TaskCommand "infra\backups\scripts\cleanup-backups.ps1") -ConfirmDelete" },
    [ordered]@{ Name = "$TaskPrefix Verify"; Schedule = "DAILY"; Day = $null; Time = "23:30"; Command = New-TaskCommand "infra\backups\scripts\verify-backups.ps1" },
    [ordered]@{ Name = "$TaskPrefix Restore PgDump Test"; Schedule = "WEEKLY"; Day = "SUN"; Time = "23:45"; Command = New-TaskCommand "infra\backups\scripts\restore-pgdump-test.ps1" }
)

foreach ($task in $tasks) {
    $args = @(
        "/Create",
        "/F",
        "/TN", $task.Name,
        "/SC", $task.Schedule,
        "/ST", $task.Time,
        "/TR", $task.Command
    )
    if ($task.Day) {
        $args += @("/D", $task.Day)
    }

    $formattedArgs = ($args | ForEach-Object {
        $text = [string]$_
        $escaped = $text.Replace('"', '\"')
        if ($escaped -match "\s") { "`"$escaped`"" } else { $escaped }
    }) -join " "
    $display = "schtasks $formattedArgs"

    Write-Host $display

    if ($Create) {
        & schtasks @args
        if ($LASTEXITCODE -ne 0) {
            throw "No se pudo crear tarea: $($task.Name)"
        }
    }
}

if (-not $Create) {
    Write-Host ""
    Write-Host "Dry-run: no se crearon tareas. Ejecuta con -Create para registrarlas."
}

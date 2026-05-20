param(
    [switch]$SkipBaseBackup,
    [switch]$SkipSync
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\backup-common.ps1"
$cfg = Get-MediQueueBackupConfig
$backupRoot = $cfg.BackupRoot
$logDir = Join-Path $backupRoot "logs"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$pipelineLog = Join-Path $logDir "pipeline_$stamp.log"

$status = [ordered]@{
    BASE_STATUS = if ($SkipBaseBackup) { "SKIPPED" } else { "PENDING" }
    DUMP_STATUS = "PENDING"
    WAL_STATUS = "PENDING"
    SYNC_STATUS = if ($SkipSync) { "SKIPPED" } else { "PENDING" }
    VERIFY_STATUS = "PENDING"
    PIPELINE_STATUS = "PENDING"
}

function Write-PipelineLog {
    param([string]$Message)
    $line = "$(Get-Date -Format o) $Message"
    Write-Host $line
    Add-Content -Path $pipelineLog -Value $line -Encoding utf8
}

function Invoke-Step {
    param(
        [string]$Name,
        [string]$ScriptPath,
        [switch]$AllowWarningExit
    )
    Write-PipelineLog "START step=$Name script=$ScriptPath"
    & $ScriptPath 2>&1 | Tee-Object -FilePath $pipelineLog -Append
    $code = $LASTEXITCODE
    Write-PipelineLog "EXIT step=$Name code=$code"
    if ($code -ne 0 -and -not $AllowWarningExit) {
        throw "$Name fallo con exit code $code"
    }
    return $code
}

try {
    Write-PipelineLog "PIPELINE_START config=$($cfg.LocalConfigPath)"

    if (-not $SkipBaseBackup) {
        Invoke-Step -Name "base" -ScriptPath (Join-Path $PSScriptRoot "backup-base.ps1") | Out-Null
        $status.BASE_STATUS = "OK"
    }

    Invoke-Step -Name "pgdump" -ScriptPath (Join-Path $PSScriptRoot "backup-pgdump.ps1") | Out-Null
    $status.DUMP_STATUS = "OK"

    $walCode = Invoke-Step -Name "wal" -ScriptPath (Join-Path $PSScriptRoot "verify-wal-archive.ps1") -AllowWarningExit
    $status.WAL_STATUS = if ($walCode -eq 0) { "OK" } else { "WARNING" }

    if (-not $SkipSync) {
        Invoke-Step -Name "sync" -ScriptPath (Join-Path $PSScriptRoot "sync-google-drive.ps1") | Out-Null
        $status.SYNC_STATUS = "OK"
    }

    Invoke-Step -Name "verify" -ScriptPath (Join-Path $PSScriptRoot "verify-backups.ps1") | Out-Null
    $status.VERIFY_STATUS = "OK"
    $status.PIPELINE_STATUS = "OK"

    foreach ($key in $status.Keys) { Write-PipelineLog "$key=$($status[$key])" }
    exit 0
} catch {
    Write-PipelineLog "ERROR $($_.Exception.Message)"
    foreach ($key in $status.Keys) {
        if ($status[$key] -eq "PENDING") { $status[$key] = "NOT_RUN" }
    }
    $status.PIPELINE_STATUS = "ERROR"
    foreach ($key in $status.Keys) { Write-PipelineLog "$key=$($status[$key])" }
    exit 1
}

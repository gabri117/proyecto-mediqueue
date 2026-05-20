param(
    [string]$ConfigPath
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "backup-common.ps1")

Initialize-BackupConfiguration -ConfigPath $ConfigPath

$pipelineStamp = Get-Date -Format "yyyyMMdd_HHmmss"
$Script:CurrentLogFile = Join-Path $Script:LogDir "pipeline_$pipelineStamp.log"
New-Item -ItemType File -Force -Path $Script:CurrentLogFile | Out-Null
Write-Log "Pipeline log iniciado: $Script:CurrentLogFile"

$commonArgs = @()
if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
    $commonArgs = @("-ConfigPath", $ConfigPath)
}

$statuses = [ordered]@{
    BASE_STATUS = "PENDING"
    DUMP_STATUS = "PENDING"
    WAL_STATUS = "PENDING"
    SYNC_STATUS = "PENDING"
    VERIFY_STATUS = "PENDING"
}
$pipelineStatus = "OK"

function Set-PipelineWarning {
    if ($script:pipelineStatus -eq "OK") {
        $script:pipelineStatus = "WARNING"
    }
}

function Set-PipelineError {
    $script:pipelineStatus = "ERROR"
}

function Invoke-PipelineStep {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$ScriptName,
        [string[]]$Arguments = @(),
        [switch]$Critical
    )

    $scriptPath = Join-Path $PSScriptRoot $ScriptName
    Write-Log "STEP_START $Name script=$scriptPath"
    $startedAt = Get-Date
    $output = @()

    try {
        $output = & $scriptPath @Arguments *>&1
        foreach ($line in $output) {
            if ($null -ne $line) {
                Write-Log "[$Name] $line"
            }
        }

        $duration = ((Get-Date) - $startedAt).TotalSeconds
        Write-Log ("STEP_END {0} status=SUCCESS duration_seconds={1:N1}" -f $Name, $duration) "OK"

        return [pscustomobject]@{
            Name = $Name
            Success = $true
            Output = @($output | ForEach-Object { "$_" })
        }
    }
    catch {
        foreach ($line in $output) {
            if ($null -ne $line) {
                Write-Log "[$Name] $line"
            }
        }

        $duration = ((Get-Date) - $startedAt).TotalSeconds
        Write-Log ("STEP_END {0} status=FAILED duration_seconds={1:N1}" -f $Name, $duration) "ERROR"
        Write-Log "STEP_ERROR $Name $($_.Exception.Message)" "ERROR"

        return [pscustomobject]@{
            Name = $Name
            Success = $false
            Output = @($output | ForEach-Object { "$_" }) + @($_.Exception.Message)
        }
    }
}

function Test-OutputContains {
    param(
        [array]$Output,
        [string]$Pattern
    )

    return (@($Output | Where-Object { $_ -match $Pattern }).Count -gt 0)
}

try {
    $baseResult = Invoke-PipelineStep -Name "backup-base" -ScriptName "backup-base.ps1" -Arguments $commonArgs -Critical
    if (-not $baseResult.Success) {
        $statuses.BASE_STATUS = "ERROR"
        Set-PipelineError
        throw "backup-base fallo."
    }
    elseif (Test-OutputContains -Output $baseResult.Output -Pattern "BASE_BACKUP_OK") {
        $statuses.BASE_STATUS = "OK"
    }
    else {
        $statuses.BASE_STATUS = "WARNING"
        Set-PipelineWarning
    }

    $dumpResult = Invoke-PipelineStep -Name "backup-pgdump" -ScriptName "backup-pgdump.ps1" -Arguments $commonArgs -Critical
    if (-not $dumpResult.Success) {
        $statuses.DUMP_STATUS = "ERROR"
        Set-PipelineError
        throw "backup-pgdump fallo."
    }
    elseif ((Test-OutputContains -Output $dumpResult.Output -Pattern "DUMP_OK") -and (Test-OutputContains -Output $dumpResult.Output -Pattern "CHECKSUM_OK")) {
        $statuses.DUMP_STATUS = "OK"
    }
    else {
        $statuses.DUMP_STATUS = "WARNING"
        Set-PipelineWarning
    }

    $walResult = Invoke-PipelineStep -Name "verify-wal-archive" -ScriptName "verify-wal-archive.ps1" -Arguments $commonArgs
    if ($walResult.Success -and (Test-OutputContains -Output $walResult.Output -Pattern "WAL_OK")) {
        $statuses.WAL_STATUS = "OK"
    }
    elseif ($walResult.Success -and (Test-OutputContains -Output $walResult.Output -Pattern "WAL_WARNING")) {
        $statuses.WAL_STATUS = "WARNING"
        Set-PipelineWarning
        Write-Log "WAL warning detectado; se continua porque verify-wal-archive no fallo." "WARN"
    }
    else {
        $statuses.WAL_STATUS = "ERROR"
        Set-PipelineError
        throw "verify-wal-archive fallo o no encontro WAL reciente."
    }

    $syncResult = Invoke-PipelineStep -Name "sync-google-drive" -ScriptName "sync-google-drive.ps1" -Arguments $commonArgs -Critical
    if (-not $syncResult.Success) {
        $statuses.SYNC_STATUS = "ERROR"
        Set-PipelineError
        throw "sync-google-drive fallo."
    }
    elseif (Test-OutputContains -Output $syncResult.Output -Pattern "SYNC_OK") {
        $statuses.SYNC_STATUS = "OK"
    }
    elseif (Test-OutputContains -Output $syncResult.Output -Pattern "SYNC_WARNING") {
        $statuses.SYNC_STATUS = "WARNING"
        Set-PipelineWarning
    }
    else {
        $statuses.SYNC_STATUS = "WARNING"
        Set-PipelineWarning
    }

    $verifyResult = Invoke-PipelineStep -Name "verify-backups" -ScriptName "verify-backups.ps1" -Arguments $commonArgs
    if ($verifyResult.Success -and (Test-OutputContains -Output $verifyResult.Output -Pattern "STATUS=OK")) {
        $statuses.VERIFY_STATUS = "OK"
    }
    elseif ($verifyResult.Success -and (Test-OutputContains -Output $verifyResult.Output -Pattern "STATUS=WARNING")) {
        $statuses.VERIFY_STATUS = "WARNING"
        Set-PipelineWarning
    }
    else {
        $statuses.VERIFY_STATUS = "ERROR"
        Set-PipelineError
        throw "verify-backups termino con error."
    }
}
catch {
    Set-PipelineError
    Write-Log "PIPELINE_ERROR $($_.Exception.Message)" "ERROR"
    throw
}
finally {
    Write-Log "PIPELINE_SUMMARY"
    foreach ($key in $statuses.Keys) {
        Write-Log "$key=$($statuses[$key])"
    }
    $pipelineLogLevel = if ($pipelineStatus -eq "OK") { "OK" } elseif ($pipelineStatus -eq "WARNING") { "WARN" } else { "ERROR" }
    Write-Log "PIPELINE_STATUS=$pipelineStatus" $pipelineLogLevel
}

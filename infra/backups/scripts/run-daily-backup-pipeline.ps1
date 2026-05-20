param(
    [string]$ConfigPath,
    [switch]$SkipSync,
    [switch]$SkipVerify
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "backup-common.ps1")

Initialize-BackupConfiguration -ConfigPath $ConfigPath
Start-BackupLog -Name "run-daily-backup-pipeline"

$commonArgs = @()
if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
    $commonArgs = @("-ConfigPath", $ConfigPath)
}

try {
    & (Join-Path $PSScriptRoot "backup-base.ps1") @commonArgs
    if ($LASTEXITCODE -ne 0) { throw "backup-base.ps1 fallo con exit code $LASTEXITCODE" }

    & (Join-Path $PSScriptRoot "backup-pgdump.ps1") @commonArgs
    if ($LASTEXITCODE -ne 0) { throw "backup-pgdump.ps1 fallo con exit code $LASTEXITCODE" }

    & (Join-Path $PSScriptRoot "backup-wal-archive.ps1") @commonArgs
    if ($LASTEXITCODE -ne 0) { throw "backup-wal-archive.ps1 fallo con exit code $LASTEXITCODE" }

    if (-not $SkipSync) {
        & (Join-Path $PSScriptRoot "sync-google-drive.ps1") @commonArgs
        if ($LASTEXITCODE -ne 0) { throw "sync-google-drive.ps1 fallo con exit code $LASTEXITCODE" }
    }

    & (Join-Path $PSScriptRoot "cleanup-backups.ps1") @commonArgs -DryRun
    if ($LASTEXITCODE -ne 0) { throw "cleanup-backups.ps1 fallo con exit code $LASTEXITCODE" }

    if (-not $SkipVerify) {
        & (Join-Path $PSScriptRoot "verify-backups.ps1") @commonArgs
        if ($LASTEXITCODE -ne 0) { throw "verify-backups.ps1 fallo con exit code $LASTEXITCODE" }
    }

    Write-Log "Pipeline diario completado." "OK"
}
catch {
    Write-Log $_.Exception.Message "ERROR"
    throw
}

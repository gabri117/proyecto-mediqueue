param(
    [string]$ConfigPath,
    [int]$DurationSeconds = 0
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "backup-common.ps1")

Initialize-BackupConfiguration -ConfigPath $ConfigPath
Start-BackupLog -Name "backup-wal-archive"

Assert-DockerAvailable
Assert-ComposeConfigValid
Assert-PostgresAvailable

if ($DurationSeconds -le 0) {
    $DurationSeconds = [int]$Script:WalReceiveDurationSeconds
}

$slot = $Script:WalReplicationSlot
$remoteWalDir = "/tmp/mediqueue-wal-archive"

try {
    Invoke-PostgresSql -Sql "SELECT pg_create_physical_replication_slot('$slot') WHERE NOT EXISTS (SELECT 1 FROM pg_replication_slots WHERE slot_name = '$slot');" | Out-Null
    Invoke-PostgresSql -Sql "SELECT pg_switch_wal();" | Out-Null

    $receiveCommand = "mkdir -p '$remoteWalDir' && timeout $DurationSeconds pg_receivewal -U '$Script:DatabaseUser' -D '$remoteWalDir' --slot='$slot' --if-not-exists --no-loop"
    Invoke-DockerCompose -Arguments @("exec", "-T", $Script:PostgresService, "sh", "-lc", $receiveCommand) -AllowedExitCodes @(0, 124) -FailureMessage "La recepcion WAL fallo."

    $containerId = Get-PostgresContainerId
    $tempWalCopy = Join-Path $Script:WalArchiveDir "_incoming-$([guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Force -Path $tempWalCopy | Out-Null

    Invoke-CheckedCommand -FilePath "docker" -Arguments @("cp", "$containerId`:$remoteWalDir/.", $tempWalCopy) -FailureMessage "No se pudo copiar WAL al host."

    Get-ChildItem -LiteralPath $tempWalCopy -File -ErrorAction SilentlyContinue | ForEach-Object {
        Move-Item -LiteralPath $_.FullName -Destination (Join-Path $Script:WalArchiveDir $_.Name) -Force
    }
    Remove-Item -LiteralPath $tempWalCopy -Recurse -Force

    Write-Log "Archivo WAL actualizado en: $Script:WalArchiveDir" "OK"
}
catch {
    Write-Log $_.Exception.Message "ERROR"
    throw
}

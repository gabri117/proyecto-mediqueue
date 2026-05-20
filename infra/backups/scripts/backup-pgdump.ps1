param(
    [string]$ConfigPath
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "backup-common.ps1")

Initialize-BackupConfiguration -ConfigPath $ConfigPath
Start-BackupLog -Name "backup-pgdump"

Assert-DockerAvailable
Assert-ComposeConfigValid
Assert-PostgresAvailable

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$dumpName = "mediqueue_dump_$timestamp.dump"
$remoteDump = "/tmp/$dumpName"
$localDump = Join-Path $Script:DumpDir $dumpName
$checksumPath = "$localDump.sha256"

try {
    Invoke-DockerCompose -Arguments @(
        "exec", "-T", $Script:PostgresService,
        "pg_dump", "-U", $Script:DatabaseUser, "-d", $Script:DatabaseName,
        "-Fc", "--no-owner", "--no-privileges", "-f", $remoteDump
    ) -FailureMessage "pg_dump fallo."

    $containerId = Get-PostgresContainerId
    Invoke-CheckedCommand -FilePath "docker" -Arguments @("cp", "$containerId`:$remoteDump", $localDump) -FailureMessage "No se pudo copiar el pg_dump al host."

    if (-not (Test-Path -LiteralPath $localDump)) {
        throw "El dump no existe en el host: $localDump"
    }

    $dumpInfo = Get-Item -LiteralPath $localDump
    if ($dumpInfo.Length -le 0) {
        throw "El dump existe pero pesa 0 bytes: $localDump"
    }

    $hash = Get-FileHash -LiteralPath $localDump -Algorithm SHA256
    "{0}  {1}" -f $hash.Hash.ToLowerInvariant(), $dumpInfo.Name |
        Set-Content -LiteralPath $checksumPath -Encoding ASCII

    if (-not (Test-Path -LiteralPath $checksumPath)) {
        throw "No se genero checksum: $checksumPath"
    }
    if ((Get-Item -LiteralPath $checksumPath).Length -le 0) {
        throw "El checksum esta vacio: $checksumPath"
    }

    Write-Log "DUMP_OK $localDump ($($dumpInfo.Length) bytes)" "OK"
    Write-Log "CHECKSUM_OK $checksumPath" "OK"
}
catch {
    Write-Log $_.Exception.Message "ERROR"
    throw
}
finally {
    try {
        Invoke-DockerCompose -Arguments @("exec", "-T", $Script:PostgresService, "rm", "-f", $remoteDump) -AllowedExitCodes @(0, 1) -FailureMessage "No se pudo limpiar el dump temporal." | Out-Null
    }
    catch {
        Write-Log "No se pudo limpiar el dump temporal: $($_.Exception.Message)" "WARN"
    }
}

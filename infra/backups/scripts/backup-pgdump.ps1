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

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$dumpName = "mediqueue-$timestamp.dump"
$remoteDump = "/tmp/$dumpName"
$localDump = Join-Path $Script:DumpDir $dumpName

try {
    Invoke-DockerCompose -Arguments @(
        "exec", "-T", $Script:PostgresService,
        "pg_dump", "-U", $Script:DatabaseUser, "-d", $Script:DatabaseName,
        "-Fc", "--no-owner", "--no-privileges", "-f", $remoteDump
    ) -FailureMessage "pg_dump fallo."

    $containerId = Get-PostgresContainerId
    Invoke-CheckedCommand -FilePath "docker" -Arguments @("cp", "$containerId`:$remoteDump", $localDump) -FailureMessage "No se pudo copiar el pg_dump al host."
    Invoke-DockerCompose -Arguments @("exec", "-T", $Script:PostgresService, "rm", "-f", $remoteDump) -FailureMessage "No se pudo limpiar el dump temporal."

    Write-Log "pg_dump creado: $localDump" "OK"
}
catch {
    Write-Log $_.Exception.Message "ERROR"
    throw
}

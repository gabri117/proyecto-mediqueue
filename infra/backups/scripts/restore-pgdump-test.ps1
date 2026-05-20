param(
    [string]$ConfigPath,
    [string]$DumpPath,
    [switch]$KeepDatabase
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "backup-common.ps1")

Initialize-BackupConfiguration -ConfigPath $ConfigPath
Start-BackupLog -Name "restore-pgdump-test"

Assert-DockerAvailable
Assert-ComposeConfigValid
Assert-PostgresAvailable

if ([string]::IsNullOrWhiteSpace($DumpPath)) {
    $dump = Get-LatestFile -Path $Script:DumpDir -Filter "mediqueue-*.dump"
    if (-not $dump) {
        throw "No hay pg_dump disponible en $Script:DumpDir"
    }
    $DumpPath = $dump.FullName
}
else {
    $DumpPath = Resolve-BackupPath -Path $DumpPath -BasePath $Script:RepoRoot -MustExist:$true
}

$testDb = "{0}_{1}" -f $Script:RestoreTestDatabasePrefix, (Get-Date -Format "yyyyMMddHHmmss")
Assert-NotMainDatabase -Database $testDb

$remoteDump = "/tmp/restore-test-$([guid]::NewGuid().ToString('N')).dump"

try {
    $containerId = Get-PostgresContainerId
    Invoke-CheckedCommand -FilePath "docker" -Arguments @("cp", $DumpPath, "$containerId`:$remoteDump") -FailureMessage "No se pudo copiar el dump al contenedor."

    Invoke-DockerCompose -Arguments @(
        "exec", "-T", $Script:PostgresService,
        "createdb", "-U", $Script:DatabaseUser, $testDb
    ) -FailureMessage "No se pudo crear la base de prueba."

    Invoke-DockerCompose -Arguments @(
        "exec", "-T", $Script:PostgresService,
        "pg_restore", "-U", $Script:DatabaseUser, "-d", $testDb,
        "--clean", "--if-exists", "--no-owner", "--no-privileges", $remoteDump
    ) -FailureMessage "La restauracion de pg_dump fallo."

    Invoke-PostgresSql -Database $testDb -Sql "SELECT current_database();" | Out-Null
    Write-Log "Restauracion logica de prueba completada en base aislada: $testDb" "OK"
}
catch {
    Write-Log $_.Exception.Message "ERROR"
    throw
}
finally {
    try {
        Invoke-DockerCompose -Arguments @("exec", "-T", $Script:PostgresService, "rm", "-f", $remoteDump) -FailureMessage "No se pudo borrar dump temporal." | Out-Null
    }
    catch {
        Write-Log "No se pudo borrar dump temporal: $($_.Exception.Message)" "WARN"
    }

    if (-not $KeepDatabase) {
        try {
            Invoke-PostgresSql -Database "postgres" -Sql "DROP DATABASE IF EXISTS $testDb WITH (FORCE);" | Out-Null
            Write-Log "Base de prueba eliminada: $testDb" "OK"
        }
        catch {
            Write-Log "No se pudo eliminar la base de prueba '$testDb': $($_.Exception.Message)" "WARN"
        }
    }
}

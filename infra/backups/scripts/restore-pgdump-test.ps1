param(
    [string]$ConfigPath,
    [string]$DumpPath,
    [switch]$RecreateDatabase,
    [switch]$KeepDatabase
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "backup-common.ps1")

Initialize-BackupConfiguration -ConfigPath $ConfigPath
Start-BackupLog -Name "restore-pgdump-test"

Assert-DockerAvailable
Assert-ComposeConfigValid
Assert-PostgresAvailable

function Invoke-PsqlValue {
    param(
        [Parameter(Mandatory = $true)][string]$Sql,
        [string]$Database = $Script:DatabaseName
    )

    return (Get-DockerComposeOutput -Arguments @(
        "exec", "-T", $Script:PostgresService,
        "psql", "-X", "-q", "-t", "-A",
        "-v", "ON_ERROR_STOP=1",
        "-U", $Script:DatabaseUser, "-d", $Database,
        "-c", $Sql
    ) -FailureMessage "psql fallo.").Trim()
}

if ([string]::IsNullOrWhiteSpace($DumpPath)) {
    $dump = Get-LatestFile -Path $Script:DumpDir -Filter "mediqueue_dump_*.dump"
    if (-not $dump) {
        throw "No hay pg_dump disponible en $Script:DumpDir. Ejecuta primero .\infra\backups\scripts\backup-pgdump.ps1; restore-pgdump-test.ps1 nunca restaura sobre la base principal."
    }
    $DumpPath = $dump.FullName
}
else {
    $DumpPath = Resolve-BackupPath -Path $DumpPath -BasePath $Script:RepoRoot -MustExist:$true
}

$testDb = "mediqueue_restore_test"
Assert-NotMainDatabase -Database $testDb
$remoteDump = "/tmp/restore-test-$([guid]::NewGuid().ToString('N')).dump"

try {
    $dbExists = Invoke-PsqlValue -Database "postgres" -Sql "SELECT EXISTS (SELECT 1 FROM pg_database WHERE datname = '$testDb');"
    if ($dbExists -eq "t") {
        if (-not $RecreateDatabase) {
            $answer = Read-Host "La base de prueba '$testDb' ya existe. Escribe RECREATE para eliminarla y recrearla"
            if ($answer -ne "RECREATE") {
                throw "Restauracion cancelada: '$testDb' existe y no se confirmo recreacion."
            }
        }

        Invoke-PostgresSql -Database "postgres" -Sql "DROP DATABASE IF EXISTS $testDb WITH (FORCE);" | Out-Null
        Write-Log "Base de prueba recreada de forma segura: $testDb" "OK"
    }

    Invoke-DockerCompose -Arguments @(
        "exec", "-T", $Script:PostgresService,
        "createdb", "-U", $Script:DatabaseUser, $testDb
    ) -FailureMessage "No se pudo crear la base de prueba."

    $containerId = Get-PostgresContainerId
    Invoke-CheckedCommand -FilePath "docker" -Arguments @("cp", $DumpPath, "$containerId`:$remoteDump") -FailureMessage "No se pudo copiar el dump al contenedor."

    Invoke-DockerCompose -Arguments @(
        "exec", "-T", $Script:PostgresService,
        "pg_restore", "-U", $Script:DatabaseUser, "-d", $testDb,
        "--no-owner", "--no-privileges", $remoteDump
    ) -FailureMessage "La restauracion de pg_dump fallo."

    $requiredSchemas = @("appointment", "patient", "schedule")
    foreach ($schema in $requiredSchemas) {
        $exists = Invoke-PsqlValue -Database $testDb -Sql "SELECT EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name = '$schema');"
        if ($exists -ne "t") {
            throw "Falta esquema requerido en restore test: $schema"
        }
        Write-Log "Schema OK: $schema" "OK"
    }

    $paymentSchemaExists = Invoke-PsqlValue -Database $testDb -Sql "SELECT EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name = 'payment');"
    if ($paymentSchemaExists -eq "t") {
        Write-Log "Schema OK: payment" "OK"
    }
    else {
        Write-Log "Schema opcional no encontrado: payment" "WARN"
    }

    $criticalTables = @(
        @{ Schema = "appointment"; Table = "appointments"; Required = $true },
        @{ Schema = "patient"; Table = "patients"; Required = $true },
        @{ Schema = "schedule"; Table = "dentist_slots"; Required = $true },
        @{ Schema = "payment"; Table = "payments"; Required = ($paymentSchemaExists -eq "t") }
    )

    foreach ($entry in $criticalTables) {
        if (-not $entry.Required) {
            Write-Log "Tabla opcional omitida: $($entry.Schema).$($entry.Table)" "WARN"
            continue
        }

        $tableExists = Invoke-PsqlValue -Database $testDb -Sql "SELECT to_regclass('$($entry.Schema).$($entry.Table)') IS NOT NULL;"
        if ($tableExists -ne "t") {
            throw "Falta tabla critica en restore test: $($entry.Schema).$($entry.Table)"
        }

        $count = Invoke-PsqlValue -Database $testDb -Sql "SELECT count(*) FROM $($entry.Schema).$($entry.Table);"
        Write-Log "Tabla critica OK: $($entry.Schema).$($entry.Table) count=$count" "OK"
    }

    Write-Log "RESTORE_TEST_OK $testDb desde $DumpPath" "OK"
}
catch {
    Write-Log $_.Exception.Message "ERROR"
    throw
}
finally {
    try {
        Invoke-DockerCompose -Arguments @("exec", "-T", $Script:PostgresService, "rm", "-f", $remoteDump) -AllowedExitCodes @(0, 1) -FailureMessage "No se pudo borrar dump temporal." | Out-Null
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

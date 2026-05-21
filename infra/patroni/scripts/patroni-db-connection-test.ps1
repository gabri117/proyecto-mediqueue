param(
    [string]$ComposeFile = "docker-compose.patroni.yml",
    [string]$Database = "mediqueue",
    [string]$User = "mediqueue",
    [string]$Password = "mediqueue",
    [switch]$SkipReader
)

$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..\..\..")
$composeArgs = @("-f", "docker-compose.yml", "-f", $ComposeFile)

function Invoke-PsqlScalar {
    param(
        [string]$Port,
        [string]$Sql
    )

    $result = docker compose @composeArgs exec -T -e "PGPASSWORD=$Password" patroni-postgres-1 `
        psql -h patroni-postgres-lb -p $Port -U $User -d $Database -At -v ON_ERROR_STOP=1 -c $Sql

    if ($LASTEXITCODE -ne 0) {
        throw "psql failed on HAProxy port $Port"
    }

    return (($result | Select-Object -First 1) -as [string]).Trim()
}

Push-Location $root
try {
    Write-Host "PATRONI_DB_TEST_WRITER"
    $writerRecovery = Invoke-PsqlScalar -Port "5432" -Sql "SELECT pg_is_in_recovery();"
    $writerAddr = Invoke-PsqlScalar -Port "5432" -Sql "SELECT COALESCE(inet_server_addr()::text, 'local');"
    Write-Host "WRITER_INET_SERVER_ADDR=$writerAddr"
    Write-Host "WRITER_PG_IS_IN_RECOVERY=$writerRecovery"

    if ($writerRecovery -ne "f") {
        Write-Host "PATRONI_DB_CONNECTION_STATUS=ERROR writer is not primary"
        exit 1
    }

    if (-not $SkipReader) {
        Write-Host "PATRONI_DB_TEST_READER"
        $readerRecovery = Invoke-PsqlScalar -Port "5433" -Sql "SELECT pg_is_in_recovery();"
        $readerAddr = Invoke-PsqlScalar -Port "5433" -Sql "SELECT COALESCE(inet_server_addr()::text, 'local');"
        Write-Host "READER_INET_SERVER_ADDR=$readerAddr"
        Write-Host "READER_PG_IS_IN_RECOVERY=$readerRecovery"

        if ($readerRecovery -ne "t") {
            Write-Host "PATRONI_DB_CONNECTION_STATUS=ERROR reader did not route to replica"
            exit 1
        }
    }

    Write-Host "PATRONI_DB_CONNECTION_STATUS=OK"
}
finally {
    Pop-Location
}

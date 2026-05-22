param(
    [string]$ComposeFile = "docker-compose.patroni.yml",
    [switch]$CreateHealthTable,
    [string]$Database = "mediqueue",
    [string]$User = "postgres",
    [string]$Password = "postgres",
    [int[]]$RestPorts = @(18008, 18009, 18010)
)

$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..\..\..")
$composeArgs = @("-f", "docker-compose.yml", "-f", $ComposeFile)
$leaderService = $null
$nodes = @(
    @{ Service = "patroni-postgres-1"; Port = 18008 },
    @{ Service = "patroni-postgres-2"; Port = 18009 },
    @{ Service = "patroni-postgres-3"; Port = 18010 }
)

foreach ($node in $nodes | Where-Object { $RestPorts -contains $_.Port }) {
    try {
        $port = $node.Port
        $status = Invoke-RestMethod -Uri "http://127.0.0.1:$port/patroni" -TimeoutSec 3
        if ($status.role -eq "primary" -or $status.role -eq "master") {
            $leaderService = if ($status.name) { $status.name } else { $node.Service }
            break
        }
    }
    catch {
        continue
    }
}

if (-not $leaderService) {
    throw "No se encontro lider Patroni para ejecutar SQL."
}

Push-Location $root
try {
    Write-Host "PATRONI_SQL_LEADER=$leaderService"
    Write-Host "PATRONI_SQL_DATABASE=$Database"

    docker compose @composeArgs exec -T -e "PGPASSWORD=$Password" $leaderService psql -U $User -d $Database -v ON_ERROR_STOP=1 -c "SELECT version();"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "PATRONI_SQL_STATUS=ERROR version check failed"
        exit 1
    }

    if ($CreateHealthTable) {
        $sql = @"
CREATE SCHEMA IF NOT EXISTS patroni_health;
CREATE TABLE IF NOT EXISTS patroni_health.sql_check (
  id integer PRIMARY KEY,
  checked_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO patroni_health.sql_check (id, checked_at)
VALUES (1, now())
ON CONFLICT (id) DO UPDATE SET checked_at = excluded.checked_at;
SELECT id, checked_at FROM patroni_health.sql_check WHERE id = 1;
"@

        $sql | docker compose @composeArgs exec -T -e "PGPASSWORD=$Password" $leaderService psql -U $User -d $Database -v ON_ERROR_STOP=1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "PATRONI_SQL_STATUS=ERROR health table check failed"
            exit 1
        }
    }

    Write-Host "PATRONI_SQL_STATUS=OK"
}
finally {
    Pop-Location
}

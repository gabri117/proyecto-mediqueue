param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("patroni-postgres-1", "patroni-postgres-2", "patroni-postgres-3")]
    [string]$ReplicaName,

    [switch]$ConfirmReinit
)

$ErrorActionPreference = "Stop"
$root = Resolve-Path (Join-Path $PSScriptRoot "..\..\..")
$composeArgs = @("-f", "docker-compose.yml", "-f", "docker-compose.patroni.yml")

if (-not $ConfirmReinit) {
    Write-Host "DRY_RUN: reinit no ejecutado para $ReplicaName."
    Write-Host "Use -ConfirmReinit solo si la replica esta rota y acepta reconstruir sus datos locales."
    exit 0
}

Push-Location $root
try {
    Write-Host "REINIT_REPLICA_START replica=$ReplicaName"
    docker compose @composeArgs exec patroni-postgres-1 patronictl -c /etc/patroni/patroni.yml reinit mediqueue-postgres-ha $ReplicaName --force
    Write-Host "REINIT_REPLICA_REQUESTED replica=$ReplicaName"
}
finally {
    Pop-Location
}

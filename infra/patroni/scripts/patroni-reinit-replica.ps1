param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("patroni-postgres-1", "patroni-postgres-2", "patroni-postgres-3")]
    [string]$ReplicaName,

    [switch]$PlanOnly,
    [switch]$Execute,
    [int[]]$RestPorts = @(18008, 18009, 18010)
)

$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..\..\..")
$composeArgs = @("-f", "docker-compose.yml", "-f", "docker-compose.patroni.yml")
$nodes = @(
    @{ Service = "patroni-postgres-1"; Port = 18008 },
    @{ Service = "patroni-postgres-2"; Port = 18009 },
    @{ Service = "patroni-postgres-3"; Port = 18010 }
)

function Get-NodeStatuses {
    $statuses = @()
    foreach ($node in $nodes | Where-Object { $RestPorts -contains $_.Port }) {
        try {
            $status = Invoke-RestMethod -Uri "http://127.0.0.1:$($node.Port)/patroni" -TimeoutSec 3
            $nodeName = if ($status.name) { $status.name } else { $node.Service }
            $statuses += [pscustomobject]@{
                Service = $node.Service
                Name = $nodeName
                Role = $status.role
                State = $status.state
            }
        }
        catch {
            $statuses += [pscustomobject]@{
                Service = $node.Service
                Name = $node.Service
                Role = "unreachable"
                State = "unreachable"
            }
        }
    }
    return $statuses
}

if ($PlanOnly -and $Execute) {
    throw "Use -PlanOnly or -Execute, not both."
}

if (-not $PlanOnly -and -not $Execute) {
    $PlanOnly = $true
}

$target = Get-NodeStatuses | Where-Object { $_.Service -eq $ReplicaName -or $_.Name -eq $ReplicaName } | Select-Object -First 1
if (-not $target) {
    throw "Replica not found: $ReplicaName"
}

Write-Host "REINIT_MODE plan_only=$PlanOnly execute=$Execute"
Write-Host "REINIT_TARGET service=$ReplicaName name=$($target.Name) role=$($target.Role) state=$($target.State)"

if ($target.Role -in @("primary", "master")) {
    throw "Refusing to reinitialize current leader: $ReplicaName"
}

if ($PlanOnly) {
    Write-Host "REINIT_STATUS=PLAN_ONLY"
    Write-Host "REINIT_HINT=Run with -Execute only if this replica is broken and can be rebuilt."
    exit 0
}

Push-Location $root
try {
    Write-Host "REINIT_REPLICA_START replica=$ReplicaName"
    docker compose @composeArgs exec -T patroni-postgres-1 patronictl -c /etc/patroni/patroni.yml reinit mediqueue-postgres-ha $ReplicaName --force
    if ($LASTEXITCODE -ne 0) {
        throw "patronictl reinit failed with exit code $LASTEXITCODE"
    }
    Write-Host "REINIT_STATUS=OK replica=$ReplicaName"
}
catch {
    Write-Host "REINIT_STATUS=ERROR message=$($_.Exception.Message)"
    exit 1
}
finally {
    Pop-Location
}

param(
    [string]$Candidate,
    [switch]$PlanOnly,
    [switch]$Execute,
    [int]$TimeoutSeconds = 120,
    [int[]]$RestPorts = @(18008, 18009, 18010)
)

$ErrorActionPreference = "Stop"

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
                Port = $node.Port
                Role = $status.role
                State = $status.state
            }
        }
        catch {
            $statuses += [pscustomobject]@{
                Service = $node.Service
                Name = $node.Service
                Port = $node.Port
                Role = "unreachable"
                State = "unreachable"
            }
        }
    }
    return $statuses
}

function Get-Leader {
    Get-NodeStatuses | Where-Object { $_.Role -in @("primary", "master") } | Select-Object -First 1
}

function Wait-LeaderChange {
    param([string]$OldLeader)

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        Start-Sleep -Seconds 3
        $leader = Get-Leader
        if ($leader -and $leader.Name -ne $OldLeader) {
            return $leader
        }
    } while ((Get-Date) -lt $deadline)

    throw "Timed out waiting for leader to change from $OldLeader"
}

if ($PlanOnly -and $Execute) {
    throw "Use -PlanOnly or -Execute, not both."
}

if (-not $PlanOnly -and -not $Execute) {
    $PlanOnly = $true
}

$statuses = Get-NodeStatuses
$leader = $statuses | Where-Object { $_.Role -in @("primary", "master") } | Select-Object -First 1
$replicas = $statuses | Where-Object { $_.Role -in @("replica", "standby_leader") }

if (-not $leader) {
    throw "No Patroni leader found."
}

if ($Candidate -and -not ($replicas | Where-Object { $_.Name -eq $Candidate -or $_.Service -eq $Candidate })) {
    throw "Candidate must be a current replica. candidate=$Candidate"
}

Write-Host "SWITCHOVER_MODE plan_only=$PlanOnly execute=$Execute"
Write-Host "SWITCHOVER_CURRENT_LEADER=$($leader.Name)"
Write-Host "SWITCHOVER_REPLICAS=$((@($replicas).Name) -join ',')"

if ($Candidate) {
    Write-Host "SWITCHOVER_CANDIDATE=$Candidate"
}
else {
    Write-Host "SWITCHOVER_CANDIDATE=patroni-selected"
}

if ($PlanOnly) {
    Write-Host "SWITCHOVER_STATUS=PLAN_ONLY"
    Write-Host "SWITCHOVER_HINT=Run with -Execute to request switchover."
    exit 0
}

$leaderEndpoint = "http://127.0.0.1:$($leader.Port)"
$payload = @{ leader = $leader.Name }
if ($Candidate) {
    $payload.candidate = $Candidate
}

Write-Host "SWITCHOVER_REQUEST leader=$($leader.Name) candidate=$Candidate endpoint=$leaderEndpoint"
Invoke-RestMethod -Uri "$leaderEndpoint/switchover" -Method Post -ContentType "application/json" -Body ($payload | ConvertTo-Json -Compress) | Out-Null

$newLeader = Wait-LeaderChange -OldLeader $leader.Name
Write-Host "SWITCHOVER_NEW_LEADER=$($newLeader.Name)"

& "$PSScriptRoot\patroni-db-connection-test.ps1" -SkipReader
if ($LASTEXITCODE -ne 0) {
    throw "Writer validation failed after switchover."
}

Write-Host "SWITCHOVER_STATUS=OK"

param(
    [string]$Candidate,
    [switch]$ConfirmSwitchover,
    [int[]]$RestPorts = @(18008, 18009, 18010)
)

$ErrorActionPreference = "Stop"

if (-not $ConfirmSwitchover) {
    Write-Host "DRY_RUN: switchover no ejecutado."
    Write-Host "Use -ConfirmSwitchover para ejecutar un switchover controlado."
    if ($Candidate) {
        Write-Host "CANDIDATE=$Candidate"
    }
    exit 0
}

$leaderEndpoint = $null
$leaderName = $null

foreach ($port in $RestPorts) {
    try {
        $status = Invoke-RestMethod -Uri "http://127.0.0.1:$port/patroni" -TimeoutSec 3
        if ($status.role -eq "primary" -or $status.role -eq "master") {
            $leaderEndpoint = "http://127.0.0.1:$port"
            $leaderName = $status.name
            break
        }
    }
    catch {
        continue
    }
}

if (-not $leaderEndpoint) {
    throw "No se encontro lider Patroni disponible."
}

$payload = @{ leader = $leaderName }
if ($Candidate) {
    $payload.candidate = $Candidate
}

Write-Host "SWITCHOVER_START leader=$leaderName candidate=$Candidate"
Invoke-RestMethod -Uri "$leaderEndpoint/switchover" -Method Post -ContentType "application/json" -Body ($payload | ConvertTo-Json -Compress) | Out-Null
Write-Host "SWITCHOVER_REQUESTED"

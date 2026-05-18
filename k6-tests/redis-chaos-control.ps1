param(
    [int]$RedisOffAfterSeconds = 90,
    [int]$RedisDownSeconds = 120
)

$ErrorActionPreference = "Stop"

function Invoke-RedisPing {
    $ping = docker compose exec -T redis redis-cli -a redis123 PING
    if ($LASTEXITCODE -ne 0) {
        throw "Redis PING failed."
    }

    $ping = ($ping | Select-Object -Last 1).Trim()
    Write-Host "PING $ping"

    if ($ping -ne "PONG") {
        throw "Unexpected Redis PING response: $ping"
    }
}

Write-Host "Redis ON"
docker compose start redis | Out-Host
Start-Sleep -Seconds 5
Invoke-RedisPing

Write-Host "Waiting $RedisOffAfterSeconds seconds before stopping Redis..."
Start-Sleep -Seconds $RedisOffAfterSeconds

Write-Host "Redis OFF"
docker compose stop redis | Out-Host

Write-Host "Redis will stay OFF for $RedisDownSeconds seconds..."
Start-Sleep -Seconds $RedisDownSeconds

Write-Host "Redis RESTORED"
docker compose start redis | Out-Host
Start-Sleep -Seconds 5
Invoke-RedisPing

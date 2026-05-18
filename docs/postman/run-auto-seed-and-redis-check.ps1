$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$Collection = Join-Path $PSScriptRoot "MediQueue_Auto_Seed_100.postman_collection.json"
$OutputDir = Join-Path $PSScriptRoot "output"
New-Item -ItemType Directory -Force $OutputDir | Out-Null

function Test-CommandExists {
    param([string]$Name)
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Invoke-RedisCli {
    param([string[]]$Args)
    docker compose exec -T -e REDISCLI_AUTH=redis123 redis redis-cli @Args
}

function Write-Section {
    param([string]$Text)
    Write-Host "`n=== $Text ===" -ForegroundColor Cyan
}

Push-Location $Root
try {
    Write-Section "Docker Compose status"
    docker compose ps

    Write-Section "Redis PING"
    Invoke-RedisCli @("PING")

    Write-Section "Redis DBSIZE before"
    $dbsizeBefore = Invoke-RedisCli @("DBSIZE")
    Write-Host "DBSIZE before: $dbsizeBefore"

    if (Test-CommandExists "newman") {
        Write-Section "Running Newman collection"
        newman run $Collection --reporters cli,json --reporter-json-export (Join-Path $OutputDir "seed-100-report.json")
    } else {
        Write-Warning "Newman is not installed. Install it with: npm install -g newman"
        Write-Warning "Then run: newman run docs/postman/MediQueue_Auto_Seed_100.postman_collection.json"
    }

    Write-Section "Redis DBSIZE after"
    $dbsizeAfter = Invoke-RedisCli @("DBSIZE")
    Write-Host "DBSIZE after: $dbsizeAfter"

    Write-Section "Exporting Redis evidence"
    Invoke-RedisCli @("--scan") | Set-Content -Path (Join-Path $OutputDir "redis-keys-all.txt") -Encoding UTF8
    Invoke-RedisCli @("--scan", "--pattern", "patients::*") | Set-Content -Path (Join-Path $OutputDir "redis-keys-patients.txt") -Encoding UTF8
    Invoke-RedisCli @("--scan", "--pattern", "slots::*") | Set-Content -Path (Join-Path $OutputDir "redis-keys-slots.txt") -Encoding UTF8
    Invoke-RedisCli @("INFO", "keyspace") | Set-Content -Path (Join-Path $OutputDir "redis-info-keyspace.txt") -Encoding UTF8
    Invoke-RedisCli @("INFO", "stats") | Set-Content -Path (Join-Path $OutputDir "redis-info-stats.txt") -Encoding UTF8

    $allKeys = @(Get-Content (Join-Path $OutputDir "redis-keys-all.txt") -ErrorAction SilentlyContinue)
    $patientKeys = @(Get-Content (Join-Path $OutputDir "redis-keys-patients.txt") -ErrorAction SilentlyContinue)
    $slotKeys = @(Get-Content (Join-Path $OutputDir "redis-keys-slots.txt") -ErrorAction SilentlyContinue)
    $stats = Get-Content (Join-Path $OutputDir "redis-info-stats.txt") -ErrorAction SilentlyContinue

    Write-Section "Redis summary"
    Write-Host "Total keys:    $($allKeys.Count)"
    Write-Host "Patient keys:  $($patientKeys.Count)"
    Write-Host "Slot keys:     $($slotKeys.Count)"
    $stats | Select-String -Pattern "total_commands_processed|keyspace_hits|keyspace_misses|total_error_replies" | ForEach-Object { Write-Host $_.Line }

    Write-Section "Evidence files"
    Get-ChildItem $OutputDir | Select-Object FullName, Length, LastWriteTime | Format-Table -AutoSize
}
finally {
    Pop-Location
}

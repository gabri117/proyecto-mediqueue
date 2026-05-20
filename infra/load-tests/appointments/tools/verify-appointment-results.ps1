param(
    [Parameter(Mandatory = $true)]
    [string]$SummaryPath,
    [int]$ExpectedCreated = 50000,
    [int]$MaxConflicts = 0,
    [int]$MaxRateLimited = 0,
    [double]$MinSuccessRate = 0.99
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -Path $SummaryPath)) {
    throw "Summary file not found: $SummaryPath"
}

$summary = Get-Content -Raw -Path $SummaryPath | ConvertFrom-Json
$metrics = $summary.metrics

function Get-MetricCount {
    param([string]$Name)

    $metric = $metrics.$Name
    if ($null -eq $metric -or $null -eq $metric.values) {
        return 0
    }
    if ($null -ne $metric.values.count) {
        return [double]$metric.values.count
    }
    return 0
}

function Get-MetricRate {
    param([string]$Name)

    $metric = $metrics.$Name
    if ($null -eq $metric -or $null -eq $metric.values) {
        return 0
    }
    if ($null -ne $metric.values.rate) {
        return [double]$metric.values.rate
    }
    return 0
}

$created = Get-MetricCount -Name "appointment_created"
$conflicts = Get-MetricCount -Name "appointment_conflict"
$rateLimited = Get-MetricCount -Name "appointment_rate_limited"
$unexpected = Get-MetricCount -Name "appointment_unexpected"
$successRate = Get-MetricRate -Name "appointment_success_rate"

$checks = @(
    [ordered]@{ name = "created"; actual = $created; expected = ">=$ExpectedCreated"; passed = $created -ge $ExpectedCreated },
    [ordered]@{ name = "conflicts"; actual = $conflicts; expected = "<=$MaxConflicts"; passed = $conflicts -le $MaxConflicts },
    [ordered]@{ name = "rate_limited"; actual = $rateLimited; expected = "<=$MaxRateLimited"; passed = $rateLimited -le $MaxRateLimited },
    [ordered]@{ name = "unexpected"; actual = $unexpected; expected = "0"; passed = $unexpected -eq 0 },
    [ordered]@{ name = "success_rate"; actual = $successRate; expected = ">=$MinSuccessRate"; passed = $successRate -ge $MinSuccessRate }
)

$checks | Format-Table -AutoSize

$failed = @($checks | Where-Object { -not $_.passed })
if ($failed.Count -gt 0) {
    Write-Error "Appointment load test verification failed."
    exit 1
}

Write-Host "Appointment load test verification passed."

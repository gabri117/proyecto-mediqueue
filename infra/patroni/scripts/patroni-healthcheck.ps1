param(
    [int]$WriterPort = 55432,
    [int]$ReaderPort = 55433,
    [int[]]$RestPorts = @(18008, 18009, 18010)
)

$ErrorActionPreference = "Stop"
$hasPrimary = $false
$reachableNodes = 0

function Test-TcpPort {
    param(
        [string]$HostName,
        [int]$Port
    )

    try {
        $client = [System.Net.Sockets.TcpClient]::new()
        $connect = $client.BeginConnect($HostName, $Port, $null, $null)
        $success = $connect.AsyncWaitHandle.WaitOne(2000, $false)
        if ($success) {
            $client.EndConnect($connect)
        }
        $client.Close()
        return $success
    }
    catch {
        return $false
    }
}

foreach ($port in $RestPorts) {
    try {
        $status = Invoke-RestMethod -Uri "http://127.0.0.1:$port/patroni" -TimeoutSec 3
        $reachableNodes++
        if ($status.role -eq "primary" -or $status.role -eq "master") {
            $hasPrimary = $true
            Write-Host "PATRONI_PRIMARY_OK port=$port role=$($status.role)"
        }
        else {
            Write-Host "PATRONI_NODE_OK port=$port role=$($status.role) state=$($status.state)"
        }
    }
    catch {
        Write-Host "PATRONI_NODE_ERROR port=$port unreachable"
    }
}

$writerOk = Test-TcpPort -HostName "127.0.0.1" -Port $WriterPort
$readerOk = Test-TcpPort -HostName "127.0.0.1" -Port $ReaderPort

Write-Host "PATRONI_REACHABLE_NODES=$reachableNodes"
Write-Host "PATRONI_HAS_PRIMARY=$hasPrimary"
Write-Host "PATRONI_WRITER_TCP_OK=$writerOk"
Write-Host "PATRONI_READER_TCP_OK=$readerOk"

if (-not $hasPrimary -or -not $writerOk) {
    Write-Host "PATRONI_HEALTH_STATUS=ERROR"
    exit 1
}

if (-not $readerOk) {
    Write-Host "PATRONI_HEALTH_STATUS=WARNING reader endpoint unavailable"
    exit 0
}

Write-Host "PATRONI_HEALTH_STATUS=OK"

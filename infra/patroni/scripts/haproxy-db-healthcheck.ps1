param(
    [int]$WriterPort = 55432,
    [int]$ReaderPort = 55433,
    [int]$StatsPort = 7000,
    [switch]$SkipReader,
    [switch]$SkipStats
)

$ErrorActionPreference = "Stop"

function Test-TcpPort {
    param(
        [string]$HostName,
        [int]$Port
    )

    try {
        $client = [System.Net.Sockets.TcpClient]::new()
        $connect = $client.BeginConnect($HostName, $Port, $null, $null)
        $success = $connect.AsyncWaitHandle.WaitOne(3000, $false)
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

$writerOk = Test-TcpPort -HostName "127.0.0.1" -Port $WriterPort
Write-Host "HAPROXY_WRITER_TCP_OK=$writerOk port=$WriterPort"

$readerOk = $true
if (-not $SkipReader) {
    $readerOk = Test-TcpPort -HostName "127.0.0.1" -Port $ReaderPort
    Write-Host "HAPROXY_READER_TCP_OK=$readerOk port=$ReaderPort"
}

$statsOk = $true
if (-not $SkipStats) {
    try {
        $response = Invoke-WebRequest -Uri "http://127.0.0.1:$StatsPort/" -UseBasicParsing -TimeoutSec 5
        $statsOk = ($response.StatusCode -eq 200)
    }
    catch {
        $statsOk = $false
    }
    Write-Host "HAPROXY_STATS_HTTP_OK=$statsOk port=$StatsPort"
}

if (-not $writerOk -or -not $readerOk -or -not $statsOk) {
    Write-Host "HAPROXY_DB_HEALTH_STATUS=ERROR"
    exit 1
}

Write-Host "HAPROXY_DB_HEALTH_STATUS=OK"

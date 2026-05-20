param(
    [string]$ConfigPath,
    [int]$MaxAgeMinutes = 10,
    [int]$WaitSeconds = 90
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "backup-common.ps1")

Initialize-BackupConfiguration -ConfigPath $ConfigPath
Start-BackupLog -Name "verify-wal-archive"

Assert-DockerAvailable
Assert-ComposeConfigValid
Assert-PostgresAvailable

function Invoke-PsqlValue {
    param([Parameter(Mandatory = $true)][string]$Sql)

    return (Get-DockerComposeOutput -Arguments @(
        "exec", "-T", $Script:PostgresService,
        "psql", "-X", "-q", "-t", "-A",
        "-U", $Script:DatabaseUser, "-d", $Script:DatabaseName,
        "-c", $Sql
    ) -FailureMessage "psql fallo.").Trim()
}

function Get-ArchiverStats {
    $json = Invoke-PsqlValue -Sql @"
SELECT row_to_json(s)
FROM (
  SELECT
    archived_count,
    failed_count,
    last_archived_wal,
    last_archived_time,
    last_failed_wal,
    last_failed_time
  FROM pg_stat_archiver
) s;
"@

    return $json | ConvertFrom-Json
}

function Get-WalFiles {
    return @(Get-ChildItem -LiteralPath $Script:WalArchiveDir -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^[0-9A-F]{24}(\.partial)?$' } |
        Sort-Object LastWriteTime -Descending)
}

try {
    $walLevel = Invoke-PsqlValue -Sql "SHOW wal_level;"
    $archiveMode = Invoke-PsqlValue -Sql "SHOW archive_mode;"
    $archiveTimeout = Invoke-PsqlValue -Sql "SHOW archive_timeout;"
    $archiveCommand = Invoke-PsqlValue -Sql "SHOW archive_command;"

    Write-Log "wal_level=$walLevel"
    Write-Log "archive_mode=$archiveMode"
    Write-Log "archive_timeout=$archiveTimeout"
    Write-Log "archive_command=$archiveCommand"

    $beforeStats = Get-ArchiverStats
    $beforeFiles = Get-WalFiles
    $beforeNames = @($beforeFiles | ForEach-Object { $_.Name })

    Write-Log "pg_stat_archiver antes: archived_count=$($beforeStats.archived_count), failed_count=$($beforeStats.failed_count), last_archived_wal=$($beforeStats.last_archived_wal), last_archived_time=$($beforeStats.last_archived_time), last_failed_wal=$($beforeStats.last_failed_wal), last_failed_time=$($beforeStats.last_failed_time)"

    Invoke-PsqlValue -Sql "SELECT pg_switch_wal();" | Out-Null

    $deadline = (Get-Date).AddSeconds($WaitSeconds)
    $afterStats = $beforeStats
    $afterFiles = $beforeFiles
    $changed = $false

    do {
        Start-Sleep -Seconds 5
        $afterStats = Get-ArchiverStats
        $afterFiles = Get-WalFiles
        $afterNames = @($afterFiles | ForEach-Object { $_.Name })

        $archivedCountIncreased = [int64]$afterStats.archived_count -gt [int64]$beforeStats.archived_count
        $lastArchivedChanged = "$($afterStats.last_archived_time)" -ne "$($beforeStats.last_archived_time)"
        $newWalFileAppeared = @($afterNames | Where-Object { $beforeNames -notcontains $_ }).Count -gt 0
        $failedCountIncreased = [int64]$afterStats.failed_count -gt [int64]$beforeStats.failed_count

        if ($failedCountIncreased) {
            throw "pg_stat_archiver failed_count aumento de $($beforeStats.failed_count) a $($afterStats.failed_count). last_failed_wal=$($afterStats.last_failed_wal), last_failed_time=$($afterStats.last_failed_time)"
        }

        $changed = $archivedCountIncreased -or $lastArchivedChanged -or $newWalFileAppeared
    } while (-not $changed -and (Get-Date) -lt $deadline)

    Write-Log "pg_stat_archiver despues: archived_count=$($afterStats.archived_count), failed_count=$($afterStats.failed_count), last_archived_wal=$($afterStats.last_archived_wal), last_archived_time=$($afterStats.last_archived_time), last_failed_wal=$($afterStats.last_failed_wal), last_failed_time=$($afterStats.last_failed_time)"

    $latestWal = $afterFiles | Select-Object -First 1
    $hasRecentWal = $false
    if ($latestWal) {
        $ageMinutes = ((Get-Date) - $latestWal.LastWriteTime).TotalMinutes
        $hasRecentWal = $ageMinutes -le $MaxAgeMinutes
        Write-Log ("WAL mas reciente: {0}, edad {1:N1} minutos." -f $latestWal.FullName, $ageMinutes)
    }

    Write-Log "Ultimos 10 WAL archivados:"
    $afterFiles | Select-Object -First 10 | ForEach-Object {
        Write-Log ("  {0} | {1} bytes | {2}" -f $_.Name, $_.Length, $_.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss"))
    }

    if ($changed) {
        Write-Log "WAL_OK" "OK"
        return
    }

    if ($hasRecentWal -and ([int64]$afterStats.failed_count -eq [int64]$beforeStats.failed_count)) {
        Write-Log "WAL_WARNING: no hubo cambio tras pg_switch_wal(), pero existe WAL reciente y failed_count no aumento." "WARN"
        return
    }

    throw "Verificacion WAL fallida: no hubo archivado nuevo y no existe WAL reciente."
}
catch {
    Write-Log $_.Exception.Message "ERROR"
    throw
}

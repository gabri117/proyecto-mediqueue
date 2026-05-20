param(
    [string]$BackupRoot = $env:MEDIQUEUE_BACKUP_ROOT,
    [int]$MaxBaseAgeHours = 30,
    [int]$MaxDumpAgeHours = 30,
    [int]$MaxWalAgeMinutes = 10
)

$ErrorActionPreference = "Stop"
if (-not $BackupRoot) { $BackupRoot = ".\infra\backups" }

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logDir = Join-Path $BackupRoot "logs"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$logFile = Join-Path $logDir "verify-backups-$stamp.log"

function Write-Log {
    param([string]$Message)
    $line = "$(Get-Date -Format o) $Message"
    Write-Host $line
    Add-Content -Path $logFile -Value $line -Encoding utf8
}

function Get-LatestFile {
    param([string]$Path, [string]$Filter)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    return Get-ChildItem -LiteralPath $Path -File -Filter $Filter |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}

function Get-LatestDirectory {
    param([string]$Path, [string]$Filter)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    return Get-ChildItem -LiteralPath $Path -Directory -Filter $Filter |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}

try {
    $failures = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]

    $base = Get-LatestDirectory -Path (Join-Path $BackupRoot "local") -Filter "mediqueue_base_*"
    $baseTar = if ($null -ne $base) { Join-Path $base.FullName "base.tar.gz" } else { $null }
    $manifest = if ($null -ne $base) { Join-Path $base.FullName "backup_manifest" } else { $null }
    if ($null -eq $base -or -not (Test-Path -LiteralPath $baseTar) -or -not (Test-Path -LiteralPath $manifest) -or (Get-Item -LiteralPath $baseTar).Length -le 0) {
        $failures.Add("No existe backup base valido.")
    } elseif ($base.LastWriteTime -lt (Get-Date).AddHours(-$MaxBaseAgeHours)) {
        $failures.Add("Backup base demasiado antiguo: $($base.FullName)")
    } else {
        Write-Log "BASE_OK dir=$($base.FullName) baseTarBytes=$((Get-Item -LiteralPath $baseTar).Length)"
    }

    $dump = Get-LatestFile -Path (Join-Path $BackupRoot "dumps") -Filter "mediqueue_dump_*.dump"
    if ($null -eq $dump -or $dump.Length -le 0) {
        $failures.Add("No existe pg_dump valido.")
    } elseif ($dump.LastWriteTime -lt (Get-Date).AddHours(-$MaxDumpAgeHours)) {
        $failures.Add("pg_dump demasiado antiguo: $($dump.FullName)")
    } else {
        Write-Log "DUMP_OK file=$($dump.FullName) bytes=$($dump.Length)"
        $checksumFile = "$($dump.FullName).sha256"
        if (Test-Path -LiteralPath $checksumFile) {
            $expected = ((Get-Content -Raw -LiteralPath $checksumFile).Trim() -split "\s+")[0]
            $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $dump.FullName).Hash
            if ($expected -ne $actual) {
                $failures.Add("Checksum invalido para pg_dump: $($dump.FullName)")
            } else {
                Write-Log "DUMP_CHECKSUM_OK file=$checksumFile"
            }
        } else {
            $warnings.Add("No existe checksum para pg_dump: $($dump.FullName)")
        }
    }

    $walRoot = Join-Path $BackupRoot "wal-archive"
    $latestWal = $null
    if (Test-Path -LiteralPath $walRoot) {
        $latestWal = Get-ChildItem -LiteralPath $walRoot -File -Recurse |
            Where-Object { $_.Name -ne ".gitkeep" } |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
    }
    if ($null -eq $latestWal) {
        $failures.Add("No existe WAL archivado verificable.")
    } elseif ($latestWal.LastWriteTime -lt (Get-Date).AddMinutes(-$MaxWalAgeMinutes)) {
        $failures.Add("WAL demasiado antiguo para RPO objetivo: $($latestWal.FullName)")
    } else {
        Write-Log "WAL_OK file=$($latestWal.FullName) ageMinutes=$([Math]::Round(((Get-Date) - $latestWal.LastWriteTime).TotalMinutes, 2))"
    }

    if ($failures.Count -gt 0) {
        foreach ($failure in $failures) { Write-Log "VERIFY_FAIL $failure" }
        Write-Log "STATUS=ERROR"
        exit 1
    }

    foreach ($warning in $warnings) { Write-Log "VERIFY_WARNING $warning" }
    if ($warnings.Count -gt 0) {
        Write-Log "STATUS=WARNING"
    } else {
        Write-Log "STATUS=OK"
    }
    Write-Log "VERIFY_OK"
    exit 0
} catch {
    Write-Log "ERROR $($_.Exception.Message)"
    exit 1
}

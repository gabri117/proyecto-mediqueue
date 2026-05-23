param(
    [string]$BackupRoot = $env:MEDIQUEUE_BACKUP_ROOT,
    [string]$GoogleDriveBackupPath,
    [int]$MaxBaseAgeHours = 30,
    [int]$MaxDumpAgeHours = 30,
    [int]$MaxWalAgeMinutes = 10,
    [switch]$SkipBaseCheck
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\backup-common.ps1"
$cfg = Get-MediQueueBackupConfig
if (-not $BackupRoot) { $BackupRoot = $cfg.BackupRoot }
if (-not $GoogleDriveBackupPath) { $GoogleDriveBackupPath = $cfg.GoogleDriveBackupPath }
$BackupMode = $cfg.BackupMode

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
    Write-Log "BACKUP_MODE=$BackupMode"

    if ($BackupMode -eq "patroni") {
        $patroniHealthScript = Join-Path $PSScriptRoot "..\..\patroni\scripts\patroni-healthcheck.ps1"
        if (Test-Path -LiteralPath $patroniHealthScript) {
            & $patroniHealthScript 2>&1 | Tee-Object -FilePath $logFile -Append
            if ($LASTEXITCODE -ne 0) {
                $failures.Add("Patroni healthcheck fallo.")
            } else {
                Write-Log "PATRONI_HEALTH_OK"
            }
        } else {
            $warnings.Add("No se encontro patroni-healthcheck.ps1 para validar modo Patroni.")
        }
    } elseif ($BackupMode -ne "single") {
        $failures.Add("BackupMode invalido: $BackupMode")
    }

    if ($SkipBaseCheck) {
        Write-Log "BASE_SKIPPED reason=SkipBaseCheck"
    } else {
        $base = Get-LatestDirectory -Path (Join-Path $BackupRoot "local") -Filter "mediqueue_base_*"
        $baseTar = if ($null -ne $base) { Join-Path $base.FullName "base.tar.gz" } else { $null }
        $walTar = if ($null -ne $base) { Join-Path $base.FullName "pg_wal.tar.gz" } else { $null }
        $manifest = if ($null -ne $base) { Join-Path $base.FullName "backup_manifest" } else { $null }
        $shaFile = if ($null -ne $base) { Join-Path $base.FullName "SHA256SUMS" } else { $null }
        $markerFile = if ($null -ne $base) { Join-Path $base.FullName "BACKUP_BASE_OK.txt" } else { $null }
        if ($null -eq $base -or
            -not (Test-Path -LiteralPath $baseTar) -or
            -not (Test-Path -LiteralPath $walTar) -or
            -not (Test-Path -LiteralPath $manifest) -or
            -not (Test-Path -LiteralPath $shaFile) -or
            -not (Test-Path -LiteralPath $markerFile) -or
            (Get-Item -LiteralPath $baseTar).Length -le 0 -or
            (Get-Item -LiteralPath $walTar).Length -le 0) {
            $failures.Add("No existe backup base valido.")
        } elseif ($base.LastWriteTime -lt (Get-Date).AddHours(-$MaxBaseAgeHours)) {
            $failures.Add("Backup base demasiado antiguo: $($base.FullName)")
        } else {
            Write-Log "BASE_OK dir=$($base.FullName) baseTarBytes=$((Get-Item -LiteralPath $baseTar).Length) pgWalTarBytes=$((Get-Item -LiteralPath $walTar).Length)"
        }
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

    $walRoot = if ($BackupMode -eq "patroni") { Join-Path $BackupRoot "wal-archive\patroni" } else { Join-Path $BackupRoot "wal-archive" }
    $latestWal = $null
    if (Test-Path -LiteralPath $walRoot) {
        $latestWal = Get-ChildItem -LiteralPath $walRoot -File -Recurse |
            Where-Object {
                $_.Name -ne ".gitkeep" -and
                ($BackupMode -ne "single" -or $_.FullName -notlike "*\wal-archive\patroni\*")
            } |
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

    if ($GoogleDriveBackupPath) {
        if (-not (Test-Path -LiteralPath $GoogleDriveBackupPath)) {
            $failures.Add("DRIVE_SYNC_ERROR ruta configurada no existe: $GoogleDriveBackupPath")
        } else {
            $driveStats = Get-DirectoryStats -Path $GoogleDriveBackupPath
            if ($driveStats.Count -lt 1 -or $driveStats.Bytes -lt 1) {
                $warnings.Add("DRIVE_SYNC_WARNING carpeta existe pero no contiene backups: $GoogleDriveBackupPath")
            } else {
                Write-Log "DRIVE_SYNC_OK path=$GoogleDriveBackupPath files=$($driveStats.Count) bytes=$($driveStats.Bytes)"
            }
        }
    } else {
        $warnings.Add("DRIVE_SYNC_WARNING GoogleDriveBackupPath no configurado.")
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

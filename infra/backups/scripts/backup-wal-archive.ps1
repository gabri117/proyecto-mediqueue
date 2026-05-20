param(
    [string]$ConfigPath
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "backup-common.ps1")

Initialize-BackupConfiguration -ConfigPath $ConfigPath
Start-BackupLog -Name "backup-wal-archive"

Assert-DockerAvailable
Assert-ComposeConfigValid
Assert-PostgresAvailable

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$snapshotDir = Join-Path $Script:LocalBackupDir "wal_archive_snapshot_$timestamp"

try {
    New-Item -ItemType Directory -Force -Path $snapshotDir | Out-Null

    $walFiles = Get-ChildItem -LiteralPath $Script:WalArchiveDir -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^[0-9A-F]{24}(\.partial)?$' } |
        Sort-Object Name

    if (-not $walFiles -or $walFiles.Count -eq 0) {
        throw "No hay WAL archivados para copiar desde $Script:WalArchiveDir"
    }

    foreach ($walFile in $walFiles) {
        Copy-Item -LiteralPath $walFile.FullName -Destination (Join-Path $snapshotDir $walFile.Name) -Force
    }

    $snapshotFiles = Get-ChildItem -LiteralPath $snapshotDir -File -ErrorAction Stop
    $totalBytes = ($snapshotFiles | Measure-Object -Property Length -Sum).Sum
    $manifestPath = Join-Path $snapshotDir "WAL_SNAPSHOT.txt"
    @(
        "WAL_SNAPSHOT_OK"
        "created_at=$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        "source=$Script:WalArchiveDir"
        "file_count=$($snapshotFiles.Count)"
        "total_bytes=$totalBytes"
    ) | Set-Content -LiteralPath $manifestPath -Encoding ASCII

    Write-Log "WAL snapshot creado: $snapshotDir" "OK"
    Write-Log "WAL snapshot conteo=$($snapshotFiles.Count), bytes=$totalBytes" "OK"
}
catch {
    Write-Log $_.Exception.Message "ERROR"
    throw
}

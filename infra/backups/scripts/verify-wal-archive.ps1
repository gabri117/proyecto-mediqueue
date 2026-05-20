param(
    [string]$ConfigPath,
    [int]$MaxAgeMinutes = 10
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "backup-common.ps1")

Initialize-BackupConfiguration -ConfigPath $ConfigPath
Start-BackupLog -Name "verify-wal-archive"

Assert-DockerAvailable
Assert-ComposeConfigValid
Assert-PostgresAvailable

$latestWal = Get-ChildItem -LiteralPath $Script:WalArchiveDir -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '^[0-9A-F]{24}(\.partial)?$' } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $latestWal) {
    Write-Log "No hay archivos WAL archivados en $Script:WalArchiveDir" "ERROR"
    throw "Verificacion WAL fallida: no hay archivos WAL."
}

$ageMinutes = ((Get-Date) - $latestWal.LastWriteTime).TotalMinutes
if ($ageMinutes -gt $MaxAgeMinutes) {
    Write-Log ("El ultimo WAL '{0}' tiene {1:N1} minutos; excede {2}." -f $latestWal.Name, $ageMinutes, $MaxAgeMinutes) "ERROR"
    throw "Verificacion WAL fallida: RPO objetivo en riesgo."
}

Write-Log ("WAL vigente: {0}, edad {1:N1} minutos." -f $latestWal.FullName, $ageMinutes) "OK"

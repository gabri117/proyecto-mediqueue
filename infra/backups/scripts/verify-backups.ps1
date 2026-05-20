param(
    [string]$ConfigPath,
    [int]$MaxBaseAgeHours = 30,
    [int]$MaxDumpAgeHours = 30,
    [int]$MaxWalAgeMinutes = 10
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "backup-common.ps1")

Initialize-BackupConfiguration -ConfigPath $ConfigPath
Start-BackupLog -Name "verify-backups"

Assert-DockerAvailable
Assert-ComposeConfigValid
Assert-PostgresAvailable

$now = Get-Date
$baseBackup = Get-ChildItem -LiteralPath $Script:LocalBackupDir -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like "mediqueue_base_*" } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
$dump = Get-LatestFile -Path $Script:DumpDir -Filter "mediqueue-*.dump"
$wal = Get-ChildItem -LiteralPath $Script:WalArchiveDir -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '^[0-9A-F]{24}(\.partial)?$' } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $baseBackup) {
    throw "No se encontro backup base en $Script:LocalBackupDir"
}
if ((($now - $baseBackup.LastWriteTime).TotalHours) -gt $MaxBaseAgeHours) {
    throw "El backup base mas reciente excede $MaxBaseAgeHours horas: $($baseBackup.FullName)"
}
$baseBackupFiles = @(Get-ChildItem -LiteralPath $baseBackup.FullName -File -Recurse -ErrorAction Stop)
if ($baseBackupFiles.Count -eq 0) {
    throw "El backup base esta vacio: $($baseBackup.FullName)"
}
if (-not (Test-Path -LiteralPath (Join-Path $baseBackup.FullName "BASE_BACKUP_OK"))) {
    throw "El backup base no tiene marcador BASE_BACKUP_OK: $($baseBackup.FullName)"
}
if (-not (Test-Path -LiteralPath (Join-Path $baseBackup.FullName "SHA256SUMS"))) {
    throw "El backup base no tiene SHA256SUMS: $($baseBackup.FullName)"
}
Write-Log "Backup base valido: $($baseBackup.FullName)" "OK"

if (-not $dump) {
    throw "No se encontro pg_dump en $Script:DumpDir"
}
if ((($now - $dump.LastWriteTime).TotalHours) -gt $MaxDumpAgeHours) {
    throw "El pg_dump mas reciente excede $MaxDumpAgeHours horas: $($dump.FullName)"
}
$remoteVerifyDump = "/tmp/verify-$([guid]::NewGuid().ToString('N')).dump"
try {
    $containerId = Get-PostgresContainerId
    Invoke-CheckedCommand -FilePath "docker" -Arguments @("cp", $dump.FullName, "$containerId`:$remoteVerifyDump") -FailureMessage "No se pudo copiar el dump para verificacion."
    Invoke-DockerCompose -Arguments @(
        "exec", "-T", $Script:PostgresService,
        "pg_restore", "-l", $remoteVerifyDump
    ) -FailureMessage "El pg_dump no se pudo listar con pg_restore."
}
finally {
    Invoke-DockerCompose -Arguments @("exec", "-T", $Script:PostgresService, "rm", "-f", $remoteVerifyDump) -AllowedExitCodes @(0, 1) -FailureMessage "No se pudo limpiar dump temporal de verificacion." | Out-Null
}
Write-Log "pg_dump custom valido: $($dump.FullName)" "OK"

if (-not $wal) {
    throw "No se encontraron WAL en $Script:WalArchiveDir"
}
if ((($now - $wal.LastWriteTime).TotalMinutes) -gt $MaxWalAgeMinutes) {
    throw "El WAL mas reciente excede $MaxWalAgeMinutes minutos: $($wal.FullName)"
}
Write-Log "WAL vigente: $($wal.FullName)" "OK"

Write-Log "Verificacion diaria completada." "OK"

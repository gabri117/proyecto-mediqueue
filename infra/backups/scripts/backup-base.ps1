param(
    [string]$ConfigPath
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "backup-common.ps1")

Initialize-BackupConfiguration -ConfigPath $ConfigPath
Start-BackupLog -Name "backup-base"

Assert-DockerAvailable
Assert-ComposeConfigValid
Assert-PostgresAvailable

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$baseName = "mediqueue_base_$timestamp"
$remoteDir = "/backups/$baseName"
$localDir = Join-Path $Script:LocalBackupDir $baseName
$statusFile = Join-Path $localDir "BASE_BACKUP_OK"
$shaFile = Join-Path $localDir "SHA256SUMS"

try {
    if (Test-Path -LiteralPath $localDir) {
        throw "El directorio de backup ya existe: $localDir"
    }

    $baseBackupHelp = Get-DockerComposeOutput -Arguments @(
        "exec", "-T", $Script:PostgresService,
        "pg_basebackup", "--help"
    ) -FailureMessage "No se pudo consultar pg_basebackup --help."

    $manifestOption = ""
    if ($baseBackupHelp -match "--manifest-checksums") {
        $manifestOption = " --manifest-checksums=SHA256"
        Write-Log "pg_basebackup soporta manifest/checksum; se usara --manifest-checksums=SHA256." "OK"
    }
    else {
        Write-Log "pg_basebackup no reporta soporte de --manifest-checksums; se continuara sin esa opcion." "WARN"
    }

    $backupCommand = @(
        "rm -rf '$remoteDir'",
        "mkdir -p '$remoteDir'",
        "pg_basebackup -U '$Script:DatabaseUser' -D '$remoteDir' -Fp -Xs -P -c fast$manifestOption"
    ) -join " && "

    Invoke-DockerCompose -Arguments @("exec", "-T", $Script:PostgresService, "sh", "-lc", $backupCommand) -FailureMessage "El backup fisico/base fallo."

    if (-not (Test-Path -LiteralPath $localDir)) {
        throw "El backup base no existe en el host: $localDir"
    }

    $files = Get-ChildItem -LiteralPath $localDir -File -Recurse -ErrorAction Stop
    if ($files.Count -eq 0) {
        throw "El backup base esta vacio: $localDir"
    }

    $totalBytes = ($files | Measure-Object -Property Length -Sum).Sum
    if ($totalBytes -le 0) {
        throw "El backup base no contiene datos: $localDir"
    }

    if (Test-Path -LiteralPath (Join-Path $localDir "backup_manifest")) {
        Write-Log "Manifest de pg_basebackup detectado: $(Join-Path $localDir 'backup_manifest')" "OK"
    }
    else {
        Write-Log "pg_basebackup no genero backup_manifest; revisa version/opciones del cliente." "WARN"
    }

    Get-ChildItem -LiteralPath $localDir -File -Recurse |
        Where-Object { $_.FullName -ne $shaFile -and $_.FullName -ne $statusFile } |
        Sort-Object FullName |
        ForEach-Object {
            $relativePath = $_.FullName.Substring($localDir.Length).TrimStart([char[]]@("\", "/")).Replace("\", "/")
            $hash = Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256
            "{0}  {1}" -f $hash.Hash.ToLowerInvariant(), $relativePath
        } | Set-Content -LiteralPath $shaFile -Encoding ASCII

    "BASE_BACKUP_OK {0} {1} bytes" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $totalBytes |
        Set-Content -LiteralPath $statusFile -Encoding ASCII

    Write-Log "BASE_BACKUP_OK $localDir ($($files.Count) archivos, $totalBytes bytes)" "OK"
}
catch {
    Write-Log $_.Exception.Message "ERROR"
    throw
}

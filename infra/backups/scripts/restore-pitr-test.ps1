param(
    [string]$ConfigPath,
    [string]$BaseBackupPath,
    [datetime]$RecoveryTargetTime = (Get-Date),
    [switch]$KeepContainer
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "backup-common.ps1")

Initialize-BackupConfiguration -ConfigPath $ConfigPath
Start-BackupLog -Name "restore-pitr-test"

Assert-DockerAvailable
Assert-ComposeConfigValid

if ([string]::IsNullOrWhiteSpace($BaseBackupPath)) {
    $baseBackup = Get-LatestFile -Path $Script:LocalBackupDir -Filter "mediqueue-base-*.tar.gz"
    if (-not $baseBackup) {
        throw "No hay backup base disponible en $Script:LocalBackupDir"
    }
    $BaseBackupPath = $baseBackup.FullName
}
else {
    $BaseBackupPath = Resolve-BackupPath -Path $BaseBackupPath -BasePath $Script:RepoRoot -MustExist:$true
}

$walCount = (Get-ChildItem -LiteralPath $Script:WalArchiveDir -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '^[0-9A-F]{24}(\.partial)?$' }).Count
if ($walCount -eq 0) {
    throw "No hay WAL archivados para probar PITR en $Script:WalArchiveDir"
}

$stamp = Get-Date -Format "yyyyMMddHHmmss"
$restoreRoot = Join-Path $Script:RestoreTestDir "pitr-$stamp"
$extractRoot = Join-Path $restoreRoot "extract"
$dataDir = Join-Path $restoreRoot "data"
$containerName = "mediqueue-pitr-test-$stamp"

try {
    New-Item -ItemType Directory -Force -Path $extractRoot, $dataDir | Out-Null
    Invoke-CheckedCommand -FilePath "tar" -Arguments @("-xzf", $BaseBackupPath, "-C", $extractRoot) -FailureMessage "No se pudo extraer el backup base."

    $extractedData = Get-ChildItem -LiteralPath $extractRoot -Directory | Select-Object -First 1
    if (-not $extractedData) {
        throw "El backup base no contiene un directorio de datos."
    }
    Copy-Item -Path (Join-Path $extractedData.FullName "*") -Destination $dataDir -Recurse -Force

    $autoConf = Join-Path $dataDir "postgresql.auto.conf"
    Add-Content -LiteralPath $autoConf -Value "restore_command = 'cp /wal-archive/%f %p'"
    Add-Content -LiteralPath $autoConf -Value ("recovery_target_time = '{0}'" -f $RecoveryTargetTime.ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ss'Z'"))
    Add-Content -LiteralPath $autoConf -Value "recovery_target_action = 'promote'"
    New-Item -ItemType File -Path (Join-Path $dataDir "recovery.signal") -Force | Out-Null

    Invoke-CheckedCommand -FilePath "docker" -Arguments @(
        "run", "-d", "--rm",
        "--name", $containerName,
        "-p", "$($Script:PitrTestPort):5432",
        "-v", "$dataDir`:/var/lib/postgresql/data",
        "-v", "$($Script:WalArchiveDir):/wal-archive:ro",
        "postgres:16"
    ) -FailureMessage "No se pudo iniciar el contenedor PITR de prueba."

    $ready = $false
    for ($i = 0; $i -lt 30; $i++) {
        $result = Get-CommandOutput -FilePath "docker" -Arguments @("exec", $containerName, "pg_isready", "-U", $Script:DatabaseUser, "-d", $Script:DatabaseName) -AllowedExitCodes @(0, 1, 2) -FailureMessage "pg_isready fallo en PITR."
        if ($LASTEXITCODE -eq 0 -or $result -match "accepting connections") {
            $ready = $true
            break
        }
        Start-Sleep -Seconds 5
    }

    if (-not $ready) {
        throw "El contenedor PITR de prueba no quedo disponible."
    }

    Invoke-CheckedCommand -FilePath "docker" -Arguments @(
        "exec", $containerName,
        "psql", "-v", "ON_ERROR_STOP=1", "-U", $Script:DatabaseUser, "-d", $Script:DatabaseName,
        "-c", "SELECT current_database(), now();"
    ) -FailureMessage "La validacion PITR con psql fallo."

    Write-Log "Restauracion PITR de prueba completada en contenedor aislado: $containerName" "OK"
}
catch {
    Write-Log $_.Exception.Message "ERROR"
    throw
}
finally {
    if (-not $KeepContainer) {
        try {
            Invoke-CheckedCommand -FilePath "docker" -Arguments @("rm", "-f", $containerName) -AllowedExitCodes @(0, 1) -FailureMessage "No se pudo eliminar el contenedor PITR." | Out-Null
            Write-Log "Contenedor PITR eliminado: $containerName" "OK"
        }
        catch {
            Write-Log "No se pudo eliminar el contenedor PITR '$containerName': $($_.Exception.Message)" "WARN"
        }
    }
}

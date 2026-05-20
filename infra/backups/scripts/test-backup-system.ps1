param(
    [string]$ConfigPath,
    [switch]$SkipDocker
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "backup-common.ps1")

Initialize-BackupConfiguration -ConfigPath $ConfigPath
Start-BackupLog -Name "test-backup-system"

$createdPaths = @()

try {
    if (-not $Script:ConfigLoaded) {
        throw "No se encontro backup.local.ps1. Crea infra/backups/config/backup.local.ps1 antes de probar la sincronizacion."
    }
    if ([string]::IsNullOrWhiteSpace($Script:GoogleDriveBackupPath)) {
        throw "GoogleDriveBackupPath no esta configurado en backup.local.ps1."
    }

    $destinationRoot = $Script:GoogleDriveBackupPathFull
    if (-not (Test-Path -LiteralPath $destinationRoot)) {
        throw "La ruta GoogleDriveBackupPath no existe: $destinationRoot"
    }

    $parserErrors = @()
    $scripts = Get-ChildItem -LiteralPath $PSScriptRoot -Filter "*.ps1" -File
    foreach ($script in $scripts) {
        $tokens = $null
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($script.FullName, [ref]$tokens, [ref]$errors) | Out-Null
        if ($errors.Count -gt 0) {
            $parserErrors += $errors | ForEach-Object { "$($script.Name): $($_.Message)" }
        }
    }

    if ($parserErrors.Count -gt 0) {
        $parserErrors | ForEach-Object { Write-Log $_ "ERROR" }
        throw "Validacion PowerShell AST fallida."
    }
    Write-Log "Validacion PowerShell AST correcta para $($scripts.Count) scripts." "OK"

    if (-not $SkipDocker) {
        Assert-DockerAvailable
        Assert-ComposeConfigValid
        Write-Log "docker compose config --quiet correcto." "OK"
    }

    @(
        $Script:LocalBackupDir,
        $Script:DumpDir,
        $Script:WalArchiveDir,
        $Script:LogDir,
        $Script:RestoreTestDir,
        $Script:WeeklyDir,
        $Script:MonthlyDir
    ) | ForEach-Object {
        if (-not (Test-Path -LiteralPath $_)) {
            throw "Falta directorio requerido: $_"
        }
        Write-Log "Directorio presente: $_" "OK"
    }

    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $token = [guid]::NewGuid().ToString("N")
    $dumpName = "sync_test_$stamp`_$token.dump"
    $shaName = "$dumpName.sha256"
    $logName = "sync_test_$stamp`_$token.log"

    $sourceDump = Join-Path $Script:DumpDir $dumpName
    $sourceSha = Join-Path $Script:DumpDir $shaName
    $sourceLog = Join-Path $Script:LogDir $logName

    "dummy dump for sync test $token" | Set-Content -LiteralPath $sourceDump -Encoding ASCII
    $hash = Get-FileHash -LiteralPath $sourceDump -Algorithm SHA256
    "{0}  {1}" -f $hash.Hash.ToLowerInvariant(), $dumpName | Set-Content -LiteralPath $sourceSha -Encoding ASCII
    "dummy log for sync test $token" | Set-Content -LiteralPath $sourceLog -Encoding ASCII

    $createdPaths += $sourceDump
    $createdPaths += $sourceSha
    $createdPaths += $sourceLog

    Write-Log "Archivos dummy creados para prueba de sync." "OK"

    & (Join-Path $PSScriptRoot "sync-google-drive.ps1") -DestinationPath $destinationRoot

    $destDump = Join-Path (Join-Path $destinationRoot "dumps") $dumpName
    $destSha = Join-Path (Join-Path $destinationRoot "dumps") $shaName
    $destLog = Join-Path (Join-Path $destinationRoot "logs") $logName

    $createdPaths += $destDump
    $createdPaths += $destSha
    $createdPaths += $destLog

    foreach ($path in @($destDump, $destSha, $destLog)) {
        if (-not (Test-Path -LiteralPath $path)) {
            throw "No llego archivo dummy al destino: $path"
        }
        if ((Get-Item -LiteralPath $path).Length -le 0) {
            throw "Archivo dummy llego vacio al destino: $path"
        }
        Write-Log "Dummy sincronizado: $path" "OK"
    }

    Write-Log "TEST_SYNC_OK destino=$destinationRoot" "OK"
}
catch {
    Write-Log $_.Exception.Message "ERROR"
    throw
}
finally {
    foreach ($path in $createdPaths) {
        try {
            if ($path -and (Test-Path -LiteralPath $path) -and ((Split-Path -Leaf $path) -like "sync_test_*")) {
                Remove-Item -LiteralPath $path -Force
                Write-Log "Dummy eliminado: $path" "OK"
            }
        }
        catch {
            Write-Log "No se pudo eliminar dummy '$path': $($_.Exception.Message)" "WARN"
        }
    }
}

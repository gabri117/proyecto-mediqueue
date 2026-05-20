param(
    [string]$ConfigPath,
    [switch]$SkipDocker
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "backup-common.ps1")

Initialize-BackupConfiguration -ConfigPath $ConfigPath
Start-BackupLog -Name "test-backup-system"

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

Write-Log "Prueba no destructiva completada. No se ejecutaron backups ni restauraciones reales." "OK"

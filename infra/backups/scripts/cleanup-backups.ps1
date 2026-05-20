param(
    [string]$ConfigPath,
    [switch]$Apply,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "backup-common.ps1")

Initialize-BackupConfiguration -ConfigPath $ConfigPath
Start-BackupLog -Name "cleanup-backups"

if ($Apply -and $DryRun) {
    throw "Usa -Apply o -DryRun, no ambos."
}

$executeDelete = $Apply.IsPresent
if (-not $executeDelete) {
    Write-Log "Limpieza en modo simulacion. No se eliminara ningun archivo. Usa -Apply para borrar manualmente." "WARN"
}

function Remove-ExpiredFiles {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Filter,
        [Parameter(Mandatory = $true)][datetime]$OlderThan,
        [Parameter(Mandatory = $true)][string]$Label
    )

    Get-ChildItem -LiteralPath $Path -Filter $Filter -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne ".gitkeep" -and $_.LastWriteTime -lt $OlderThan } |
        ForEach-Object {
            if ($executeDelete) {
                Remove-Item -LiteralPath $_.FullName -Force
                Write-Log "Eliminado ($Label): $($_.FullName)" "OK"
            }
            else {
                Write-Log "Simulacion eliminaria ($Label): $($_.FullName)" "WARN"
            }
        }
}

Remove-ExpiredFiles -Path $Script:LocalBackupDir -Filter "mediqueue-base-*.tar.gz" -OlderThan (Get-Date).AddDays(-[int]$Script:BaseBackupRetentionDays) -Label "base"
Remove-ExpiredFiles -Path $Script:DumpDir -Filter "mediqueue-*.dump" -OlderThan (Get-Date).AddDays(-[int]$Script:DumpRetentionDays) -Label "dump"
Remove-ExpiredFiles -Path $Script:WalArchiveDir -Filter "*" -OlderThan (Get-Date).AddDays(-[int]$Script:WalRetentionDays) -Label "wal"
Remove-ExpiredFiles -Path $Script:LogDir -Filter "*.log" -OlderThan (Get-Date).AddDays(-[int]$Script:LogRetentionDays) -Label "logs"
Remove-ExpiredFiles -Path $Script:WeeklyDir -Filter "*.tar.gz" -OlderThan (Get-Date).AddDays(-7 * [int]$Script:WeeklyRetentionWeeks) -Label "weekly"
Remove-ExpiredFiles -Path $Script:MonthlyDir -Filter "*.tar.gz" -OlderThan (Get-Date).AddMonths(-[int]$Script:MonthlyRetentionMonths) -Label "monthly"

Write-Log "Limpieza finalizada. Modo real: $executeDelete" "OK"

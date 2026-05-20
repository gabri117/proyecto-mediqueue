param(
    [string]$ConfigPath,
    [switch]$DryRun,
    [switch]$ConfirmDelete
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "backup-common.ps1")

Initialize-BackupConfiguration -ConfigPath $ConfigPath
Start-BackupLog -Name "cleanup-incomplete-base-backups"

function Test-BaseBackupDirectory {
    param(
        [Parameter(Mandatory = $true)][System.IO.DirectoryInfo]$Directory
    )

    $baseTar = Join-Path $Directory.FullName "base.tar.gz"
    $walTar = Join-Path $Directory.FullName "pg_wal.tar.gz"
    $shaFile = Join-Path $Directory.FullName "SHA256SUMS"
    $markerFile = Join-Path $Directory.FullName "BACKUP_BASE_OK.txt"
    $reasons = New-Object System.Collections.Generic.List[string]

    if (-not (Test-Path -LiteralPath $baseTar)) {
        $reasons.Add("falta base.tar.gz")
    }
    elseif ((Get-Item -LiteralPath $baseTar).Length -le 0) {
        $reasons.Add("base.tar.gz esta vacio")
    }

    if (-not (Test-Path -LiteralPath $walTar)) {
        $reasons.Add("falta pg_wal.tar.gz")
    }
    elseif ((Get-Item -LiteralPath $walTar).Length -le 0) {
        $reasons.Add("pg_wal.tar.gz esta vacio")
    }

    if (-not (Test-Path -LiteralPath $shaFile)) {
        $reasons.Add("falta SHA256SUMS")
    }
    elseif ((Get-Item -LiteralPath $shaFile).Length -le 0) {
        $reasons.Add("SHA256SUMS esta vacio")
    }

    if (-not (Test-Path -LiteralPath $markerFile)) {
        $reasons.Add("falta BACKUP_BASE_OK.txt")
    }
    elseif ((Get-Item -LiteralPath $markerFile).Length -le 0) {
        $reasons.Add("BACKUP_BASE_OK.txt esta vacio")
    }

    return [pscustomobject]@{
        Directory = $Directory
        IsValid = ($reasons.Count -eq 0)
        Reasons = @($reasons)
    }
}

try {
    if ($ConfirmDelete -and $DryRun) {
        throw "No combines -DryRun con -ConfirmDelete."
    }

    $effectiveDryRun = -not $ConfirmDelete
    if ($effectiveDryRun) {
        Write-Log "Modo DryRun activo. No se eliminaran carpetas." "WARN"
    }

    $localRoot = (Resolve-Path -LiteralPath $Script:LocalBackupDir).Path
    $baseDirs = @(Get-ChildItem -LiteralPath $Script:LocalBackupDir -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "mediqueue_base_*" } |
        Sort-Object LastWriteTime -Descending)

    if ($baseDirs.Count -eq 0) {
        Write-Log "No se encontraron carpetas mediqueue_base_* en $Script:LocalBackupDir" "OK"
        return
    }

    $checks = @($baseDirs | ForEach-Object { Test-BaseBackupDirectory -Directory $_ })
    $incomplete = @($checks | Where-Object { -not $_.IsValid })
    $validCount = @($checks | Where-Object { $_.IsValid }).Count

    Write-Log "BACKUP_BASE_VALID_COUNT=$validCount"
    Write-Log "BACKUP_BASE_INCOMPLETE_COUNT=$($incomplete.Count)"

    if ($incomplete.Count -eq 0) {
        Write-Log "No hay backups base incompletos." "OK"
        return
    }

    foreach ($entry in $incomplete) {
        $target = (Resolve-Path -LiteralPath $entry.Directory.FullName).Path
        if (-not $target.StartsWith($localRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Ruta fuera de infra/backups/local bloqueada: $target"
        }

        Write-Log ("INCOMPLETE_BASE_BACKUP path={0} reasons={1}" -f $target, ($entry.Reasons -join "; ")) "WARN"

        if ($effectiveDryRun) {
            Write-Log "DRY_RUN would_delete=$target" "WARN"
            continue
        }

        Remove-Item -LiteralPath $target -Recurse -Force
        Write-Log "DELETED_INCOMPLETE_BASE_BACKUP $target" "OK"
    }
}
catch {
    Write-Log $_.Exception.Message "ERROR"
    throw
}

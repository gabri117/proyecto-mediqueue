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

$Script:OverallStatus = "OK"

function Set-OverallStatus {
    param([ValidateSet("OK", "WARNING", "ERROR")][string]$Status)

    if ($Status -eq "ERROR") {
        $Script:OverallStatus = "ERROR"
        return
    }

    if ($Status -eq "WARNING" -and $Script:OverallStatus -eq "OK") {
        $Script:OverallStatus = "WARNING"
    }
}

function Write-Check {
    param(
        [Parameter(Mandatory = $true)][string]$Code,
        [ValidateSet("OK", "WARNING", "ERROR")][string]$Status,
        [Parameter(Mandatory = $true)][string]$Message
    )

    Set-OverallStatus -Status $Status
    $level = if ($Status -eq "OK") { "OK" } elseif ($Status -eq "WARNING") { "WARN" } else { "ERROR" }
    Write-Log "$Code $Message" $level
}

function Test-DumpChecksum {
    param(
        [Parameter(Mandatory = $true)][System.IO.FileInfo]$Dump
    )

    $checksumPath = "$($Dump.FullName).sha256"
    if (-not (Test-Path -LiteralPath $checksumPath)) {
        Write-Check -Code "CHECKSUM_WARNING" -Status "WARNING" -Message "Falta checksum para $($Dump.FullName)"
        return
    }

    $checksumInfo = Get-Item -LiteralPath $checksumPath
    if ($checksumInfo.Length -le 0) {
        Write-Check -Code "CHECKSUM_WARNING" -Status "WARNING" -Message "Checksum vacio: $checksumPath"
        return
    }

    $checksumLine = (Get-Content -LiteralPath $checksumPath -TotalCount 1).Trim()
    $expectedHash = ($checksumLine -split "\s+")[0].ToLowerInvariant()
    $actualHash = (Get-FileHash -LiteralPath $Dump.FullName -Algorithm SHA256).Hash.ToLowerInvariant()

    if ($expectedHash -eq $actualHash) {
        Write-Check -Code "CHECKSUM_OK" -Status "OK" -Message "$checksumPath"
    }
    else {
        Write-Check -Code "DUMP_ERROR" -Status "ERROR" -Message "Checksum no coincide para $($Dump.FullName)"
    }
}

try {
    Assert-DockerAvailable
    Assert-ComposeConfigValid
    Assert-PostgresAvailable
}
catch {
    Write-Check -Code "STATUS=ERROR" -Status "ERROR" -Message "No se pudo validar Docker/PostgreSQL: $($_.Exception.Message)"
    throw
}

$now = Get-Date

try {
    $baseBackup = Get-ChildItem -LiteralPath $Script:LocalBackupDir -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "mediqueue_base_*" } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if (-not $baseBackup) {
        Write-Check -Code "BASE_ERROR" -Status "ERROR" -Message "No se encontro backup base en $Script:LocalBackupDir"
    }
    elseif ((($now - $baseBackup.LastWriteTime).TotalHours) -gt $MaxBaseAgeHours) {
        Write-Check -Code "BASE_ERROR" -Status "ERROR" -Message "Backup base fuera de ventana: $($baseBackup.FullName)"
    }
    else {
        $baseBackupFiles = @(Get-ChildItem -LiteralPath $baseBackup.FullName -File -Recurse -ErrorAction Stop)
        $hasOkMarker = Test-Path -LiteralPath (Join-Path $baseBackup.FullName "BASE_BACKUP_OK")
        $hasSha = Test-Path -LiteralPath (Join-Path $baseBackup.FullName "SHA256SUMS")

        if ($baseBackupFiles.Count -eq 0 -or -not $hasOkMarker -or -not $hasSha) {
            Write-Check -Code "BASE_ERROR" -Status "ERROR" -Message "Backup base incompleto: $($baseBackup.FullName)"
        }
        else {
            Write-Check -Code "BASE_OK" -Status "OK" -Message "$($baseBackup.FullName)"
        }
    }
}
catch {
    Write-Check -Code "BASE_ERROR" -Status "ERROR" -Message $_.Exception.Message
}

$dump = $null
try {
    $dump = Get-LatestFile -Path $Script:DumpDir -Filter "mediqueue_dump_*.dump"
    if (-not $dump) {
        Write-Check -Code "DUMP_ERROR" -Status "ERROR" -Message "No se encontro pg_dump en $Script:DumpDir"
    }
    elseif ($dump.Length -le 0) {
        Write-Check -Code "DUMP_ERROR" -Status "ERROR" -Message "Dump vacio: $($dump.FullName)"
    }
    elseif ((($now - $dump.LastWriteTime).TotalHours) -gt $MaxDumpAgeHours) {
        Write-Check -Code "DUMP_ERROR" -Status "ERROR" -Message "Dump fuera de ventana: $($dump.FullName)"
    }
    else {
        Write-Check -Code "DUMP_OK" -Status "OK" -Message "$($dump.FullName)"
        Test-DumpChecksum -Dump $dump
    }
}
catch {
    Write-Check -Code "DUMP_ERROR" -Status "ERROR" -Message $_.Exception.Message
}

try {
    $wal = Get-ChildItem -LiteralPath $Script:WalArchiveDir -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^[0-9A-F]{24}(\.partial)?$' } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if (-not $wal) {
        Write-Check -Code "WAL_ERROR" -Status "ERROR" -Message "No se encontraron WAL en $Script:WalArchiveDir"
    }
    else {
        $walAgeMinutes = (($now - $wal.LastWriteTime).TotalMinutes)
        if ($walAgeMinutes -le $MaxWalAgeMinutes) {
            Write-Check -Code "WAL_OK" -Status "OK" -Message ("{0}, edad {1:N1} minutos" -f $wal.FullName, $walAgeMinutes)
        }
        else {
            Write-Check -Code "WAL_WARNING" -Status "WARNING" -Message ("WAL existe pero excede {0} minutos: {1}, edad {2:N1}" -f $MaxWalAgeMinutes, $wal.FullName, $walAgeMinutes)
        }
    }
}
catch {
    Write-Check -Code "WAL_ERROR" -Status "ERROR" -Message $_.Exception.Message
}

try {
    if (-not $Script:ConfigLoaded -or [string]::IsNullOrWhiteSpace($Script:GoogleDriveBackupPath)) {
        Write-Check -Code "DRIVE_SYNC_WARNING" -Status "WARNING" -Message "Google Drive no esta configurado en backup.local.ps1"
    }
    elseif (-not (Test-Path -LiteralPath $Script:GoogleDriveBackupPathFull)) {
        Write-Check -Code "DRIVE_SYNC_ERROR" -Status "ERROR" -Message "Ruta configurada no existe: $Script:GoogleDriveBackupPathFull"
    }
    else {
        $driveFiles = @(Get-ChildItem -LiteralPath $Script:GoogleDriveBackupPathFull -File -Recurse -ErrorAction SilentlyContinue)
        if ($driveFiles.Count -eq 0) {
            Write-Check -Code "DRIVE_SYNC_WARNING" -Status "WARNING" -Message "Ruta de Google Drive existe pero esta vacia: $Script:GoogleDriveBackupPathFull"
        }
        elseif ($dump -and -not (Get-ChildItem -LiteralPath $Script:GoogleDriveBackupPathFull -Filter $dump.Name -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1)) {
            Write-Check -Code "DRIVE_SYNC_WARNING" -Status "WARNING" -Message "Google Drive tiene archivos, pero no se encontro el ultimo dump: $($dump.Name)"
        }
        else {
            Write-Check -Code "DRIVE_SYNC_OK" -Status "OK" -Message "$Script:GoogleDriveBackupPathFull"
        }
    }
}
catch {
    Write-Check -Code "DRIVE_SYNC_ERROR" -Status "ERROR" -Message $_.Exception.Message
}

$finalLogLevel = if ($Script:OverallStatus -eq "OK") { "OK" } elseif ($Script:OverallStatus -eq "WARNING") { "WARN" } else { "ERROR" }
Write-Log "STATUS=$Script:OverallStatus" $finalLogLevel

if ($Script:OverallStatus -eq "ERROR") {
    throw "Verificacion de backups termino con STATUS=ERROR"
}

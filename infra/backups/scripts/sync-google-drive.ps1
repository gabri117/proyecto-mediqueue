param(
    [string]$ConfigPath,
    [string]$DestinationPath,
    [switch]$VerifyOnly,
    [switch]$OpenDestination,
    [int]$MaxWalAgeMinutes = 10
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "backup-common.ps1")

Initialize-BackupConfiguration -ConfigPath $ConfigPath
Start-BackupLog -Name "sync-google-drive"
$Script:SyncHadWarning = $false

function Get-RelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$BasePath,
        [Parameter(Mandatory = $true)][string]$FullPath
    )

    return $FullPath.Substring($BasePath.Length).TrimStart([char[]]@("\", "/"))
}

function Get-BackupFileSet {
    param(
        [Parameter(Mandatory = $true)][array]$Roots,
        [string]$RootPrefix = "",
        [string]$ExcludePath
    )

    $files = @()
    foreach ($root in $Roots) {
        if (-not (Test-Path -LiteralPath $root.Path)) {
            continue
        }

        $rootFiles = Get-ChildItem -LiteralPath $root.Path -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -ne ".gitkeep" -and
                ([string]::IsNullOrWhiteSpace($ExcludePath) -or $_.FullName -ne $ExcludePath)
            }

        foreach ($file in $rootFiles) {
            $relative = Get-RelativePath -BasePath $root.Path -FullPath $file.FullName
            $files += [pscustomobject]@{
                SourceRoot = $root.Name
                FullName = $file.FullName
                RelativePath = (Join-Path $root.Name $relative)
                Length = $file.Length
                LastWriteTime = $file.LastWriteTime
            }
        }
    }

    return @($files)
}

function Get-TotalBytes {
    param([array]$Files)

    if (-not $Files -or $Files.Count -eq 0) {
        return 0
    }

    return ($Files | Measure-Object -Property Length -Sum).Sum
}

function Assert-CopiedFiles {
    param(
        [Parameter(Mandatory = $true)][array]$SourceFiles,
        [Parameter(Mandatory = $true)][string]$DestinationRoot
    )

    foreach ($sourceFile in $SourceFiles) {
        $destPath = Join-Path $DestinationRoot $sourceFile.RelativePath
        if (-not (Test-Path -LiteralPath $destPath)) {
            throw "No se encontro archivo destino para '$($sourceFile.RelativePath)': $destPath"
        }

        $destItem = Get-Item -LiteralPath $destPath
        if ($destItem.Length -ne $sourceFile.Length) {
            throw "Tamano distinto para '$($sourceFile.RelativePath)'. Fuente=$($sourceFile.Length), destino=$($destItem.Length)"
        }

        $sourceHash = (Get-FileHash -LiteralPath $sourceFile.FullName -Algorithm SHA256).Hash
        $destHash = (Get-FileHash -LiteralPath $destPath -Algorithm SHA256).Hash
        if ($sourceHash -ne $destHash) {
            throw "Hash SHA256 distinto para '$($sourceFile.RelativePath)'"
        }
    }
}

function Write-InventoryStatus {
    param(
        [Parameter(Mandatory = $true)][array]$DestinationFiles,
        [Parameter(Mandatory = $true)][string]$DestinationRoot
    )

    $dumpFiles = @($DestinationFiles | Where-Object { $_.RelativePath -like "dumps\*.dump" })
    $checksumFiles = @($DestinationFiles | Where-Object { $_.RelativePath -like "dumps\*.dump.sha256" -or $_.RelativePath -like "dumps\*.sha256" })
    $baseMarkers = @(Get-ChildItem -LiteralPath (Join-Path $DestinationRoot "local") -Filter "BASE_BACKUP_OK" -File -Recurse -ErrorAction SilentlyContinue)
    $walFiles = @(Get-ChildItem -LiteralPath (Join-Path $DestinationRoot "wal-archive") -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^[0-9A-F]{24}(\.partial)?$' } |
        Sort-Object LastWriteTime -Descending)

    if ($dumpFiles.Count -eq 0) {
        $Script:SyncHadWarning = $true
        Write-Log "DUMP_WARNING No se encontro ningun .dump en destino." "WARN"
    }
    else {
        Write-Log "DUMP_OK dumps=$($dumpFiles.Count)" "OK"
    }

    if ($checksumFiles.Count -eq 0) {
        $Script:SyncHadWarning = $true
        Write-Log "CHECKSUM_WARNING No se encontro ningun .sha256 en destino." "WARN"
    }
    else {
        Write-Log "CHECKSUM_OK sha256=$($checksumFiles.Count)" "OK"
    }

    if ($baseMarkers.Count -eq 0) {
        $Script:SyncHadWarning = $true
        Write-Log "BASE_WARNING No se encontro backup base con BASE_BACKUP_OK en destino/local." "WARN"
    }
    else {
        Write-Log "BASE_OK base_backups=$($baseMarkers.Count)" "OK"
    }

    if ($walFiles.Count -eq 0) {
        $Script:SyncHadWarning = $true
        Write-Log "WAL_WARNING No se encontraron WAL archivados en destino/wal-archive." "WARN"
    }
    else {
        $latestWal = $walFiles | Select-Object -First 1
        $ageMinutes = ((Get-Date) - $latestWal.LastWriteTime).TotalMinutes
        if ($ageMinutes -le $MaxWalAgeMinutes) {
            Write-Log ("WAL_OK latest={0}, age_minutes={1:N1}" -f $latestWal.Name, $ageMinutes) "OK"
        }
        else {
            $Script:SyncHadWarning = $true
            Write-Log ("WAL_WARNING WAL mas reciente excede {0} minutos: {1}, age_minutes={2:N1}" -f $MaxWalAgeMinutes, $latestWal.Name, $ageMinutes) "WARN"
        }
    }
}

try {
    if ([string]::IsNullOrWhiteSpace($DestinationPath)) {
        if (-not $Script:ConfigLoaded) {
            throw "No se encontro backup.local.ps1. Crea infra/backups/config/backup.local.ps1 o pasa -DestinationPath."
        }
        if ([string]::IsNullOrWhiteSpace($Script:GoogleDriveBackupPath)) {
            throw "GoogleDriveBackupPath no esta configurado en backup.local.ps1."
        }
        $DestinationPath = $Script:GoogleDriveBackupPath
    }

    $destinationRoot = Resolve-BackupPath -Path $DestinationPath -BasePath $Script:RepoRoot -MustExist:$false
    New-Item -ItemType Directory -Force -Path $destinationRoot | Out-Null

    $sourceRoots = @(
        @{ Name = "dumps"; Path = $Script:DumpDir },
        @{ Name = "local"; Path = $Script:LocalBackupDir },
        @{ Name = "wal-archive"; Path = $Script:WalArchiveDir },
        @{ Name = "logs"; Path = $Script:LogDir }
    )

    foreach ($root in $sourceRoots) {
        New-Item -ItemType Directory -Force -Path (Join-Path $destinationRoot $root.Name) | Out-Null
    }

    $sourceFiles = Get-BackupFileSet -Roots $sourceRoots -ExcludePath $Script:CurrentLogFile
    $copiedFiles = @()

    if (-not $VerifyOnly) {
        foreach ($sourceFile in $sourceFiles) {
            $destPath = Join-Path $destinationRoot $sourceFile.RelativePath
            $destDir = Split-Path -Parent $destPath
            New-Item -ItemType Directory -Force -Path $destDir | Out-Null
            Copy-Item -LiteralPath $sourceFile.FullName -Destination $destPath -Force
            $copiedFiles += [pscustomobject]@{
                RelativePath = $sourceFile.RelativePath
                FullName = $destPath
                Length = (Get-Item -LiteralPath $destPath).Length
                LastWriteTime = (Get-Item -LiteralPath $destPath).LastWriteTime
            }
        }
    }
    else {
        Write-Log "VerifyOnly activo: no se copiaran archivos." "WARN"
    }

    $destinationRoots = @(
        @{ Name = "dumps"; Path = (Join-Path $destinationRoot "dumps") },
        @{ Name = "local"; Path = (Join-Path $destinationRoot "local") },
        @{ Name = "wal-archive"; Path = (Join-Path $destinationRoot "wal-archive") },
        @{ Name = "logs"; Path = (Join-Path $destinationRoot "logs") }
    )
    $destinationFiles = Get-BackupFileSet -Roots $destinationRoots

    $sourceCount = $sourceFiles.Count
    $destCount = $destinationFiles.Count
    $sourceBytes = Get-TotalBytes -Files $sourceFiles
    $destBytes = Get-TotalBytes -Files $destinationFiles

    Write-Log "SOURCE_COUNT=$sourceCount"
    Write-Log "DEST_COUNT=$destCount"
    Write-Log "SOURCE_BYTES=$sourceBytes"
    Write-Log "DEST_BYTES=$destBytes"

    if ($destCount -eq 0 -or $destBytes -eq 0) {
        throw "El destino quedo vacio despues de la sincronizacion: $destinationRoot"
    }

    if (-not $VerifyOnly) {
        Assert-CopiedFiles -SourceFiles $sourceFiles -DestinationRoot $destinationRoot
        Write-Log "FILE_BY_FILE_VERIFY_OK archivos_verificados=$($sourceFiles.Count)" "OK"
    }

    Write-InventoryStatus -DestinationFiles $destinationFiles -DestinationRoot $destinationRoot

    $lastFiles = if ($copiedFiles.Count -gt 0) {
        $copiedFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 10
    }
    else {
        $destinationFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 10
    }

    Write-Log "LAST_COPIED_FILES"
    foreach ($file in $lastFiles) {
        Write-Log ("  {0} | {1} bytes | {2}" -f $file.RelativePath, $file.Length, $file.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss"))
    }

    if ($OpenDestination) {
        Start-Process -FilePath "explorer.exe" -ArgumentList "`"$destinationRoot`""
    }

    if ($Script:SyncHadWarning) {
        Write-Log "SYNC_WARNING destino=$destinationRoot" "WARN"
    }
    else {
        Write-Log "SYNC_OK destino=$destinationRoot" "OK"
    }
}
catch {
    Write-Log $_.Exception.Message "ERROR"
    throw
}

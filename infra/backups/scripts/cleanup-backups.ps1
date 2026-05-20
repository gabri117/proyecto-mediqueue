param(
    [string]$ConfigPath,
    [switch]$DryRun,
    [switch]$ConfirmDelete,
    [switch]$IncludeGoogleDrive
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "backup-common.ps1")

Initialize-BackupConfiguration -ConfigPath $ConfigPath
Start-BackupLog -Name "cleanup-backups"

$today = (Get-Date).Date
$deleteEnabled = $ConfirmDelete.IsPresent
if (-not $deleteEnabled) {
    Write-Log "Modo DryRun activo por defecto. No se eliminara ningun archivo sin -ConfirmDelete." "WARN"
}
if ($DryRun -and $ConfirmDelete) {
    throw "Usa -DryRun o -ConfirmDelete, no ambos."
}
if ($IncludeGoogleDrive -and -not $ConfirmDelete) {
    throw "Para limpiar Google Drive debes pasar tambien -ConfirmDelete."
}

function Get-ItemAgeDescription {
    param([Parameter(Mandatory = $true)][datetime]$LastWriteTime)

    $age = (Get-Date) - $LastWriteTime
    if ($age.TotalDays -ge 1) {
        return "{0:N1} days" -f $age.TotalDays
    }
    return "{0:N1} hours" -f $age.TotalHours
}

function Test-IsToday {
    param([Parameter(Mandatory = $true)][datetime]$LastWriteTime)

    return $LastWriteTime.Date -eq $today
}

function New-CleanupCandidate {
    param(
        [Parameter(Mandatory = $true)][System.IO.FileSystemInfo]$Item,
        [Parameter(Mandatory = $true)][string]$Category,
        [Parameter(Mandatory = $true)][datetime]$OlderThan,
        [Parameter(Mandatory = $true)][string]$Reason
    )

    if ($Item.Name -eq ".gitkeep") {
        return $null
    }
    if (Test-IsToday -LastWriteTime $Item.LastWriteTime) {
        return $null
    }
    if ($Item.LastWriteTime -ge $OlderThan) {
        return $null
    }

    return [pscustomobject]@{
        Path = $Item.FullName
        Category = $Category
        Reason = $Reason
        Age = Get-ItemAgeDescription -LastWriteTime $Item.LastWriteTime
        LastWriteTime = $Item.LastWriteTime
        IsDirectory = ($Item.PSIsContainer -eq $true)
    }
}

function Add-ExpiredFiles {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Candidates,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Filter,
        [Parameter(Mandatory = $true)][datetime]$OlderThan,
        [Parameter(Mandatory = $true)][string]$Category,
        [Parameter(Mandatory = $true)][string]$Reason
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    Get-ChildItem -LiteralPath $Path -Filter $Filter -File -Recurse -ErrorAction SilentlyContinue |
        ForEach-Object {
            $candidate = New-CleanupCandidate -Item $_ -Category $Category -OlderThan $OlderThan -Reason $Reason
            if ($candidate) {
                $Candidates.Add($candidate) | Out-Null
            }
        }
}

function Add-ExpiredDirectories {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Candidates,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Filter,
        [Parameter(Mandatory = $true)][datetime]$OlderThan,
        [Parameter(Mandatory = $true)][string]$Category,
        [Parameter(Mandatory = $true)][string]$Reason
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    Get-ChildItem -LiteralPath $Path -Directory -Filter $Filter -ErrorAction SilentlyContinue |
        ForEach-Object {
            $candidate = New-CleanupCandidate -Item $_ -Category $Category -OlderThan $OlderThan -Reason $Reason
            if ($candidate) {
                $Candidates.Add($candidate) | Out-Null
            }
        }
}

function Write-CleanupCandidate {
    param([Parameter(Mandatory = $true)]$Candidate)

    Write-Log ("CLEANUP_CANDIDATE file=""{0}"" age=""{1}"" category=""{2}"" reason=""{3}""" -f $Candidate.Path, $Candidate.Age, $Candidate.Category, $Candidate.Reason) "WARN"
}

$candidates = [System.Collections.Generic.List[object]]::new()
$now = Get-Date

Add-ExpiredDirectories -Candidates $candidates -Path $Script:LocalBackupDir -Filter "mediqueue_base_*" -OlderThan $now.AddDays(-14) -Category "base" -Reason "base backup older than 14 days"
Add-ExpiredDirectories -Candidates $candidates -Path $Script:LocalBackupDir -Filter "wal_archive_snapshot_*" -OlderThan $now.AddDays(-14) -Category "wal-snapshot" -Reason "WAL snapshot older than 14 days"
Add-ExpiredFiles -Candidates $candidates -Path $Script:DumpDir -Filter "mediqueue_dump_*.dump" -OlderThan $now.AddDays(-30) -Category "pg_dump" -Reason "pg_dump older than 30 days"
Add-ExpiredFiles -Candidates $candidates -Path $Script:DumpDir -Filter "mediqueue_dump_*.dump.sha256" -OlderThan $now.AddDays(-30) -Category "pg_dump-checksum" -Reason "pg_dump checksum older than 30 days"
Add-ExpiredFiles -Candidates $candidates -Path $Script:WalArchiveDir -Filter "*" -OlderThan $now.AddDays(-14) -Category "wal" -Reason "WAL older than 14 days"
Add-ExpiredFiles -Candidates $candidates -Path $Script:LogDir -Filter "*.log" -OlderThan $now.AddDays(-30) -Category "logs" -Reason "log older than 30 days"
Add-ExpiredFiles -Candidates $candidates -Path $Script:WeeklyDir -Filter "*" -OlderThan $now.AddDays(-56) -Category "weekly" -Reason "weekly backup older than 8 weeks"
Add-ExpiredDirectories -Candidates $candidates -Path $Script:WeeklyDir -Filter "*" -OlderThan $now.AddDays(-56) -Category "weekly" -Reason "weekly backup directory older than 8 weeks"
Add-ExpiredFiles -Candidates $candidates -Path $Script:MonthlyDir -Filter "*" -OlderThan $now.AddMonths(-12) -Category "monthly" -Reason "monthly backup older than 12 months"
Add-ExpiredDirectories -Candidates $candidates -Path $Script:MonthlyDir -Filter "*" -OlderThan $now.AddMonths(-12) -Category "monthly" -Reason "monthly backup directory older than 12 months"

if ($IncludeGoogleDrive) {
    if (-not $Script:ConfigLoaded -or [string]::IsNullOrWhiteSpace($Script:GoogleDriveBackupPath)) {
        throw "No se puede limpiar Google Drive sin GoogleDriveBackupPath en backup.local.ps1."
    }
    if (-not (Test-Path -LiteralPath $Script:GoogleDriveBackupPathFull)) {
        throw "GoogleDriveBackupPath no existe: $Script:GoogleDriveBackupPathFull"
    }

    Add-ExpiredDirectories -Candidates $candidates -Path (Join-Path $Script:GoogleDriveBackupPathFull "local") -Filter "mediqueue_base_*" -OlderThan $now.AddDays(-14) -Category "drive-base" -Reason "Drive base backup older than 14 days"
    Add-ExpiredFiles -Candidates $candidates -Path (Join-Path $Script:GoogleDriveBackupPathFull "dumps") -Filter "mediqueue_dump_*.dump" -OlderThan $now.AddDays(-30) -Category "drive-pg_dump" -Reason "Drive pg_dump older than 30 days"
    Add-ExpiredFiles -Candidates $candidates -Path (Join-Path $Script:GoogleDriveBackupPathFull "dumps") -Filter "mediqueue_dump_*.dump.sha256" -OlderThan $now.AddDays(-30) -Category "drive-pg_dump-checksum" -Reason "Drive pg_dump checksum older than 30 days"
    Add-ExpiredFiles -Candidates $candidates -Path (Join-Path $Script:GoogleDriveBackupPathFull "wal-archive") -Filter "*" -OlderThan $now.AddDays(-14) -Category "drive-wal" -Reason "Drive WAL older than 14 days"
    Add-ExpiredFiles -Candidates $candidates -Path (Join-Path $Script:GoogleDriveBackupPathFull "logs") -Filter "*.log" -OlderThan $now.AddDays(-30) -Category "drive-logs" -Reason "Drive log older than 30 days"
}

if ($candidates.Count -eq 0) {
    Write-Log "CLEANUP_NOTHING_TO_DELETE" "OK"
    return
}

foreach ($candidate in ($candidates | Sort-Object Category, LastWriteTime)) {
    Write-CleanupCandidate -Candidate $candidate
}

Write-Log "CLEANUP_CANDIDATE_COUNT=$($candidates.Count)" "WARN"

if (-not $deleteEnabled) {
    Write-Log "CLEANUP_DRY_RUN completed. No se elimino nada." "WARN"
    return
}

foreach ($candidate in ($candidates | Sort-Object IsDirectory)) {
    if ($candidate.IsDirectory) {
        Remove-Item -LiteralPath $candidate.Path -Recurse -Force
    }
    else {
        Remove-Item -LiteralPath $candidate.Path -Force
    }
    Write-Log ("CLEANUP_DELETED file=""{0}"" age=""{1}"" category=""{2}"" reason=""{3}""" -f $candidate.Path, $candidate.Age, $candidate.Category, $candidate.Reason) "OK"
}

Write-Log "CLEANUP_DELETE_OK deleted=$($candidates.Count)" "OK"

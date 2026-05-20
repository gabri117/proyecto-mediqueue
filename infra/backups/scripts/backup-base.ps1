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
$statusFile = Join-Path $localDir "BACKUP_BASE_OK.txt"
$failedStatusFile = Join-Path $localDir "BACKUP_BASE_FAILED.txt"
$shaFile = Join-Path $localDir "SHA256SUMS"

function ConvertTo-ProcessArgumentString {
    param([string[]]$Arguments)

    return (($Arguments | ForEach-Object {
        if ($null -eq $_) {
            '""'
        }
        elseif ($_ -match '[\s"]') {
            '"' + ($_.Replace('"', '\"')) + '"'
        }
        else {
            $_
        }
    }) -join " ")
}

function Invoke-CapturedProcess {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    Write-Log ("Ejecutando: {0} {1}" -f $FilePath, ($Arguments -join " "))

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $FilePath
    $startInfo.WorkingDirectory = $Script:RepoRoot
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.Arguments = ConvertTo-ProcessArgumentString -Arguments $Arguments

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    [void]$process.Start()

    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()

    $stdout = $stdoutTask.GetAwaiter().GetResult()
    $stderr = $stderrTask.GetAwaiter().GetResult()

    if (-not [string]::IsNullOrWhiteSpace($stdout)) {
        foreach ($line in ($stdout -split "\r?\n")) {
            if (-not [string]::IsNullOrWhiteSpace($line)) {
                Write-Log "[stdout] $line"
            }
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($stderr)) {
        foreach ($line in ($stderr -split "\r?\n")) {
            if (-not [string]::IsNullOrWhiteSpace($line)) {
                Write-Log "[stderr] $line"
            }
        }
    }

    return [pscustomobject]@{
        ExitCode = $process.ExitCode
        Stdout = $stdout
        Stderr = $stderr
    }
}

try {
    if (Test-Path -LiteralPath $localDir) {
        throw "El directorio de backup ya existe: $localDir"
    }

    $backupCommand = @(
        "rm -rf '$remoteDir'",
        "mkdir -p '$remoteDir'",
        "pg_basebackup -U '$Script:DatabaseUser' -D '$remoteDir' -Ft -z -X stream -c fast -P"
    ) -join " && "

    $result = Invoke-CapturedProcess -FilePath "docker" -Arguments @(
        "compose", "-f", $Script:DockerComposeFileFull,
        "exec", "-T", $Script:PostgresService,
        "sh", "-lc", $backupCommand
    )

    if ($result.ExitCode -ne 0) {
        throw "El backup fisico/base fallo. Exit code: $($result.ExitCode)"
    }

    if (-not (Test-Path -LiteralPath $localDir)) {
        throw "El backup base no existe en el host: $localDir"
    }

    $baseTar = Join-Path $localDir "base.tar.gz"
    $walTar = Join-Path $localDir "pg_wal.tar.gz"

    if (-not (Test-Path -LiteralPath $baseTar)) {
        throw "Falta base.tar.gz en el backup base: $localDir"
    }

    if (-not (Test-Path -LiteralPath $walTar)) {
        throw "Falta pg_wal.tar.gz en el backup base: $localDir"
    }

    $baseTarInfo = Get-Item -LiteralPath $baseTar
    $walTarInfo = Get-Item -LiteralPath $walTar

    if ($baseTarInfo.Length -le 0) {
        throw "base.tar.gz esta vacio: $baseTar"
    }

    if ($walTarInfo.Length -le 0) {
        throw "pg_wal.tar.gz esta vacio: $walTar"
    }

    $files = @($baseTarInfo, $walTarInfo)
    $totalBytes = ($files | Measure-Object -Property Length -Sum).Sum

    $checksumLines = foreach ($file in $files) {
        $hash = Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256
        "{0}  {1}" -f $hash.Hash.ToLowerInvariant(), $file.Name
    }
    $checksumLines | Set-Content -LiteralPath $shaFile -Encoding ASCII

    if (-not (Test-Path -LiteralPath $shaFile) -or ((Get-Item -LiteralPath $shaFile).Length -le 0)) {
        throw "No se pudo generar SHA256SUMS para $localDir"
    }

    @(
        "BASE_BACKUP_OK"
        "created_at=$(Get-Date -Format "yyyy-MM-dd HH:mm:ss")"
        "database=$Script:DatabaseName"
        "database_user=$Script:DatabaseUser"
        "postgres_service=$Script:PostgresService"
        "backup_name=$baseName"
        "total_bytes=$totalBytes"
        "base_tar_gz_bytes=$($baseTarInfo.Length)"
        "pg_wal_tar_gz_bytes=$($walTarInfo.Length)"
        "checksums_file=SHA256SUMS"
        "checksums:"
    ) + $checksumLines | Set-Content -LiteralPath $statusFile -Encoding ASCII

    Write-Log "CHECKSUM_OK $shaFile" "OK"
    Write-Log "BASE_BACKUP_OK $localDir (base.tar.gz=$($baseTarInfo.Length) bytes, pg_wal.tar.gz=$($walTarInfo.Length) bytes, total=$totalBytes bytes)" "OK"
}
catch {
    Write-Log $_.Exception.Message "ERROR"
    if (Test-Path -LiteralPath $localDir) {
        try {
            @(
                "BASE_BACKUP_FAILED"
                "failed_at=$(Get-Date -Format "yyyy-MM-dd HH:mm:ss")"
                "backup_name=$baseName"
                "reason=$($_.Exception.Message)"
            ) | Set-Content -LiteralPath $failedStatusFile -Encoding ASCII
            Write-Log "Backup base incompleto marcado como failed: $failedStatusFile" "WARN"
        }
        catch {
            Write-Log "No se pudo marcar backup incompleto como failed: $($_.Exception.Message)" "WARN"
        }
    }
    throw
}

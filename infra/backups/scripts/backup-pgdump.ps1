param(
    [string]$PostgresService = $env:MEDIQUEUE_BACKUP_POSTGRES_SERVICE,
    [string]$DatabaseName = $env:MEDIQUEUE_BACKUP_DB_NAME,
    [string]$DatabaseUser = $env:MEDIQUEUE_BACKUP_DB_USER,
    [string]$BackupRoot = $env:MEDIQUEUE_BACKUP_ROOT,
    [string]$GoogleDrivePath = $env:MEDIQUEUE_BACKUP_GOOGLE_DRIVE_PATH,
    [string]$GpgRecipient = $env:MEDIQUEUE_BACKUP_GPG_RECIPIENT,
    [string]$GpgPassphrase = $env:MEDIQUEUE_BACKUP_GPG_PASSPHRASE
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\backup-common.ps1"
$cfg = Get-MediQueueBackupConfig
if (-not $PostgresService) { $PostgresService = $cfg.PostgresService }
if (-not $DatabaseName) { $DatabaseName = $cfg.DatabaseName }
if (-not $DatabaseUser) { $DatabaseUser = $cfg.DatabaseUser }
if (-not $BackupRoot) { $BackupRoot = $cfg.BackupRoot }
if (-not $GoogleDrivePath) { $GoogleDrivePath = $cfg.GoogleDriveBackupPath }
$BackupMode = $cfg.BackupMode

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logDir = Join-Path $BackupRoot "logs"
$dumpDir = Join-Path $BackupRoot "dumps"
New-Item -ItemType Directory -Force -Path $logDir, $dumpDir | Out-Null
$logFile = Join-Path $logDir "backup-pgdump-$stamp.log"

function Write-Log {
    param([string]$Message)
    $line = "$(Get-Date -Format o) $Message"
    Write-Host $line
    Add-Content -Path $logFile -Value $line -Encoding utf8
}

function Invoke-Checked {
    param([string]$Label, [scriptblock]$Block)
    Write-Log "START $Label"
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        & $Block 2>&1 | Tee-Object -FilePath $logFile -Append
        $code = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    Write-Log "EXIT $Label code=$code"
    if ($null -ne $code -and $code -ne 0) {
        throw "$Label fallo con exit code $code"
    }
}

try {
    Write-Log "BACKUP_MODE=$BackupMode"
    Invoke-Checked "docker info" { docker info }
    if ($BackupMode -eq "patroni") {
        Invoke-Checked "docker compose patroni ps" { docker compose -f docker-compose.yml -f docker-compose.patroni.yml ps }
    } else {
        Invoke-Checked "docker compose ps" { docker compose ps }
    }

    $containerDump = "/tmp/mediqueue_dump_$stamp.dump"
    $localDump = Join-Path $dumpDir "mediqueue_dump_$stamp.dump"

    if ($BackupMode -eq "patroni") {
        $patroniRunnerService = "$($cfg.PatroniDockerServicePrefix)-1"
        $writerRecovery = docker compose -f docker-compose.yml -f docker-compose.patroni.yml exec -T -e "PGPASSWORD=$($cfg.PatroniAdminPassword)" $patroniRunnerService `
            psql -h patroni-postgres-lb -p 5432 -U $($cfg.PatroniAdminUser) -d $DatabaseName -At -v ON_ERROR_STOP=1 -c "SELECT pg_is_in_recovery();"
        if ($LASTEXITCODE -ne 0) {
            throw "No se pudo validar Patroni writer."
        }
        $writerRecovery = ([string]$writerRecovery).Trim()
        Write-Log "PATRONI_WRITER_PG_IS_IN_RECOVERY=$writerRecovery"
        if ($writerRecovery -ne "f") {
            throw "Patroni writer apunta a una replica; se aborta pg_dump."
        }

        $cmd = "set -euo pipefail; rm -f '$containerDump'; export PGPASSWORD='$($cfg.PatroniAdminPassword)'; pg_dump -h patroni-postgres-lb -p 5432 -U '$($cfg.PatroniAdminUser)' -d '$DatabaseName' -Fc -f '$containerDump'; test -s '$containerDump'; pg_restore -l '$containerDump' >/tmp/mediqueue_dump_$stamp.list"
        Invoke-Checked "patroni pg_dump custom format via writer" { docker compose -f docker-compose.yml -f docker-compose.patroni.yml exec -T $patroniRunnerService bash -lc $cmd }
        Invoke-Checked "copy patroni pg_dump to host" { docker compose -f docker-compose.yml -f docker-compose.patroni.yml cp "${patroniRunnerService}:$containerDump" $localDump }
        Invoke-Checked "cleanup patroni temp dump" { docker compose -f docker-compose.yml -f docker-compose.patroni.yml exec -T $patroniRunnerService bash -lc "rm -f '$containerDump' /tmp/mediqueue_dump_$stamp.list" }
    } elseif ($BackupMode -eq "single") {
        Invoke-Checked "postgres readiness" { docker compose exec -T $PostgresService pg_isready -U $DatabaseUser -d $DatabaseName }
        $cmd = "set -euo pipefail; rm -f '$containerDump'; export PGPASSWORD=`"`$POSTGRES_PASSWORD`"; pg_dump -U '$DatabaseUser' -d '$DatabaseName' -Fc -f '$containerDump'; test -s '$containerDump'; pg_restore -l '$containerDump' >/tmp/mediqueue_dump_$stamp.list"
        Invoke-Checked "pg_dump custom format" { docker compose exec -T $PostgresService bash -lc $cmd }
        Invoke-Checked "copy pg_dump to host" { docker compose cp "${PostgresService}:$containerDump" $localDump }
        Invoke-Checked "cleanup container temp dump" { docker compose exec -T $PostgresService bash -lc "rm -f '$containerDump' /tmp/mediqueue_dump_$stamp.list" }
    } else {
        throw "BackupMode invalido: $BackupMode. Use single o patroni."
    }

    if (-not (Test-Path -LiteralPath $localDump) -or (Get-Item -LiteralPath $localDump).Length -le 0) {
        throw "pg_dump no fue creado o esta vacio: $localDump"
    }

    $checksum = Get-FileHash -Algorithm SHA256 -LiteralPath $localDump
    $checksumFile = "$localDump.sha256"
    "$($checksum.Hash)  $(Split-Path -Leaf $localDump)" | Set-Content -LiteralPath $checksumFile -Encoding utf8
    if (-not (Test-Path -LiteralPath $checksumFile) -or (Get-Item -LiteralPath $checksumFile).Length -le 0) {
        throw "No se pudo generar checksum SHA256 para $localDump"
    }
    Write-Log "CHECKSUM_OK file=$checksumFile hash=$($checksum.Hash)"

    if ($GpgRecipient -or $GpgPassphrase) {
        $gpg = Get-Command gpg -ErrorAction SilentlyContinue
        if (-not $gpg) {
            throw "Se solicito cifrado GPG, pero gpg no esta instalado o no esta en PATH."
        }

        if ($GpgRecipient) {
            Invoke-Checked "encrypt pg_dump with GPG recipient" { gpg --batch --yes --recipient $GpgRecipient --encrypt $localDump }
        } else {
            Invoke-Checked "encrypt pg_dump with GPG symmetric passphrase" { gpg --batch --yes --pinentry-mode loopback --passphrase $GpgPassphrase --symmetric --cipher-algo AES256 $localDump }
        }
        Write-Log "ENCRYPTION_OK output=$localDump.gpg"
    } else {
        Write-Log "ENCRYPTION_SKIPPED reason=no_gpg_recipient_or_passphrase"
    }

    Write-Log "DUMP_OK file=$localDump bytes=$((Get-Item -LiteralPath $localDump).Length)"

    if ($GoogleDrivePath) {
        New-Item -ItemType Directory -Force -Path $GoogleDrivePath | Out-Null
        Copy-Item -LiteralPath $localDump -Destination $GoogleDrivePath -Force
        Copy-Item -LiteralPath $checksumFile -Destination $GoogleDrivePath -Force
        if (Test-Path -LiteralPath "$localDump.gpg") {
            Copy-Item -LiteralPath "$localDump.gpg" -Destination $GoogleDrivePath -Force
        }
        Write-Log "GOOGLE_DRIVE_COPY_OK destination=$GoogleDrivePath"
    }

    exit 0
} catch {
    Write-Log "ERROR $($_.Exception.Message)"
    exit 1
}

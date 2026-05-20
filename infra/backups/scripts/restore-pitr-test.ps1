param(
    [string]$ConfigPath,
    [string]$BaseBackupPath,
    [datetime]$RecoveryTargetTime = (Get-Date),
    [switch]$PlanOnly
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "backup-common.ps1")

Initialize-BackupConfiguration -ConfigPath $ConfigPath
Start-BackupLog -Name "restore-pitr-test"

if ([string]::IsNullOrWhiteSpace($BaseBackupPath)) {
    $baseBackup = Get-ChildItem -LiteralPath $Script:LocalBackupDir -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "mediqueue_base_*" } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if ($baseBackup) {
        $BaseBackupPath = $baseBackup.FullName
    }
    else {
        $BaseBackupPath = "<ruta-a-backup-base>"
    }
}
else {
    $BaseBackupPath = Resolve-BackupPath -Path $BaseBackupPath -BasePath $Script:RepoRoot -MustExist:$true
}

$walFiles = @(Get-ChildItem -LiteralPath $Script:WalArchiveDir -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '^[0-9A-F]{24}(\.partial)?$' } |
    Sort-Object Name)

$planPath = Join-Path $Script:RestoreTestDir "PITR_PLAN.txt"
$targetUtc = $RecoveryTargetTime.ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ss'Z'")

$plan = @"
MediQueue PITR restore plan
Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Mode: PlanOnly

Safety rules
- Do not restore over the main database '$Script:DatabaseName'.
- Do not run docker compose down -v.
- Use an isolated PostgreSQL container or isolated host.
- Keep the original postgres-data volume untouched.

Inputs
- Base backup: $BaseBackupPath
- WAL archive: $Script:WalArchiveDir
- Recovery target time UTC: $targetUtc
- WAL files currently detected: $($walFiles.Count)

High-level restore steps
1. Stop only the isolated test PostgreSQL instance, never the production Compose service.
2. Copy the selected base backup directory to an isolated PGDATA directory.
3. Ensure PGDATA ownership/permissions match the postgres user in the isolated environment.
4. Add these recovery settings to postgresql.auto.conf in the isolated PGDATA:
   restore_command = 'cp /wal-archive/%f %p'
   recovery_target_time = '$targetUtc'
   recovery_target_action = 'promote'
5. Create an empty recovery.signal file in the isolated PGDATA.
6. Mount the WAL archive read-only at /wal-archive.
7. Start the isolated PostgreSQL instance.
8. Validate with pg_isready and read-only queries.
9. Export evidence to infra/backups/restore-test/.
10. Destroy only the isolated restore-test instance after evidence is collected.

Example isolated docker run command
docker run --rm --name mediqueue-pitr-drill `
  -p 55432:5432 `
  -v "<isolated-pgdata>:/var/lib/postgresql/data" `
  -v "$($Script:WalArchiveDir):/wal-archive:ro" `
  postgres:16

Notes
- This script intentionally does not execute the restore.
- This script does not connect to or modify the main database.
- Use verify-wal-archive.ps1 before planning PITR to confirm WAL freshness.
"@

$plan | Set-Content -LiteralPath $planPath -Encoding UTF8

Write-Log "PITR PlanOnly generado: $planPath" "OK"
Write-Log "RecoveryTargetTime UTC: $targetUtc" "OK"
Write-Log "WAL detectados: $($walFiles.Count)" "OK"

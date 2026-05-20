# MediQueue Backups

PostgreSQL service: `postgres` (`mediqueue-postgres`). Backups live under `infra/backups/`; real artifacts are ignored by git.

## Strategy

- RPO target: <= 5 minutes through continuous WAL archiving with `archive_timeout=300`.
- RTO target: 30-60 minutes; emergency maximum 2 hours.
- Physical/base backup: daily at 21:00.
- Logical `pg_dump -Fc`: daily at 22:00.
- Google Drive sync: daily at 22:30 using a local Drive folder or optional `rclone` remote.
- Cleanup: daily at 23:00.
- Verification: daily at 23:30.
- `pg_dump` restore test: weekly, Sunday 23:45.
- PITR test: monthly in an isolated restore environment.

Retention:

- Base/full daily backups: 14 days.
- WAL archive: 14 days.
- Daily pg_dump files: 30 days.
- Weekly copies: 8 weeks.
- Monthly copies: 12 months.

## Configuration

Do not commit secrets. Copy the local example and adjust it for the machine where the scheduled tasks will run:

```powershell
Copy-Item .\infra\backups\config\backup.local.example.ps1 .\infra\backups\config\backup.local.ps1
notepad .\infra\backups\config\backup.local.ps1
```

Recommended local values for this project:

```powershell
$BackupRoot = ".\infra\backups"
$GoogleDriveBackupPath = "B:\Proyecto BD II Microservivios\MediQueue Backups"
$DatabaseName = "mediqueue"
$DatabaseUser = "mediqueue"
$PostgresService = "postgres"
$PostgresContainer = "mediqueue-postgres"
```

`backup.local.ps1` is ignored by git. The scheduled tasks read this file directly, so they do not depend on temporary `$env:GOOGLE_DRIVE_BACKUP_PATH` values from an interactive PowerShell session.

Optional encryption for pg_dump:

```powershell
$env:MEDIQUEUE_BACKUP_GPG_RECIPIENT="your-key@example.com"
# or symmetric encryption, only from a local shell/secret manager:
$env:MEDIQUEUE_BACKUP_GPG_PASSPHRASE="..."
```

## WAL / PITR

`docker-compose.yml` starts PostgreSQL with:

```text
wal_level=replica
archive_mode=on
archive_timeout=300
archive_command=test ! -f /var/lib/postgresql/wal-archive/%f && cp %p /var/lib/postgresql/wal-archive/%f
```

Mounted paths:

```text
postgres-data                  -> /var/lib/postgresql/data
./infra/backups/wal-archive    -> /var/lib/postgresql/wal-archive
./infra/backups/local          -> /backups
```

WAL files are PostgreSQL change logs. A base backup plus WAL lets PostgreSQL replay changes to a chosen point in time. This is what gives the approximate 5-minute RPO.

Apply Compose changes:

```powershell
docker compose up -d --force-recreate postgres
docker compose up -d postgres-lb
```

Do not use `docker compose down -v` unless you intentionally want to delete the database volume.

## Manual Commands

Base backup:

```powershell
.\infra\backups\scripts\backup-base.ps1
```

Daily pg_dump:

```powershell
.\infra\backups\scripts\backup-pgdump.ps1
```

Verify WAL archiving:

```powershell
.\infra\backups\scripts\verify-wal-archive.ps1
```

Sync to Google Drive folder or rclone remote:

```powershell
.\infra\backups\scripts\sync-google-drive.ps1
```

`sync-google-drive.ps1` does not authenticate with Google and does not store Google credentials. It copies files into a local folder that Google Drive Desktop is already synchronizing. Google Drive Desktop must be installed, signed in, and actively syncing that folder.

The script verifies file counts, byte counts, latest copied files, `.dump`, `.sha256`, base backups, and recent WAL. After it reports `SYNC_OK`, verify two things:

1. The local folder contains updated `dumps`, `local`, `wal-archive`, and `logs` folders.
2. Google Drive Desktop finishes sync, then the files are visible in Drive web.

Open the destination after sync:

```powershell
.\infra\backups\scripts\sync-google-drive.ps1 -OpenDestination
```

Verify the Drive folder without copying again:

```powershell
.\infra\backups\scripts\sync-google-drive.ps1 -VerifyOnly
```

Or with rclone:

```powershell
$env:MEDIQUEUE_BACKUP_RCLONE_REMOTE="gdrive:mediqueue-backups"
.\infra\backups\scripts\sync-google-drive.ps1
```

Cleanup dry-run:

```powershell
.\infra\backups\scripts\cleanup-backups.ps1 -DryRun
```

Real cleanup requires explicit confirmation:

```powershell
.\infra\backups\scripts\cleanup-backups.ps1 -ConfirmDelete
```

Verify backups:

```powershell
.\infra\backups\scripts\verify-backups.ps1
```

Quick end-to-end backup system test:

```powershell
.\infra\backups\scripts\test-backup-system.ps1
```

The test creates dummy files in ignored backup folders, syncs them to the local Google Drive folder, verifies they arrived, runs `verify-backups.ps1`, and removes only its own dummy files.

Daily pipeline:

```powershell
.\infra\backups\scripts\run-daily-backup-pipeline.ps1
```

Restore latest pg_dump into test database `mediqueue_restore_test`:

```powershell
.\infra\backups\scripts\restore-pgdump-test.ps1
```

Keep the test DB for inspection:

```powershell
.\infra\backups\scripts\restore-pgdump-test.ps1 -KeepDatabase
```

PITR plan generation:

```powershell
.\infra\backups\scripts\restore-pitr-test.ps1 `
  -BaseBackupFile .\infra\backups\local\mediqueue_base_YYYYMMDD_HHMMSS `
  -WalArchiveDir .\infra\backups\wal-archive `
  -RecoveryTargetTime "2026-05-20T18:30:00Z" `
  -PlanOnly
```

## Windows Task Scheduler

Print commands only:

```powershell
.\infra\backups\scripts\install-backup-tasks.ps1
```

Create tasks:

```powershell
.\infra\backups\scripts\install-backup-tasks.ps1 -Create
```

Create the single daily pipeline task plus cleanup and weekly restore test:

```powershell
.\infra\backups\scripts\install-backup-tasks.ps1 -Create -UsePipelineTask
```

If a task already exists and you want to replace it:

```powershell
.\infra\backups\scripts\install-backup-tasks.ps1 -Create -UsePipelineTask -DeleteExisting
```

Tasks are created with absolute script paths and the repo root as `WorkingDirectory`. They read Google Drive and database settings from `infra/backups/config/backup.local.ps1`.

Schedule created without `-UsePipelineTask`:

- Base backup daily 21:00.
- pg_dump daily 22:00.
- Google Drive sync daily 22:30.
- Cleanup daily 23:00.
- Verify daily 23:30.
- pg_dump restore test weekly Sunday 23:45.

Schedule created with `-UsePipelineTask`:

- Daily pipeline at 21:00.
- Cleanup daily 23:00.
- pg_dump restore test weekly Sunday 23:45.

Verify tasks:

```powershell
Get-ScheduledTask | Where-Object TaskName -like "MediQueue*"
```

Run the pipeline task manually:

```powershell
Start-ScheduledTask -TaskName "MediQueue Daily Backup Pipeline"
```

Review recent logs:

```powershell
Get-ChildItem .\infra\backups\logs | Sort-Object LastWriteTime -Descending | Select-Object -First 10
```

## Daily Checklist

- `verify-backups.ps1` status is `OK` or only expected `WARNING`.
- Latest base backup has `base.tar.gz`, `backup_manifest`, and `SHA256SUMS`.
- Latest pg_dump exists, is non-empty, and checksum validates.
- WAL archive has recent files.
- Google Drive sync completed.
- No backup logs contain `ERROR`.

## If A Backup Fails

1. Do not delete old backups.
2. Check `infra/backups/logs/` for the failing script.
3. Check Docker and PostgreSQL health: `docker compose ps` and `pg_isready`.
4. If WAL fails, verify disk space and `archive_command`.
5. Re-run the failed script manually after fixing the cause.
6. Run `verify-backups.ps1` again.

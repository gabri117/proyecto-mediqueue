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

Do not commit secrets. Use environment variables or copy `config/backup.config.example.ps1` / `config/backup.env.example` to an untracked location.

```powershell
$env:MEDIQUEUE_BACKUP_POSTGRES_SERVICE="postgres"
$env:MEDIQUEUE_BACKUP_DB_NAME="mediqueue"
$env:MEDIQUEUE_BACKUP_DB_USER="mediqueue"
$env:MEDIQUEUE_BACKUP_ROOT=".\infra\backups"
$env:GOOGLE_DRIVE_BACKUP_PATH="G:\My Drive\MediQueue Backups"
```

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
$env:GOOGLE_DRIVE_BACKUP_PATH="G:\My Drive\MediQueue Backups"
.\infra\backups\scripts\sync-google-drive.ps1
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

Schedule created:

- Base backup daily 21:00.
- pg_dump daily 22:00.
- Google Drive sync daily 22:30.
- Cleanup daily 23:00.
- Verify daily 23:30.
- pg_dump restore test weekly Sunday 23:45.

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
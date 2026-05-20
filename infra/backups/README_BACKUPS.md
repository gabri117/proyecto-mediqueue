# MediQueue backup strategy

This directory contains the backup automation for the MediQueue PostgreSQL database. It is intentionally isolated from microservices, gateway, HAProxy, k6, and load testing work.

## Objectives

- Target RPO: 5 minutes through WAL streaming archive.
- Target RTO: 30 to 60 minutes.
- Maximum emergency RTO: 2 hours.
- Daily base backup: 21:00.
- Daily logical `pg_dump`: 22:00.
- Google Drive Desktop local sync: 22:30.
- Daily cleanup review: 23:00, dry-run by default.
- Daily verification: 23:30.
- Weekly restore test: Sunday 23:45.

## Local configuration

Copy the example configuration and edit local paths only on your machine:

```powershell
Copy-Item .\infra\backups\config\backup.local.example.ps1 .\infra\backups\config\backup.local.ps1
```

`backup.local.ps1` is ignored by Git. Do not commit real secrets, backup files, logs, restore-test data, or Google Drive Desktop synchronized backup contents.

Default values match the current Compose service:

- Database: `mediqueue`
- User: `mediqueue`
- Compose service: `postgres`
- Container: `mediqueue-postgres`

## Google Drive Desktop

The scripts do not authenticate with Google APIs. Google Drive Desktop must already be installed and syncing the configured local folder:

```powershell
$GoogleDriveBackupPath = "B:\Proyecto BD II Microservivios\MediQueue Backups"
```

`sync-google-drive.ps1` only copies backup artifacts into that local folder.

## WAL and PITR

WAL means Write-Ahead Log. PostgreSQL writes every data change to WAL before the change is considered durable in the data files. A base backup plus archived WAL files lets PostgreSQL replay changes up to a selected recovery target time.

WAL helps the RPO because the daily base backup is only the starting point. With `archive_timeout=300`, PostgreSQL forces WAL rotation at least every 5 minutes during activity, so the archive can be used for Point-in-Time Recovery with a target RPO of 5 minutes.

The `postgres` service in `docker-compose.yml` is configured with:

- `wal_level=replica`
- `archive_mode=on`
- `archive_timeout=300`
- `archive_command=test ! -f /var/lib/postgresql/wal-archive/%f && cp %p /var/lib/postgresql/wal-archive/%f`

The WAL archive is persisted through this bind mount:

```text
./infra/backups/wal-archive:/var/lib/postgresql/wal-archive
```

Base backups are written through:

```text
./infra/backups/local:/backups
```

Apply the Compose changes without deleting volumes:

```powershell
docker compose up -d --force-recreate postgres
```

Do not run `docker compose down -v` for this workflow.

Verify WAL archiving:

```powershell
.\infra\backups\scripts\verify-wal-archive.ps1
```

The verifier checks `SHOW wal_level`, `SHOW archive_mode`, `SHOW archive_timeout`, `SHOW archive_command`, `pg_stat_archiver`, runs `SELECT pg_switch_wal();`, waits up to 90 seconds, and prints the last 10 archived WAL files.

Create a physical/base backup:

```powershell
.\infra\backups\scripts\backup-base.ps1
```

The base backup is stored as:

```text
infra/backups/local/mediqueue_base_YYYYMMDD_HHMMSS/
```

It includes `backup_manifest` when PostgreSQL provides it, `SHA256SUMS`, and a `BASE_BACKUP_OK` marker.

Copy a local snapshot of the current WAL archive:

```powershell
.\infra\backups\scripts\backup-wal-archive.ps1
```

Plan PITR without executing a restore:

```powershell
.\infra\backups\scripts\restore-pitr-test.ps1 -RecoveryTargetTime "2026-05-20T19:30:00"
```

This writes `infra/backups/restore-test/PITR_PLAN.txt`. It does not touch the main database, does not start a restore container, and does not delete data.

## Logical dumps

Create a daily logical backup with PostgreSQL custom format:

```powershell
.\infra\backups\scripts\backup-pgdump.ps1
```

The dump is stored as:

```text
infra/backups/dumps/mediqueue_dump_YYYYMMDD_HHMMSS.dump
infra/backups/dumps/mediqueue_dump_YYYYMMDD_HHMMSS.dump.sha256
```

The script validates the dump file, writes the SHA-256 checksum, and logs `DUMP_OK` and `CHECKSUM_OK`.

Run a safe logical restore test:

```powershell
.\infra\backups\scripts\restore-pgdump-test.ps1
```

The restore test uses the isolated database `mediqueue_restore_test`; it never restores over `mediqueue`. If `mediqueue_restore_test` already exists, the script asks for confirmation before recreating it. For unattended restore drills, pass the explicit recreation flag:

```powershell
.\infra\backups\scripts\restore-pgdump-test.ps1 -RecreateDatabase
```

Keep the test database for manual inspection:

```powershell
.\infra\backups\scripts\restore-pgdump-test.ps1 -RecreateDatabase -KeepDatabase
```

The restore test validates the main schemas `appointment`, `patient`, `schedule`, and `payment` when present. It also checks critical tables and logs `RESTORE_TEST_OK` when the restored database passes.

Run the consolidated daily verification:

```powershell
.\infra\backups\scripts\verify-backups.ps1
```

Expected status labels:

- `BASE_OK` / `BASE_ERROR`
- `DUMP_OK` / `DUMP_ERROR`
- `CHECKSUM_OK` / `CHECKSUM_WARNING`
- `WAL_OK` / `WAL_WARNING` / `WAL_ERROR`
- `DRIVE_SYNC_OK` / `DRIVE_SYNC_WARNING` / `DRIVE_SYNC_ERROR`
- `STATUS=OK` / `STATUS=WARNING` / `STATUS=ERROR`

## Manual checks

Non-destructive validation:

```powershell
.\infra\backups\scripts\test-backup-system.ps1
```

PowerShell AST validation only:

```powershell
Get-ChildItem .\infra\backups\scripts -Filter *.ps1 | ForEach-Object {
  $tokens = $null
  $errors = $null
  [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$errors) | Out-Null
  if ($errors.Count -gt 0) { throw "$($_.FullName): $($errors[0].Message)" }
}
```

Docker Compose config validation:

```powershell
docker compose -f .\docker-compose.yml config --quiet
```

## Manual backup commands

Run these only when you are ready to create real backup artifacts:

```powershell
.\infra\backups\scripts\backup-base.ps1
.\infra\backups\scripts\verify-wal-archive.ps1
.\infra\backups\scripts\backup-wal-archive.ps1
.\infra\backups\scripts\backup-pgdump.ps1
.\infra\backups\scripts\sync-google-drive.ps1
.\infra\backups\scripts\verify-backups.ps1
.\infra\backups\scripts\restore-pgdump-test.ps1 -RecreateDatabase
```

Cleanup is dry-run unless `-Apply` is explicitly passed:

```powershell
.\infra\backups\scripts\cleanup-backups.ps1 -DryRun
.\infra\backups\scripts\cleanup-backups.ps1 -Apply
```

Restore tests are isolated:

```powershell
.\infra\backups\scripts\restore-pgdump-test.ps1
.\infra\backups\scripts\restore-pitr-test.ps1
```

## Scheduled tasks

Register Windows scheduled tasks:

```powershell
.\infra\backups\scripts\install-backup-tasks.ps1
```

The cleanup task is registered with `-DryRun` so it does not delete files automatically.

## Retention defaults

- Base backups: 7 days.
- Logical dumps: 14 days.
- WAL archive: 7 days.
- Logs: 30 days.
- Weekly base copies: 8 weeks.
- Monthly base copies: 12 months.

Adjust retention only in `backup.local.ps1` for the local machine.

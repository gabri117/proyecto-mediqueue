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

Google Drive Desktop must be installed, signed in, and syncing the configured local folder. The backup scripts do not sign in to Google, do not call Google APIs, and do not upload directly to Drive. They only copy files to a local folder that Google Drive Desktop syncs.

```powershell
$GoogleDriveBackupPath = "B:\Proyecto BD II Microservivios\MediQueue Backups"
```

Create the local config from the example:

```powershell
Copy-Item .\infra\backups\config\backup.local.example.ps1 .\infra\backups\config\backup.local.ps1
```

Then confirm this value in `backup.local.ps1`:

```powershell
$GoogleDriveBackupPath = "B:\Proyecto BD II Microservivios\MediQueue Backups"
```

`sync-google-drive.ps1` copies these local backup folders while preserving structure:

- `infra/backups/dumps` to `MediQueue Backups/dumps`
- `infra/backups/local` to `MediQueue Backups/local`
- `infra/backups/wal-archive` to `MediQueue Backups/wal-archive`
- `infra/backups/logs` to `MediQueue Backups/logs`

Run synchronization:

```powershell
.\infra\backups\scripts\sync-google-drive.ps1
```

Verify the destination without copying and open it in Explorer:

```powershell
.\infra\backups\scripts\sync-google-drive.ps1 -VerifyOnly -OpenDestination
```

Use an explicit destination for diagnostics:

```powershell
.\infra\backups\scripts\sync-google-drive.ps1 -DestinationPath "B:\Proyecto BD II Microservivios\MediQueue Backups"
```

The script prints `SOURCE_COUNT`, `DEST_COUNT`, `SOURCE_BYTES`, `DEST_BYTES`, and `LAST_COPIED_FILES`. It validates each copied source file against its destination copy with size and SHA-256. It fails if the destination is empty. It prints `SYNC_OK` only when the destination contains the expected dump, checksum, base-backup marker, and recent WAL; otherwise it prints `SYNC_WARNING` with the missing category.

In Google Drive web, Desktop-synced folders may appear under "Computers" or the machine name, not necessarily under "My Drive".

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

It is generated with `pg_basebackup -Ft -z -X stream -c fast -P`, so the expected structure is:

```text
infra/backups/local/mediqueue_base_YYYYMMDD_HHMMSS/base.tar.gz
infra/backups/local/mediqueue_base_YYYYMMDD_HHMMSS/pg_wal.tar.gz
infra/backups/local/mediqueue_base_YYYYMMDD_HHMMSS/SHA256SUMS
infra/backups/local/mediqueue_base_YYYYMMDD_HHMMSS/BACKUP_BASE_OK.txt
```

`pg_basebackup` can write progress such as `waiting for checkpoint` to stderr. The script records stdout and stderr in the log, but only fails when the process exit code is non-zero or the final backup structure is incomplete.

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

It requires at least one dump created by `backup-pgdump.ps1`.

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
- `BASE_WARNING` when incomplete base backup folders exist but an older valid base backup is available
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

This sync test requires `backup.local.ps1`, creates only `sync_test_*` dummy files in `dumps` and `logs`, verifies they reached the Google Drive Desktop folder, and deletes only those dummy files. It does not delete real backups.

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

Run the automated daily pipeline manually:

```powershell
.\infra\backups\scripts\run-daily-backup-pipeline.ps1
```

The pipeline runs, in order:

- `backup-base.ps1`
- `backup-pgdump.ps1`
- `verify-wal-archive.ps1`
- `sync-google-drive.ps1`
- `verify-backups.ps1`

It writes one evidence log per run:

```text
infra/backups/logs/pipeline_YYYYMMDD_HHMMSS.log
```

The pipeline stops on base backup, pg_dump, or sync failures. WAL and final verification warnings are recorded as `PIPELINE_STATUS=WARNING`; a clean run ends with `PIPELINE_STATUS=OK`.

Cleanup is dry-run by default. It prints each candidate with file, age, category, and reason. It never deletes `.gitkeep` and never deletes files from the current day.

```powershell
.\infra\backups\scripts\cleanup-backups.ps1 -DryRun
```

Real cleanup requires explicit confirmation:

```powershell
.\infra\backups\scripts\cleanup-backups.ps1 -ConfirmDelete
```

Google Drive Desktop cleanup is not included unless requested separately, and still requires confirmation:

```powershell
.\infra\backups\scripts\cleanup-backups.ps1 -ConfirmDelete -IncludeGoogleDrive
```

Find incomplete physical/base backup folders without deleting anything:

```powershell
.\infra\backups\scripts\cleanup-incomplete-base-backups.ps1 -DryRun
```

Delete only incomplete `mediqueue_base_*` folders after reviewing the dry run:

```powershell
.\infra\backups\scripts\cleanup-incomplete-base-backups.ps1 -ConfirmDelete
```

Restore tests are isolated:

```powershell
.\infra\backups\scripts\restore-pgdump-test.ps1
.\infra\backups\scripts\restore-pitr-test.ps1
```

## Scheduled tasks

Preview Windows scheduled tasks without creating anything:

```powershell
.\infra\backups\scripts\install-backup-tasks.ps1
```

Recommended pipeline-based installation:

```powershell
.\infra\backups\scripts\install-backup-tasks.ps1 -Create -UsePipelineTask
```

This creates:

- `MediQueue Daily Backup Pipeline` at 21:00 daily
- `MediQueue Cleanup Daily` at 23:00 daily, always with `-DryRun`
- `MediQueue Restore PgDump Test Weekly` on Sunday at 23:45

Separate-task installation:

```powershell
.\infra\backups\scripts\install-backup-tasks.ps1 -Create
```

This creates:

- `MediQueue Backup Base Daily` at 21:00
- `MediQueue PgDump Daily` at 22:00
- `MediQueue Sync Google Drive Daily` at 22:30
- `MediQueue Cleanup Daily` at 23:00, always with `-DryRun`
- `MediQueue Verify Daily` at 23:30
- `MediQueue Restore PgDump Test Weekly` on Sunday at 23:45

Replace existing tasks explicitly:

```powershell
.\infra\backups\scripts\install-backup-tasks.ps1 -Create -UsePipelineTask -DeleteExisting
```

Preview a create run without registering tasks:

```powershell
.\infra\backups\scripts\install-backup-tasks.ps1 -Create -UsePipelineTask -WhatIf
```

View tasks:

```powershell
Get-ScheduledTask | Where-Object TaskName -like "MediQueue*"
```

Run the pipeline task manually:

```powershell
Start-ScheduledTask -TaskName "MediQueue Daily Backup Pipeline"
```

View the last result:

```powershell
Get-ScheduledTaskInfo -TaskName "MediQueue Daily Backup Pipeline"
```

The installer uses an absolute script path, an absolute `backup.local.ps1` path, and the repository root as the scheduled task working directory. It prefers `pwsh.exe` if available and falls back to `powershell.exe`.

Google Drive Desktop normally syncs best when the Windows user is signed in. If a scheduled task runs without an interactive user session, the scripts can still create and copy files locally, but Google Drive Desktop may not upload them until the user signs in.

## Retention defaults

- Base backups: 14 days.
- Logical dumps: 30 days.
- WAL archive: 14 days.
- Logs: 30 days.
- Weekly base copies: 8 weeks.
- Monthly base copies: 12 months.

Adjust retention only in `backup.local.ps1` for the local machine.

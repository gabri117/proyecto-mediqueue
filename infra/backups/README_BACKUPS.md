# MediQueue Backup Strategy

MediQueue uses PostgreSQL 16 in Docker Compose. The PostgreSQL service is:

```text
service: postgres
container: mediqueue-postgres
database: mediqueue
default user: mediqueue
```

Do not commit real backups, database passwords, Google Drive credentials, or restore artifacts.

## Objectives

- RPO target: maximum 5 minutes of data loss.
- RTO target: 30 to 60 minutes for normal recovery.
- Emergency RTO maximum: 2 hours.
- Backups must be verifiable.
- Backups are stored locally and copied externally, for example to Google Drive.

## Operating Schedule

Clinic schedule:

- Open: 08:00 to 20:00.
- Lunch: 13:00 to 14:00.
- Heavy backup window: after closing.

Backup schedule:

- Physical/base backup: daily at 21:00.
- Logical `pg_dump`: daily at 22:00.
- WAL archive: continuous, with `archive_timeout=5min`.
- Daily verification: check latest base, dump, and WAL files.
- Weekly logical restore test.
- Monthly PITR restore test.
- Full recovery drill every 3 months.

## Retention

- Daily full/base backups: 14 days.
- WAL archive: 14 days.
- Daily `pg_dump`: 30 days.
- Weekly backups: 8 weeks.
- Monthly backups: 12 months.

The cleanup script enforces the daily base/WAL/dump retention windows. Weekly and monthly retention should be implemented by copying selected artifacts into separate external folders or Google Drive retention folders.

## Configuration

Examples live in `infra/backups/config/`:

- `backup.env.example`
- `backup.config.example.ps1`

Use environment variables or a local untracked config. Do not put passwords in committed files.

PowerShell example:

```powershell
$env:MEDIQUEUE_BACKUP_POSTGRES_SERVICE="postgres"
$env:MEDIQUEUE_BACKUP_DB_NAME="mediqueue"
$env:MEDIQUEUE_BACKUP_DB_USER="mediqueue"
$env:MEDIQUEUE_BACKUP_ROOT=".\infra\backups"
$env:MEDIQUEUE_BACKUP_GOOGLE_DRIVE_PATH="G:\My Drive\MediQueue Backups"
```

The scripts run inside the PostgreSQL container and use the container's `POSTGRES_PASSWORD` environment variable where needed. No database password is stored in the repo.

## Docker Compose WAL Configuration

`docker-compose.yml` configures PostgreSQL with:

```text
wal_level=replica
archive_mode=on
archive_timeout=300
archive_command=test ! -f /var/lib/postgresql/wal-archive/%f && cp %p /var/lib/postgresql/wal-archive/%f
```

Mounted paths:

```text
postgres-data volume                      -> /var/lib/postgresql/data
./infra/backups/wal-archive               -> /var/lib/postgresql/wal-archive
./infra/backups/local                     -> /backups
```

The `archive_command` is idempotent: it uses `test ! -f ... && cp ...`, so an existing WAL segment is not overwritten.

To apply these PostgreSQL settings after changing Compose:

```powershell
docker compose up -d --force-recreate postgres
docker compose up -d postgres-lb
```

If the database was already initialized before WAL settings were added, a container recreate is enough for `postgres -c ...` runtime settings. Do not run `docker compose down -v` unless you intentionally want to delete the database volume.

## Manual Commands

Start the stack first:

```powershell
docker compose up -d
```

Base physical backup:

```powershell
.\infra\backups\scripts\backup-base.ps1
```

Logical `pg_dump`:

```powershell
.\infra\backups\scripts\backup-pgdump.ps1
```

WAL archive copy/verification:

```powershell
.\infra\backups\scripts\backup-wal-archive.ps1
```

Verify live WAL archiving:

```powershell
.\infra\backups\scripts\verify-wal-archive.ps1
```

Cleanup:

```powershell
.\infra\backups\scripts\cleanup-backups.ps1
```

Dry-run cleanup:

```powershell
.\infra\backups\scripts\cleanup-backups.ps1 -WhatIfOnly
```

Verification:

```powershell
.\infra\backups\scripts\verify-backups.ps1
```

Logical restore test:

```powershell
.\infra\backups\scripts\restore-pgdump-test.ps1
```

PITR input validation:

```powershell
.\infra\backups\scripts\restore-pitr-test.ps1 -PlanOnly
```

## WAL / PITR Requirements

WAL is PostgreSQL's write-ahead log. Base backups give a physical starting point; archived WAL files let PostgreSQL replay changes after that base backup. This is what enables Point-in-Time Recovery and keeps the RPO near the configured archive timeout.

For real RPO <= 5 minutes, PostgreSQL must run with:

```text
wal_level=replica
archive_mode=on
archive_timeout=5min
archive_command='test ! -f /var/lib/postgresql/wal-archive/%f && cp %p /var/lib/postgresql/wal-archive/%f'
```

The archive target must be a persistent directory that is copied by `backup-wal-archive.ps1` and by the external Google Drive process. The script intentionally fails if `archive_mode` is off.

Do not disable cleanup. WAL can grow quickly if the archive command fails or if retention is not enforced.

Validation:

```powershell
docker compose exec -T postgres psql -U mediqueue -d mediqueue -c "show wal_level;"
docker compose exec -T postgres psql -U mediqueue -d mediqueue -c "show archive_mode;"
docker compose exec -T postgres psql -U mediqueue -d mediqueue -c "show archive_timeout;"
docker compose exec -T postgres psql -U mediqueue -d mediqueue -c "select pg_switch_wal();"
.\infra\backups\scripts\verify-wal-archive.ps1
```

## What Each Script Does

`backup-base.ps1`:

- Checks Docker.
- Checks `docker compose ps`.
- Checks PostgreSQL readiness with `pg_isready`.
- Runs `pg_basebackup` inside the `postgres` service.
- Writes a physical base backup directory to `infra/backups/local/mediqueue_base_YYYYMMDD_HHMMSS/`.
- Uses tar format with gzip compression for `base.tar.gz` and WAL stream files.
- Writes `backup_manifest` and `SHA256SUMS`.
- Optionally copies the directory to Google Drive.
- Writes a log to `infra/backups/logs/`.

`backup-pgdump.ps1`:

- Checks Docker and PostgreSQL readiness.
- Runs custom-format `pg_dump`.
- Verifies the dump with `pg_restore -l`.
- Copies `mediqueue_dump_YYYYMMDD_HHMMSS.dump` to `infra/backups/dumps/`.
- Optionally copies it to Google Drive.

`backup-wal-archive.ps1`:

- Checks Docker and PostgreSQL readiness.
- Reads `archive_mode`, `archive_command`, and `archive_timeout`.
- Fails if WAL archiving is not active.
- Copies the configured container archive directory to `infra/backups/wal-archive/wal_YYYYMMDD_HHMMSS/`.

`cleanup-backups.ps1`:

- Deletes expired local base backups, WAL archive folders, and dump files.
- Never deletes `.gitkeep`.
- Supports `-WhatIfOnly`.

`verify-backups.ps1`:

- Verifies latest base backup exists and is fresh.
- Verifies latest dump exists and is fresh.
- Verifies latest WAL file exists and is fresh enough for RPO.
- Exits non-zero if verification fails.

`restore-pgdump-test.ps1`:

- Copies the latest or specified dump into the postgres container.
- Creates a temporary restore database.
- Restores with `pg_restore`.
- Verifies expected schemas exist.
- Drops the test database unless `-KeepDatabase` is used.

`restore-pitr-test.ps1`:

- Validates that a base backup and WAL archive exist.
- Validates `base.tar.gz`, `backup_manifest`, and WAL files.
- Writes a PITR restore plan under `infra/backups/restore-test/pitr_YYYYMMDD_HHMMSS/PITR_PLAN.txt`.
- Does not touch production Docker volumes.

## PITR Procedure Summary

Monthly PITR tests should happen in an isolated environment:

1. Pick a base backup from `infra/backups/local/mediqueue_base_YYYYMMDD_HHMMSS/`.
2. Pick WAL files from `infra/backups/wal-archive/`.
3. Choose an optional recovery target time.
4. Run:

```powershell
.\infra\backups\scripts\restore-pitr-test.ps1 `
  -BaseBackupFile .\infra\backups\local\mediqueue_base_YYYYMMDD_HHMMSS `
  -WalArchiveDir .\infra\backups\wal-archive `
  -RecoveryTargetTime "2026-05-20T18:30:00Z" `
  -PlanOnly
```

5. Follow the generated `PITR_PLAN.txt` in a disposable PostgreSQL container/volume.
6. Verify schemas and critical tables.
7. Delete the disposable restore environment.

## Verification Evidence

For each backup day, keep:

- Script log from `infra/backups/logs/`.
- File name and size of the base backup.
- File name and size of the `pg_dump`.
- WAL archive age and latest WAL file.
- Result of `verify-backups.ps1`.
- Result of weekly/monthly restore tests.

## Important Notes

- Do not insert or restore into the live database during business hours unless it is an emergency.
- Do not run restore tests against the production Compose volume.
- Do not commit files under `local/`, `wal-archive/`, `dumps/`, `logs/`, or `restore-test/`.
- Heavy backups should run after 20:00, preferably 21:00 and 22:00 as scheduled.

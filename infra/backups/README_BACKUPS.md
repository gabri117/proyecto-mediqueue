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

`backup-wal-archive.ps1` uses PostgreSQL `pg_receivewal` through Docker Compose and a physical replication slot named `mediqueue_backup_slot` by default. Schedule it every 5 minutes during operating hours, 08:00 to 20:00, to support the RPO objective.

PITR tests are isolated. `restore-pitr-test.ps1` starts a separate temporary PostgreSQL container and never restores over the main database.

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
.\infra\backups\scripts\backup-wal-archive.ps1
.\infra\backups\scripts\backup-base.ps1
.\infra\backups\scripts\backup-pgdump.ps1
.\infra\backups\scripts\sync-google-drive.ps1
.\infra\backups\scripts\verify-backups.ps1
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

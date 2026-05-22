# Copy to backup.local.ps1 and adjust for your machine.
# backup.local.ps1 is ignored by git.

$BackupRoot = ".\infra\backups"
$GoogleDriveBackupPath = "B:\Proyecto BD II Microservivios\MediQueue Backups"
$DatabaseName = "mediqueue"
$DatabaseUser = "mediqueue"
$PostgresService = "postgres"
$PostgresContainer = "mediqueue-postgres"

# BackupMode:
# - "single": PostgreSQL simple actual.
# - "patroni": cluster Patroni via HAProxy writer.
$BackupMode = "single"

$PatroniWriterHost = "localhost"
$PatroniWriterPort = 55432
$PatroniDockerServicePrefix = "patroni-postgres"
$PatroniScope = "mediqueue-postgres-ha"

# Optional. Empty means backup-base.ps1 prefers a healthy replica.
$PatroniBackupNode = ""

# Development defaults only. Do not use these passwords in production.
$PatroniReplicationUser = "replicator"
$PatroniReplicationPassword = "replicator"
$PatroniAdminUser = "postgres"
$PatroniAdminPassword = "postgres"

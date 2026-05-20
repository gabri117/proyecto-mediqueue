# Copy this file to backup.local.ps1 for machine-specific settings.
# Do not commit backup.local.ps1.

$BackupRoot = ".\infra\backups"
$GoogleDriveBackupPath = "B:\Proyecto BD II Microservivios\MediQueue Backups"

$DatabaseName = "mediqueue"
$DatabaseUser = "mediqueue"
$PostgresService = "postgres"
$PostgresContainer = "mediqueue-postgres"
$DockerComposeFile = ".\docker-compose.yml"

$WalArchiveIntervalMinutes = 5
$WalReceiveDurationSeconds = 290
$WalReplicationSlot = "mediqueue_backup_slot"

$BaseBackupRetentionDays = 14
$DumpRetentionDays = 30
$WalRetentionDays = 14
$LogRetentionDays = 30
$WeeklyRetentionWeeks = 8
$MonthlyRetentionMonths = 12

$RestoreTestDatabasePrefix = "mediqueue_restore_test"
$PitrTestPort = 55432

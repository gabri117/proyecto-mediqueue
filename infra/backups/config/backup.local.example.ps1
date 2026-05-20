# Copy to backup.local.ps1 and adjust for your machine.
# backup.local.ps1 is ignored by git.

$BackupRoot = ".\infra\backups"
$GoogleDriveBackupPath = "B:\Proyecto BD II Microservivios\MediQueue Backups"
$DatabaseName = "mediqueue"
$DatabaseUser = "mediqueue"
$PostgresService = "postgres"
$PostgresContainer = "mediqueue-postgres"

# Copy this file to a local, untracked path before use.
# Do not commit real secrets.

$BackupConfig = @{
    PostgresService = "postgres"
    DatabaseName = "mediqueue"
    DatabaseUser = "mediqueue"

    # Keep this null and set MEDIQUEUE_BACKUP_DB_PASSWORD in your shell.
    DatabasePassword = $null

    BackupRoot = ".\infra\backups"
    GoogleDrivePath = $null
    ContainerWalArchiveDir = "/var/lib/postgresql/wal-archive"

    BaseRetentionDays = 14
    WalRetentionDays = 14
    DumpRetentionDays = 30

    ArchiveTimeoutMinutes = 5
}

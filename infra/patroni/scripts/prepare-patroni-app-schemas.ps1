param(
    [string]$ComposeFile = "docker-compose.patroni.yml",
    [string]$Database = "mediqueue",
    [string]$AdminUser = "postgres",
    [string]$AdminPassword = "postgres",
    [string]$AppUser = "mediqueue"
)

$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..\..\..")
$composeArgs = @("-f", "docker-compose.yml", "-f", $ComposeFile)
$schemas = @("patient", "schedule", "appointment", "payment", "notification")

$sqlLines = @()
$sqlLines += @'
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'uuid-ossp') THEN
        IF NOT EXISTS (
            SELECT 1
            FROM pg_extension
            WHERE extname = 'uuid-ossp'
              AND extnamespace = 'public'::regnamespace
        ) THEN
            ALTER EXTENSION "uuid-ossp" SET SCHEMA public;
        END IF;
    ELSE
        CREATE EXTENSION "uuid-ossp" WITH SCHEMA public;
    END IF;
END
$$;
'@
foreach ($schema in $schemas) {
    $sqlLines += "CREATE SCHEMA IF NOT EXISTS $schema AUTHORIZATION $AppUser;"
    $sqlLines += "GRANT USAGE, CREATE ON SCHEMA $schema TO $AppUser;"
}
$sqlLines += "GRANT USAGE, CREATE ON SCHEMA public TO $AppUser;"
$sqlLines += @"
DO `$`$
DECLARE
    schema_name text;
    flyway_rows bigint;
BEGIN
    FOREACH schema_name IN ARRAY ARRAY['patient', 'schedule', 'appointment', 'payment', 'notification']
    LOOP
        IF to_regclass(format('%I.flyway_schema_history', schema_name)) IS NOT NULL THEN
            EXECUTE format('SELECT count(*) FROM %I.flyway_schema_history', schema_name) INTO flyway_rows;

            IF flyway_rows = 0 THEN
                RAISE NOTICE 'Dropping empty failed Flyway history table %.flyway_schema_history', schema_name;
                EXECUTE format('DROP TABLE %I.flyway_schema_history', schema_name);
            END IF;
        END IF;
    END LOOP;
END
`$`$;
"@
$sql = $sqlLines -join "`n"

Push-Location $root
try {
    Write-Host "PREPARE_PATRONI_SCHEMAS database=$Database app_user=$AppUser"
    $sql | docker compose @composeArgs exec -T -e "PGPASSWORD=$AdminPassword" patroni-postgres-1 `
        psql -h patroni-postgres-lb -p 5432 -U $AdminUser -d $Database -v ON_ERROR_STOP=1

    if ($LASTEXITCODE -ne 0) {
        Write-Host "PREPARE_PATRONI_SCHEMAS_STATUS=ERROR"
        exit 1
    }

    Write-Host "PREPARE_PATRONI_SCHEMAS_STATUS=OK"
}
finally {
    Pop-Location
}

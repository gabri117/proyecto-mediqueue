#!/usr/bin/env bash
set -euo pipefail

APP_USER="${POSTGRES_APP_USER:-mediqueue}"
APP_PASSWORD="${POSTGRES_APP_PASSWORD:-mediqueue}"
APP_DB="${POSTGRES_APP_DB:-mediqueue}"
SUPERUSER="${PATRONI_SUPERUSER_USERNAME:-postgres}"
SUPERPASS="${PATRONI_SUPERUSER_PASSWORD:-postgres}"

case "$APP_USER" in
  ""|*[!a-zA-Z0-9_]*)
    echo "Invalid POSTGRES_APP_USER: $APP_USER" >&2
    exit 1
    ;;
esac

case "$APP_DB" in
  ""|*[!a-zA-Z0-9_]*)
    echo "Invalid POSTGRES_APP_DB: $APP_DB" >&2
    exit 1
    ;;
esac

export PGPASSWORD="$SUPERPASS"

psql -h 127.0.0.1 -p 5432 -U "$SUPERUSER" -d postgres -v ON_ERROR_STOP=1 <<SQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '$APP_USER') THEN
    CREATE ROLE $APP_USER LOGIN PASSWORD '$APP_PASSWORD';
  END IF;
END
\$\$;

SELECT 'CREATE DATABASE $APP_DB OWNER $APP_USER'
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = '$APP_DB')\gexec

GRANT ALL PRIVILEGES ON DATABASE $APP_DB TO $APP_USER;
SQL

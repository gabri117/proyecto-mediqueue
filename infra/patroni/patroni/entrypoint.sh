#!/bin/bash
set -e
chown -R postgres:postgres /home/postgres/pgdata
chown -R postgres:postgres /var/lib/postgresql/wal-archive 2>/dev/null || true
exec /usr/sbin/runuser -u postgres -- "$@"

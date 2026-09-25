#!/bin/sh
# Restores the newest backup into a scratch database and checks it; run after
# changing the backup setup and regularly (e.g. monthly).
set -eu
cd "$(dirname "$0")/.."
latest=$(ls -t backups/alvyo-*.dump | head -1)
dc="docker compose -f compose.prod.yaml exec -T db"
$dc psql -U odysgeh -d postgres -qc "DROP DATABASE IF EXISTS restore_check" -c "CREATE DATABASE restore_check"
$dc pg_restore -U odysgeh -d restore_check --no-owner < "$latest"
$dc psql -U odysgeh -d restore_check -Atc "SELECT 'users: ' || count(*) FROM users UNION ALL SELECT 'routes: ' || count(*) FROM routes"
$dc psql -U odysgeh -d postgres -qc "DROP DATABASE restore_check"
echo "restore check OK: $latest"

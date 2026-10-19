#!/bin/sh
# Loads the official hiking routes of Wanderland Schweiz (ASTRA /
# SchweizMobil, ch.astra.wanderland, opendata.swiss: open use, source
# required) into wanderland_routes and wanderland_stages. The API turns them
# into public routes and journeys of the account «wanderland» once
# imported_at is newer than its last sync. Updated a few times a year;
# re-running replaces the tables in one transaction, so the API never sees
# them half loaded. Needs PG* environment variables for the target database.
set -eu
# shellcheck source-path=SCRIPTDIR source=download.sh
. "$(dirname "$0")/download.sh"

url="https://data.geo.admin.ch/ch.astra.wanderland/wanderland/wanderland_2056.gpkg"
dir=/data/wanderland
mkdir -p "$dir"
cd "$dir"

# Downloaded again only when newer than the copy kept from the last run.
download "$url" wanderland.gpkg

# Into tables of their own first (ogr2ogr cannot join psql's transaction).
# Three routes have a way back of their own («Rückweg»): only the way there.
ogr2ogr -f PostgreSQL "PG:" wanderland.gpkg -overwrite -nln wanderland_routes_load \
	-sql "SELECT NrR AS nr, NameR AS name, Typ_TR AS kind, AOrt AS start_name, ZOrt AS end_name, geom FROM Route WHERE Abwicklung <> 'Rückweg'" \
	-t_srs EPSG:4326 -nlt MULTILINESTRING -dim XY -lco GEOMETRY_NAME=geom
ogr2ogr -f PostgreSQL "PG:" wanderland.gpkg -overwrite -nln wanderland_stages_load \
	-sql "SELECT NrR AS nr, CAST(NrEtappe AS integer) AS stage, NameS AS start_name, NameZ AS end_name, geom FROM Etappe WHERE Abwicklung <> 'Rückweg'" \
	-t_srs EPSG:4326 -nlt MULTILINESTRING -dim XY -lco GEOMETRY_NAME=geom
ogr2ogr -f PostgreSQL "PG:" wanderland.gpkg -overwrite -nln wanderland_transport_load \
	-sql "SELECT VerkehrM AS mode, geom FROM Weg WHERE VerkehrM <> ''" \
	-t_srs EPSG:4326 -nlt MULTILINESTRING -dim XY -lco GEOMETRY_NAME=geom

psql -v ON_ERROR_STOP=1 <<'SQL'
BEGIN;
DELETE FROM wanderland_stages;
DELETE FROM wanderland_routes;
DELETE FROM wanderland_transport;
INSERT INTO wanderland_transport (mode, geom) SELECT mode, geom FROM wanderland_transport_load WHERE geom IS NOT NULL;
INSERT INTO wanderland_routes (nr, name, kind, start_name, end_name, geom)
SELECT nr, name, kind, coalesce(start_name, ''), coalesce(end_name, ''), geom FROM wanderland_routes_load;
INSERT INTO wanderland_stages (nr, stage, start_name, end_name, geom)
SELECT nr, stage, coalesce(start_name, ''), coalesce(end_name, ''), geom FROM wanderland_stages_load
WHERE geom IS NOT NULL;
INSERT INTO wanderland_import (imported_at) VALUES (now())
ON CONFLICT (one) DO UPDATE SET imported_at = excluded.imported_at;
COMMIT;
DROP TABLE wanderland_routes_load, wanderland_stages_load, wanderland_transport_load;
SELECT kind, count(*) FROM wanderland_routes GROUP BY 1 ORDER BY 1;
SELECT count(*) AS stages FROM wanderland_stages;
SELECT mode, count(*) FROM wanderland_transport GROUP BY 1;
SQL

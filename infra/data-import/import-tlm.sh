#!/bin/sh
# Loads swissTLM3D Wanderwege (© swisstopo, OGD) into tlm_hiking_paths.
# Updated yearly by swisstopo; re-running replaces the table contents.
# Needs PG* environment variables for the target database.
set -eu

url="https://data.geo.admin.ch/ch.swisstopo.swisstlm3d-wanderwege/swisstlm3d-wanderwege/swisstlm3d-wanderwege_2056_5728.gpkg.zip"
dir=/data/tlm
mkdir -p "$dir"
cd "$dir"

if [ ! -f SWISSTLM3D_WANDERWEGE.gpkg ]; then
	curl -fL --retry 3 -o wanderwege.gpkg.zip "$url"
	unzip -o wanderwege.gpkg.zip
fi

psql -v ON_ERROR_STOP=1 -c "TRUNCATE tlm_hiking_paths"
ogr2ogr -f PostgreSQL "PG:" SWISSTLM3D_WANDERWEGE.gpkg \
	-append -nln tlm_hiking_paths -preserve_fid \
	-sql "SELECT id, wanderwege AS category, geom FROM tlm_strassen_strasse WHERE wanderwege IS NOT NULL" \
	-nlt MULTILINESTRING -dim XY -gt 50000
psql -v ON_ERROR_STOP=1 -c "ANALYZE tlm_hiking_paths" \
	-c "SELECT category, count(*), round(sum(ST_Length(geom)) / 1000) AS km FROM tlm_hiking_paths GROUP BY 1 ORDER BY 1"

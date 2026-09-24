#!/bin/sh
# Loads the places offered as stage starts and ends:
#  - public transport stops from the BAV list of stops (© BAV, OGD), keyed by
#    their Didok number
#  - named huts and accommodation from OpenStreetMap (© OpenStreetMap
#    contributors, ODbL), from the extract of `make osm-fetch`
# Re-running updates places in place (by source and id), so stages keep their
# choices; places that disappeared are removed and those stages fall back to
# the suggestion. Needs PG* environment variables for the target database.
set -eu

stops_url="https://data.geo.admin.ch/ch.bav.haltestellen-oev/haltestellen-oev/haltestellen-oev_2056_de.gpkg.zip"
pbf=/data/osm/ch-fl.osm.pbf
dir=/data/places
mkdir -p "$dir"
cd "$dir"

[ -f "$pbf" ] || { echo "missing $pbf: run make osm-fetch first" >&2; exit 1; }

# -z: download only if newer than the local copy.
if [ -f stops.gpkg.zip ]; then
	curl -fL --retry 3 -z stops.gpkg.zip -o stops.gpkg.zip "$stops_url"
else
	curl -fL --retry 3 -o stops.gpkg.zip "$stops_url"
fi
unzip -o -q stops.gpkg.zip HaltestellenOeV.gpkg

# Stops: VP = Haltestelle, VPG = Haltestelle und Bedienpunkt. The rest are
# operating points without passengers (junctions, depots …).
ogr2ogr -f PostgreSQL "PG:" HaltestellenOeV.gpkg \
	-overwrite -nln import_stops -lco GEOMETRY_NAME=geom -lco SPATIAL_INDEX=NONE -t_srs EPSG:4326 \
	-sql "SELECT CAST(Nummer AS TEXT) AS source_id, Name AS name, Verkehrsmittel_Bezeichnung AS detail, geom
		FROM Betriebspunkt WHERE Betriebspunkttyp_Code IN ('VP', 'VPG') AND Nummer IS NOT NULL"

# Huts and accommodation, mapped as nodes or as building outlines. The filter
# keeps the nodes and members the outlines need; the SQL below drops those.
osmium tags-filter --overwrite -o osm-places.pbf "$pbf" \
	nwr/tourism=alpine_hut,wilderness_hut,hotel,guest_house,hostel,camp_site
osmium export --overwrite -f geojsonseq -x print_record_separator=false \
	--geometry-types=point,polygon -a type,id -o osm-places.geojsonseq osm-places.pbf

psql -v ON_ERROR_STOP=1 -q <<'SQL'
CREATE UNLOGGED TABLE IF NOT EXISTS import_osm (j jsonb NOT NULL);
TRUNCATE import_osm;
-- CSV with characters that never occur in JSON as quote and delimiter, so
-- every line arrives verbatim (text COPY would eat the backslashes).
\copy import_osm FROM 'osm-places.geojsonseq' WITH (FORMAT csv, QUOTE E'\x01', DELIMITER E'\x02')

BEGIN;
CREATE TEMP TABLE incoming ON COMMIT DROP AS
SELECT 'pt_stop' AS kind, name, coalesce(detail, '') AS detail, 'didok' AS source, source_id, geom,
	'' AS website
FROM import_stops
UNION ALL
SELECT CASE p->>'tourism'
		WHEN 'alpine_hut' THEN 'hut' WHEN 'wilderness_hut' THEN 'hut'
		WHEN 'camp_site' THEN 'campsite' ELSE 'hotel' END,
	p->>'name', p->>'tourism', 'osm', left(p->>'@type', 1) || (p->>'@id'),
	ST_PointOnSurface(ST_SetSRID(ST_GeomFromGeoJSON(j->'geometry'), 4326)),
	-- Only web addresses: shown as links.
	CASE WHEN w ~* '^https?://[^\s]+$' THEN w
		WHEN w ~* '^[a-z0-9-]+(\.[a-z0-9-]+)+(/[^\s]*)?$' THEN 'https://' || w
		ELSE '' END
FROM import_osm, jsonb_extract_path(j, 'properties') AS p,
	trim(coalesce(p->>'website', p->>'contact:website', '')) AS w
WHERE p->>'name' IS NOT NULL
	AND p->>'tourism' IN ('alpine_hut', 'wilderness_hut', 'hotel', 'guest_house', 'hostel', 'camp_site');

INSERT INTO places (kind, name, detail, source, source_id, geom, website)
SELECT DISTINCT ON (source, source_id) kind, name, detail, source, source_id, geom, website FROM incoming
ON CONFLICT (source, source_id) DO UPDATE
	SET kind = excluded.kind, name = excluded.name, detail = excluded.detail, geom = excluded.geom,
		website = excluded.website;
DELETE FROM places p
WHERE NOT EXISTS (SELECT 1 FROM incoming i WHERE i.source = p.source AND i.source_id = p.source_id);
COMMIT;

DROP TABLE import_stops, import_osm;
ANALYZE places;
SELECT kind, count(*) FROM places GROUP BY 1 ORDER BY 1;
SQL

#!/bin/sh
# Downloads the Geofabrik extracts for Switzerland and Liechtenstein and merges
# them into /data/osm/ch-fl.osm.pbf, the routing graph input. Liechtenstein is
# not part of the Swiss extract but hiking routes (e.g. Via Alpina stage 1)
# start there. Re-running only downloads files whose checksum changed.
set -eu

out=/data/osm
mkdir -p "$out"
cd "$out"

for region in switzerland liechtenstein; do
	f="$region-latest.osm.pbf"
	curl -fsSL -o "$f.md5" "https://download.geofabrik.de/europe/$f.md5"
	if [ -f "$f" ] && md5sum -c --status "$f.md5"; then
		echo "$f is up to date"
		continue
	fi
	curl -fL --retry 3 -o "$f" "https://download.geofabrik.de/europe/$f"
	md5sum -c "$f.md5"
done

# Objects on the border appear in both extracts; merge drops the duplicates.
# Keep the Swiss extract's timestamp so GraphHopper reports the data date.
ts=$(osmium fileinfo -g header.option.osmosis_replication_timestamp switzerland-latest.osm.pbf)
osmium merge --overwrite -o ch-fl.osm.pbf \
	--output-header="osmosis_replication_timestamp=$ts" \
	switzerland-latest.osm.pbf liechtenstein-latest.osm.pbf
osmium fileinfo -g header.option.osmosis_replication_timestamp ch-fl.osm.pbf

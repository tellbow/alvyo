#!/bin/sh
# Downloads the Geofabrik extracts for Switzerland and Liechtenstein and those
# of the neighbouring regions, cuts the latter to 15 km around the border
# (border.geojson), and merges all into /data/osm/ch-fl.osm.pbf, the routing
# graph input. Liechtenstein is not part of the Swiss extract but hiking
# routes (e.g. Via Alpina stage 1) start there; the strip beyond the border
# lets routes go near and across it. Re-running only downloads files whose
# checksum changed.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
out=/data/osm
mkdir -p "$out"
cd "$out"

# Every Geofabrik region within 15 km of Switzerland or Liechtenstein.
neighbours="germany/baden-wuerttemberg germany/bayern/schwaben austria italy/nord-ovest italy/nord-est
	france/alsace france/franche-comte france/rhone-alpes"

for region in switzerland liechtenstein $neighbours; do
	f="$(basename "$region")-latest.osm.pbf"
	url="https://download.geofabrik.de/europe/$region-latest.osm.pbf"
	curl -fsSL -o "$f.md5" "$url.md5"
	if [ -f "$f" ] && md5sum -c --status "$f.md5"; then
		echo "$f is up to date"
		continue
	fi
	curl -fL --retry 3 -o "$f" "$url"
	md5sum -c "$f.md5"
done

# The strip beyond the border; complete ways, so paths crossing its edge
# are whole.
strips=""
for region in $neighbours; do
	name=$(basename "$region")
	osmium extract --overwrite -p "$here/border.geojson" -o "strip-$name.osm.pbf" "$name-latest.osm.pbf"
	strips="$strips strip-$name.osm.pbf"
done

# The Swiss extract first: its timestamp is the data date.
# shellcheck disable=SC2086 # the strips are separate arguments
sh "$here/merge-extracts.sh" ch-fl.osm.pbf \
	switzerland-latest.osm.pbf liechtenstein-latest.osm.pbf $strips
osmium fileinfo -g header.option.osmosis_replication_timestamp ch-fl.osm.pbf

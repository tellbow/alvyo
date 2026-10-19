#!/bin/sh
# Merges OSM extracts into one file: merge-extracts.sh OUT FIRST [MORE ...].
# OUT keeps FIRST's replication timestamp, so GraphHopper reports its data
# date.
#
# Objects on the border appear in several extracts. osmium merge drops only
# identical copies (same id and version), and Geofabrik's regions are not
# all from the same day: on a Monday at 02:00 UTC Switzerland is from the
# evening before, Baden-Württemberg and Italy from a day earlier. A border
# node edited in between is in the merge twice, and GraphHopper's import
# fails on it (node 323960126 on 2026-10-19). Merged as history,
# time-filter keeps the newest version of each object.
set -eu

out=$1
shift
ts=$(osmium fileinfo -g header.option.osmosis_replication_timestamp "$1")
osmium merge --with-history -f osh.pbf -o - "$@" |
	osmium time-filter -F osh.pbf --overwrite -o "$out" \
		--output-header="osmosis_replication_timestamp=$ts" -

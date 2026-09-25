#!/bin/sh
# Weekly routing graph refresh with fresh OSM data. The new graph is built next
# to the running one and swapped in only if the import succeeds, so routing is
# down only for the restart (~30 s). Places (stops, huts) are refreshed too.
# Cron: 0 4 * * 1  /srv/alvyo/infra/ops/refresh-graph.sh
set -eu
cd "$(dirname "$0")/.."
dc="docker compose -f compose.prod.yaml"

docker compose -f compose.yaml run --rm osm-fetch
rm -rf data/graph-cache-new
mkdir -p data/graph-cache-new
$dc run --rm --no-deps -v "$PWD/data/graph-cache-new:/data/graph-cache-new" --entrypoint sh graphhopper -c \
	'exec java $JAVA_OPTS -Ddw.graphhopper.graph.location=/data/graph-cache-new -jar /opt/graphhopper.jar import /opt/graphhopper/config.yml'
# Both CH profiles must have been prepared.
test -f data/graph-cache-new/nodes_ch_hike && test -f data/graph-cache-new/nodes_ch_alpine

$dc stop graphhopper
rm -rf data/graph-cache-old
mv data/graph-cache data/graph-cache-old
mv data/graph-cache-new data/graph-cache
$dc start graphhopper
echo "graph refreshed; previous graph kept in data/graph-cache-old"
$dc run --rm places-import

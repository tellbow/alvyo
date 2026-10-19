#!/bin/sh
# Test of merge-extracts.sh; runs in the data-import image (osmium):
#   docker run --rm -v "$PWD/infra/data-import:/scripts:ro" alvyo-data-import sh /scripts/merge-extracts_test.sh
set -eu

here=$(cd "$(dirname "$0")" && pwd)
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT

# The Swiss extract a day newer than the German one: node 1 was edited in
# between, node 2 was not.
cat >"$dir/ch.opl" <<'EOF'
n1 v5 dV c2 t2026-10-18T18:47:38Z i1 ua T x8.7985774 y47.6989372
n2 v1 dV c1 t2020-01-01T00:00:00Z i1 ua T x8.80 y47.70
EOF
cat >"$dir/de.opl" <<'EOF'
n1 v4 dV c1 t2026-04-05T07:51:28Z i1 ua T x8.7985699 y47.6989430
n2 v1 dV c1 t2020-01-01T00:00:00Z i1 ua T x8.80 y47.70
EOF
osmium cat -o "$dir/ch.osm.pbf" "$dir/ch.opl" \
	--output-header="osmosis_replication_timestamp=2026-10-18T20:25:06Z"
osmium cat -o "$dir/de.osm.pbf" "$dir/de.opl"

sh "$here/merge-extracts.sh" "$dir/out.osm.pbf" "$dir/ch.osm.pbf" "$dir/de.osm.pbf"

got=$(osmium cat -f opl "$dir/out.osm.pbf" | cut -d' ' -f1,2 | tr '\n' ' ')
want="n1 v5 n2 v1 "
if [ "$got" != "$want" ]; then
	echo "FAIL: objects: got '$got', want '$want'" >&2
	exit 1
fi
ts=$(osmium fileinfo -g header.option.osmosis_replication_timestamp "$dir/out.osm.pbf")
if [ "$ts" != 2026-10-18T20:25:06Z ]; then
	echo "FAIL: timestamp: got '$ts'" >&2
	exit 1
fi
echo "ok"

#!/bin/sh
# Test of download.sh against a small fake server; runs in the data-import
# image (curl, python3):
#   docker run --rm -v "$PWD/infra/data-import:/scripts:ro" alvyo-data-import sh /scripts/download_test.sh
set -eu

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source-path=SCRIPTDIR source=download.sh
. "$here/download.sh"
dir=$(mktemp -d)
trap 'kill "$server" 2>/dev/null; rm -rf "$dir"' EXIT

# /busy: 503 twice, then the file; /gone: 404; /same: 304 when asked with
# If-Modified-Since.
python3 - "$dir/port" <<'EOF' &
import http.server, sys
busy = 0
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        global busy
        if self.path == "/busy":
            busy += 1
            if busy <= 2:
                self.send_response(503); self.end_headers(); return
        elif self.path == "/gone":
            self.send_response(404); self.end_headers(); return
        elif self.path == "/same" and self.headers["If-Modified-Since"]:
            self.send_response(304); self.end_headers(); return
        self.send_response(200); self.end_headers(); self.wfile.write(b"new")
    def log_message(self, *a): pass
srv = http.server.HTTPServer(("127.0.0.1", 0), H)
open(sys.argv[1], "w").write(str(srv.server_port))
srv.serve_forever()
EOF
server=$!
while [ ! -s "$dir/port" ]; do sleep 0.1; done
base="http://127.0.0.1:$(cat "$dir/port")"
cd "$dir"

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

start=$(date +%s)
download "$base/busy" busy.txt 2>err.txt
[ "$(cat busy.txt)" = new ] || fail "busy: $(cat busy.txt)"
[ "$(grep -c 'again in' err.txt)" = 2 ] || fail "busy: $(cat err.txt)"
# Waits of 1-2 s and 2-3 s.
[ $(($(date +%s) - start)) -ge 3 ] || fail "busy: retried too soon"

echo kept >gone.txt
if download "$base/gone" gone.txt 2>err.txt; then fail "gone: no error"; fi
[ "$(cat gone.txt)" = kept ] || fail "gone: the kept copy changed"
grep -q 'again in' err.txt && fail "gone: retried"
[ ! -e gone.txt.part ] || fail "gone: .part left"

echo kept >same.txt
download "$base/same" same.txt
[ "$(cat same.txt)" = kept ] || fail "same: replaced although not newer"

echo ok

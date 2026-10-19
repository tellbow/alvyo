"""Test of fetch() in swissalti3d.py against a small fake server; runs in the
data-import image:
  docker run --rm -v "$PWD/infra/data-import:/scripts:ro" alvyo-data-import python3 /scripts/swissalti3d_test.py
"""
import http.server, os, sys, threading, urllib.error
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import swissalti3d as m

hits = {"/busy": 0, "/gone": 0}
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        hits[self.path] += 1
        if self.path == "/busy" and hits["/busy"] <= 2:
            self.send_response(503); self.end_headers(); return
        if self.path == "/gone":
            self.send_response(404); self.end_headers(); return
        self.send_response(200); self.end_headers(); self.wfile.write(b"ok")
    def log_message(self, *a): pass
srv = http.server.HTTPServer(("127.0.0.1", 0), H)
threading.Thread(target=srv.serve_forever, daemon=True).start()
base = f"http://127.0.0.1:{srv.server_port}"
waits = []
m.time.sleep = waits.append
assert m.fetch(base + "/busy") == b"ok" and hits["/busy"] == 3, hits
assert 1 <= waits[0] < 2 and 2 <= waits[1] < 3, waits
try:
    m.fetch(base + "/gone"); raise SystemExit("404 not raised")
except urllib.error.HTTPError as e:
    assert e.code == 404 and hits["/gone"] == 1, hits
print("ok: waits", [round(w, 2) for w in waits], "404 not retried")

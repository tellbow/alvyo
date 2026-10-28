"""Test of icon_run() in weather-precip.py against a small fake STAC; runs in
the data-import image:
  docker run --rm -v "$PWD/infra/data-import:/scripts:ro" alvyo-data-import python3 /scripts/weather-precip_test.py
"""
import http.server, importlib.util, json, os, threading
from datetime import datetime, timezone

spec = importlib.util.spec_from_file_location("wp", os.path.join(os.path.dirname(os.path.abspath(__file__)), "weather-precip.py"))
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

# The 09:00 run lists hour 5 before its file is up; the 06:00 run is complete.
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        ref = json.loads(self.rfile.read(int(self.headers["Content-Length"])))["forecast:reference_datetime"]
        items = [{"properties": {"forecast:horizon": f"P0DT{h}H0M0S"},
                  "assets": {} if ref.endswith("09:00:00Z") and h == 5 else {"a": {"href": f"{ref}/{h}"}}}
                 for h in range(24)]
        self.send_response(200); self.end_headers(); self.wfile.write(json.dumps({"features": items}).encode())
    def log_message(self, *a): pass
srv = http.server.HTTPServer(("127.0.0.1", 0), H)
threading.Thread(target=srv.serve_forever, daemon=True).start()
m.STAC = f"http://127.0.0.1:{srv.server_port}"

run, urls = m.icon_run(datetime(2026, 10, 28, 10, 20, tzinfo=timezone.utc))
assert run == datetime(2026, 10, 28, 6, tzinfo=timezone.utc), run
assert sorted(urls) == list(range(4, 17)) and urls[5] == "2026-10-28T06:00:00Z/5", urls
print("ok: item without file skipped, run", f"{run:%H:%M}")

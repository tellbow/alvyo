"""Test of newest() in snow-cover.py against a small fake bucket; runs in the
data-import image:
  docker run --rm -v "$PWD/infra/data-import:/scripts:ro" alvyo-data-import python3 /scripts/snow-cover_test.py
"""
import http.server, importlib.util, os, threading, urllib.parse
from datetime import date

spec = importlib.util.spec_from_file_location("sc", os.path.join(os.path.dirname(os.path.abspath(__file__)), "snow-cover.py"))
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

have = set()  # (tile, "YYYY/MM/DD") in the bucket
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        prefix = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)["prefix"][0]
        _, tile, day = prefix.rstrip("/").split("/", 2)
        body = f"<Prefix>{prefix}</Prefix>"
        if (tile, day) in have:
            body += f"<Prefix>{prefix}CLMS_WSI_GFSC_060m_T{tile}_V102/</Prefix>"
        self.send_response(200); self.end_headers(); self.wfile.write(body.encode())
    def log_message(self, *a): pass
srv = http.server.HTTPServer(("127.0.0.1", 0), H)
threading.Thread(target=srv.serve_forever, daemon=True).start()
m.BUCKET = f"http://127.0.0.1:{srv.server_port}"
today = date(2026, 10, 28)

# Every tile yesterday.
have = {(t, "2026/10/27") for t in m.TILES}
day, found = m.newest(today)
assert day == date(2026, 10, 27) and len(found) == 11, (day, found)
assert found["32TLT"][1].endswith("/GFSC/32TLT/2026/10/27/CLMS_WSI_GFSC_060m_T32TLT_V102/CLMS_WSI_GFSC_060m_T32TLT_V102_GF.tif"), found

# 32TLT missing yesterday: its product of three days ago.
have = {(t, "2026/10/27") for t in m.TILES if t != "32TLT"} | {("32TLT", "2026/10/25")}
day, found = m.newest(today)
assert day == date(2026, 10, 27) and found["32TLT"][0] == date(2026, 10, 25) and len(found) == 11, (day, found)

# 32TLT missing for longer than DAYS_BACK: left out.
have = {(t, "2026/10/27") for t in m.TILES if t != "32TLT"} | {("32TLT", "2026/10/21")}
day, found = m.newest(today)
assert day == date(2026, 10, 27) and "32TLT" not in found and len(found) == 10, (day, found)

# Nothing at all.
have = set()
assert m.newest(today) == (None, {})
print("ok: newest tile per tile, missing ones left out")

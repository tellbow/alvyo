"""Builds reference_stages.json from the official Wanderland stages.

Download wanderland_2056.shp.zip from
https://data.geo.admin.ch/api/stac/v1/collections/ch.astra.wanderland (ASTRA /
SchweizMobil, opendata.swiss, open use with source), unzip it, then:

  ogr2ogr -f GeoJSON ref.geojson <dir>/Etappe.shp -t_srs EPSG:4326 \
    -lco COORDINATE_PRECISION=6 -lco RFC7946=YES \
    -where "(NrR = '1' AND NrEtappe <= 10) OR (NrR IN ('2','3','4','5','6','7') AND NrEtappe <= 3)" \
    -select NrR,NrEtappe,NameS,NameZ,DistanzE,HoeheAufE,HoeheAbE,ZeitStZiE,ZeitZiStE,TechnikE
  python3 make_reference_stages.py ref.geojson > reference_stages.json
"""

import json
import sys


def enc_val(v):
    v = ~(v << 1) if v < 0 else (v << 1)
    out = ""
    while v >= 0x20:
        out += chr((0x20 | (v & 0x1F)) + 63)
        v >>= 5
    return out + chr(v + 63)


def encode(pts):
    """Google polyline (lat, lon order, precision 1e5) of [lon, lat] points."""
    out, plat, plon = "", 0, 0
    for lon, lat in pts:
        ilat, ilon = round(lat * 1e5), round(lon * 1e5)
        out += enc_val(ilat - plat) + enc_val(ilon - plon)
        plat, plon = ilat, ilon
    return out


features = json.load(open(sys.argv[1]))["features"]
features.sort(key=lambda f: (int(f["properties"]["NrR"]), f["properties"]["NrEtappe"]))
stages = []
for f in features:
    p, line = f["properties"], f["geometry"]["coordinates"][0]
    stages.append({
        "route": int(p["NrR"]), "stage": int(p["NrEtappe"]), "from": p["NameS"], "to": p["NameZ"],
        "distance_m": round(p["DistanzE"]), "ascent_m": p["HoeheAufE"], "descent_m": p["HoeheAbE"],
        "minutes": p["ZeitStZiE"], "minutes_reverse": p["ZeitZiStE"], "technique": p["TechnikE"],
        "line": encode([(q[0], q[1]) for q in line]),
    })
json.dump({
    "source": "ASTRA / SchweizMobil, Wanderland Schweiz (ch.astra.wanderland, 2026 shapefile, layer Etappe), "
              "opendata.swiss; geometry as Google polyline (lat, lon, precision 1e5)",
    "stages": stages,
}, sys.stdout, ensure_ascii=False, indent=1)
print()

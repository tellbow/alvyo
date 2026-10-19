#!/usr/bin/env python3
"""swisstopo's height model swissALTI3D (2 m, Switzerland and Liechtenstein)
on our own disk, so the API needs no outside service for heights. Each 1 km
tile becomes /data/alti/E-N.png (E, N: its south-west corner in km of LV95):
500 x 500 pixels from the north-west, 16-bit grey in decimetres, 0 where
there is no data. Only tiles that are new or changed since the last run are
fetched (swisstopo renews about a sixth of the country a year), so run it
once a year. With tile names as arguments (e.g. 2600-1198) only those.
Source: © swisstopo (free geodata, OGD).
"""
import json
import os
import re
import shutil
import sys
import tempfile
import urllib.request

from osgeo import gdal

gdal.UseExceptions()

COLLECTION = "https://data.geo.admin.ch/api/stac/v0.9/collections/ch.swisstopo.swissalti3d/items?limit=100"
OUT = "/data/alti"
INDEX = os.path.join(OUT, "index.json")  # {tile: "item id updated"} of the PNGs written
USER_AGENT = "alvyo-data-import (+https://github.com/tellbow/alvyo)"
ITEM = re.compile(r"swissalti3d_(\d{4})_(\d{4}-\d{4})$")

gdal.SetConfigOption("GDAL_PAM_ENABLED", "NO")  # no .aux.xml next to the PNGs


def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)


def newest():
    """{tile: (version, URL of its 2 m GeoTIFF)} of each tile's newest year."""
    found = {}
    url = COLLECTION
    while url:
        page = get(url)
        for f in page["features"]:
            m = ITEM.match(f["id"])
            tif = [a["href"] for k, a in f["assets"].items() if k.endswith("_2_2056_5728.tif")]
            if not m or not tif:
                continue
            year, tile = m.groups()
            if tile not in found or year > found[tile][0][:4]:
                found[tile] = (f"{year} {f['properties']['updated']}", tif[0])
        url = next((link["href"] for link in page["links"] if link["rel"] == "next"), None)
    return found


def convert(url, tile):
    # Downloaded in one request: GDAL reading it over HTTP asks for each
    # block separately (3 s a tile instead of well under 1 s).
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with tempfile.NamedTemporaryFile(suffix=".tif") as tif:
        with urllib.request.urlopen(req, timeout=60) as r:
            shutil.copyfileobj(r, tif)
        tif.flush()
        tmp = os.path.join(OUT, f".{tile}.png")
        # No data (-9999) clamps to 0. Not marked as no data in the PNG: a
        # transparent grey makes Go decode it as colour.
        gdal.Translate(tmp, tif.name, format="PNG", outputType=gdal.GDT_UInt16, noData="none",
                       scaleParams=[[0, 6553.5, 0, 65535]], creationOptions=["ZLEVEL=9"])
    os.replace(tmp, os.path.join(OUT, f"{tile}.png"))


def main():
    os.makedirs(OUT, exist_ok=True)
    try:
        with open(INDEX) as f:
            done = json.load(f)
    except FileNotFoundError:
        done = {}
    tiles = newest()
    if len(sys.argv) > 1:
        tiles = {t: tiles[t] for t in sys.argv[1:] if t in tiles}
    todo = [t for t, (version, _) in sorted(tiles.items()) if done.get(t) != version]
    print(f"{len(tiles)} tiles, {len(todo)} new or changed", flush=True)
    for i, t in enumerate(todo, 1):
        version, url = tiles[t]
        convert(url, t)
        done[t] = version
        if i % 500 == 0 or i == len(todo):
            # Kept along the way, so an interrupted run goes on from here.
            with open(INDEX + ".tmp", "w") as f:
                json.dump(done, f)
            os.replace(INDEX + ".tmp", INDEX)
            print(f"{i}/{len(todo)}", flush=True)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Snow on the map: the daily gap-filled fractional snow cover of the
Copernicus Land Monitoring Service (HR-WSI GFSC, 60 m, Sentinel-2 with
Sentinel-1 filling the cloud gaps) over Switzerland and 15 km around, as
coloured PNG tiles in Web Mercator (zoom 6-11), into snow_tiles. Run daily;
a day is converted once, the day before is then removed. Generated using
European Union's Copernicus Land Monitoring Service information (CLMS data
policy). Needs PG* environment variables for the target database.
"""
import math
import os
import re
import sys
import tempfile
import urllib.request
import warnings
from datetime import date, timedelta

import numpy as np
import psycopg
from osgeo import gdal, ogr, osr

gdal.UseExceptions()

# EEA's public bucket (read without keys).
BUCKET = "https://s3.WAW3-2.cloudferro.com/HRWSI"
# The MGRS tiles that cover Switzerland and 15 km around.
TILES = ["31TGL", "31TGM", "32TLR", "32TLS", "32TLT", "32TMR", "32TMS", "32TMT", "32TNR", "32TNS", "32TNT"]
BORDER = os.path.join(os.path.dirname(os.path.abspath(__file__)), "border.geojson")
# The products of the last days are looked for, newest first.
DAYS_BACK = 6
MINZOOM, MAXZOOM = 6, 11
# Snow cover in % from which a colour starts; must match api/internal/snow.
LEVELS = [15, 50, 90]
COLOURS = [(198, 219, 239), (107, 174, 214), (33, 113, 181)]
ALPHA = 170
# The GF layer: 0-100 % snow; 205 cloud or no observation, 210 water,
# 255 no data.
SNOW_MAX = 100
EARTH = 2 * math.pi * 6378137.0


def get(url):
    with urllib.request.urlopen(url, timeout=60) as r:
        return r.read()


def listing(prefix):
    """The bucket's sub-folders under prefix (one level)."""
    xml = get(f"{BUCKET}?list-type=2&delimiter=/&max-keys=1000&prefix={prefix}").decode()
    return [p for p in re.findall(r"<Prefix>([^<]*)</Prefix>", xml) if p != prefix]


def products(day):
    """{tile: URL of its GF layer} for day, or None while a tile is missing."""
    found = {}
    for tile in TILES:
        dirs = listing(f"GFSC/{tile}/{day:%Y/%m/%d}/")
        if not dirs:
            return None
        name = dirs[-1].rstrip("/").rsplit("/", 1)[-1]  # the newest version
        found[tile] = f"{BUCKET}/{dirs[-1]}{name}_GF.tif"
    return found


def newest():
    """The newest day with all tiles, and their GF layers."""
    today = date.today()
    for back in range(1, DAYS_BACK + 1):
        day = today - timedelta(days=back)
        if (urls := products(day)) is not None:
            return day, urls
    return None, {}


def snow_only(url):
    """A tile's GF layer with all but snow cover (0-100 %) as no data."""
    src = gdal.Open("/vsicurl/" + url)
    a = src.GetRasterBand(1).ReadAsArray()
    a[a > SNOW_MAX] = 255
    mem = gdal.GetDriverByName("MEM").Create("", src.RasterXSize, src.RasterYSize, 1, gdal.GDT_Byte)
    mem.SetGeoTransform(src.GetGeoTransform())
    mem.SetProjection(src.GetProjection())
    band = mem.GetRasterBand(1)
    band.SetNoDataValue(255)
    band.WriteArray(a)
    return mem


def tile_range(z):
    """The tiles at zoom z that cover the border's area: x0, y0, x1, y1."""
    ds = ogr.Open(BORDER)
    west, east, south, north = ds.GetLayer().GetExtent()
    n = 2 ** z

    def tx(lon):
        return int((lon + 180) / 360 * n)

    def ty(lat):
        r = math.radians(lat)
        return int((1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2 * n)

    return tx(west), ty(north), tx(east), ty(south)


def mosaic(sources):
    """Snow cover in % at MAXZOOM over its tiles (NaN: none known), and the
    tiles' range."""
    x0, y0, x1, y1 = tile_range(MAXZOOM)
    size = EARTH / 2 ** MAXZOOM
    left, top = -EARTH / 2 + x0 * size, EARTH / 2 - y0 * size
    w, h = (x1 - x0 + 1) * 256, (y1 - y0 + 1) * 256
    merc = osr.SpatialReference()
    merc.ImportFromEPSG(3857)
    out = gdal.Warp("", sources, format="MEM", dstSRS=merc.ExportToWkt(),
                    outputBounds=(left, top - h * size / 256, left + w * size / 256, top), width=w, height=h,
                    resampleAlg="average", srcNodata=255, dstNodata=255, outputType=gdal.GDT_Byte,
                    cutlineDSName=BORDER)
    a = out.GetRasterBand(1).ReadAsArray().astype(np.float32)
    a[a > SNOW_MAX] = np.nan
    return a, (x0, y0)


def halve(a):
    """The next zoom out: the mean of each 2×2 block, NaN where none is known."""
    h, w = a.shape
    blocks = a[: h - h % 2, : w - w % 2].reshape(h // 2, 2, w // 2, 2)
    with warnings.catch_warnings():
        warnings.simplefilter("ignore", RuntimeWarning)  # blocks without any
        return np.nanmean(blocks, axis=(1, 3))


def png(idx):
    """A paletted PNG of colour indices (0: transparent)."""
    mem = gdal.GetDriverByName("MEM").Create("", idx.shape[1], idx.shape[0], 1, gdal.GDT_Byte)
    band = mem.GetRasterBand(1)
    band.WriteArray(idx)
    ct = gdal.ColorTable()
    ct.SetColorEntry(0, (0, 0, 0, 0))
    for i, c in enumerate(COLOURS, 1):
        ct.SetColorEntry(i, (*c, ALPHA))
    band.SetRasterColorTable(ct)
    with tempfile.NamedTemporaryFile(suffix=".png") as f:
        gdal.GetDriverByName("PNG").CreateCopy(f.name, mem, options=["ZLEVEL=9"])
        return open(f.name, "rb").read()


def tiles(a, origin):
    """(z, x, y, PNG) of every tile with snow, from MAXZOOM out to MINZOOM."""
    x0, y0 = origin
    for z in range(MAXZOOM, MINZOOM - 1, -1):
        idx = np.digitize(np.nan_to_num(a, nan=0), LEVELS).astype(np.uint8)
        for ty in range(idx.shape[0] // 256):
            for tx in range(idx.shape[1] // 256):
                t = idx[ty * 256:(ty + 1) * 256, tx * 256:(tx + 1) * 256]
                if t.any():
                    yield z, x0 + tx, y0 + ty, png(t)
        # One zoom out: the range must start on an even tile.
        if x0 % 2:
            a = np.pad(a, ((0, 0), (256, 0)), constant_values=np.nan)
            x0 -= 1
        if y0 % 2:
            a = np.pad(a, ((256, 0), (0, 0)), constant_values=np.nan)
            y0 -= 1
        if a.shape[1] % 512:
            a = np.pad(a, ((0, 0), (0, 256)), constant_values=np.nan)
        if a.shape[0] % 512:
            a = np.pad(a, ((0, 256), (0, 0)), constant_values=np.nan)
        a, x0, y0 = halve(a), x0 // 2, y0 // 2


def main():
    with psycopg.connect() as db:
        day, urls = newest()
        if day is None:
            print(f"snow: no day with all {len(TILES)} tiles in the last {DAYS_BACK} days", file=sys.stderr)
            sys.exit(1)
        if db.execute("SELECT 1 FROM snow_days WHERE day = %s", (day,)).fetchone():
            print(f"snow: {day} already there")
            return
        a, origin = mosaic([snow_only(u) for u in urls.values()])
        db.execute("INSERT INTO snow_days (day) VALUES (%s)", (day,))
        n = 0
        for z, x, y, img in tiles(a, origin):
            db.execute("INSERT INTO snow_tiles (day, z, x, y, png) VALUES (%s, %s, %s, %s, %s)", (day, z, x, y, img))
            n += 1
        db.execute("DELETE FROM snow_days WHERE day <> %s", (day,))
        db.commit()
        print(f"snow: {day}, {n} tiles")


if __name__ == "__main__":
    main()

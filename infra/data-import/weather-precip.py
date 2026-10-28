#!/usr/bin/env python3
"""Rain on the map: MeteoSwiss's radar of the last hour (every 5 minutes)
and the ICON-CH1 forecast of the next 12 hours (hourly), as coloured PNG
pictures in Web Mercator, into precip_frames. Run every 5 minutes; a
forecast run is converted once. Data © MeteoSwiss (CC-BY, open data).
Needs PG* environment variables for the target database.
"""
import io
import json
import math
import re
import sys
import tempfile
import urllib.request
from datetime import datetime, timedelta, timezone

import eccodes
import h5py
import numpy as np
import psycopg
from osgeo import gdal, osr
from scipy.spatial import cKDTree

gdal.UseExceptions()

STAC = "https://data.geo.admin.ch/api/stac/v1"
RADAR = "ch.meteoschweiz.ogd-radar-precip"
ICON = "ch.meteoschweiz.ogd-forecasting-icon-ch1"
PAST = timedelta(hours=1)
AHEAD = 12  # hours

# The radar's area in Web Mercator, about 1.4 km pixels (1 km at 46.5°N).
WEST, SOUTH, EAST, NORTH = 2.689, 43.619, 12.462, 49.374
RES = 1400.0

# Rain in mm/h from which a colour starts; must match api/internal/precip.
LEVELS = [0.1, 0.5, 1, 2, 4, 7, 10, 20, 40]
COLOURS = [
    (166, 219, 247), (95, 170, 240), (40, 110, 230), (20, 60, 200), (60, 20, 170),
    (140, 40, 200), (230, 140, 30), (220, 30, 30), (150, 0, 90),
]
ALPHA = 200


def get(url):
    with urllib.request.urlopen(url, timeout=60) as r:
        return r.read()


def merc(lon, lat):
    x = math.radians(lon) * 6378137.0
    y = math.log(math.tan(math.pi / 4 + math.radians(lat) / 2)) * 6378137.0
    return x, y


def grid():
    """The Web Mercator raster: geotransform, width, height."""
    x0, y0 = merc(WEST, NORTH)
    x1, y1 = merc(EAST, SOUTH)
    w, h = round((x1 - x0) / RES), round((y0 - y1) / RES)
    return (x0, RES, 0, y0, 0, -RES), w, h


def png(rate):
    """A paletted PNG of rain rates (mm/h, NaN for none)."""
    idx = np.digitize(np.nan_to_num(rate, nan=0), LEVELS).astype(np.uint8)
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


def merc_srs():
    s = osr.SpatialReference()
    s.ImportFromEPSG(3857)
    return s


def radar_png(data):
    """An ODIM HDF5 radar composite (rain rate) warped to the raster."""
    with h5py.File(io.BytesIO(data)) as f:
        what = f["dataset1/data1/what"].attrs
        rate = f["dataset1/data1/data"][:] * what["gain"] + what["offset"]
        where = dict(f["where"].attrs)
        src_srs = osr.SpatialReference()
        src_srs.ImportFromProj4(where["projdef"].decode() if isinstance(where["projdef"], bytes) else where["projdef"])
        src_srs.SetAxisMappingStrategy(osr.OAMS_TRADITIONAL_GIS_ORDER)
        wgs = osr.SpatialReference()
        wgs.ImportFromEPSG(4326)
        wgs.SetAxisMappingStrategy(osr.OAMS_TRADITIONAL_GIS_ORDER)
        # The corners are those of the outer pixels: round to the 1 km grid.
        x, y, _ = osr.CoordinateTransformation(wgs, src_srs).TransformPoint(float(where["UL_lon"]), float(where["UL_lat"]))
        x0, y0 = round(x / 1000) * 1000, round(y / 1000) * 1000
        h, w = rate.shape
    rate = rate.astype(np.float32)
    rate[~np.isfinite(rate)] = 0
    src = gdal.GetDriverByName("MEM").Create("", w, h, 1, gdal.GDT_Float32)
    src.SetGeoTransform((x0, float(where["xscale"]), 0, y0, 0, -float(where["yscale"])))
    src.SetProjection(src_srs.ExportToWkt())
    src.GetRasterBand(1).WriteArray(rate)
    gt, gw, gh = grid()
    out = gdal.Warp("", src, format="MEM", dstSRS=merc_srs().ExportToWkt(), outputBounds=(gt[0], gt[3] - gh * RES, gt[0] + gw * RES, gt[3]),
                    width=gw, height=gh, resampleAlg="near", dstNodata=0)
    return png(out.GetRasterBand(1).ReadAsArray())


def radar_frames():
    """The radar pictures of the last hour: [(time, url)], oldest first."""
    now = datetime.now(timezone.utc)
    found = []
    for day in (now - timedelta(days=1), now):
        try:
            item = json.loads(get(f"{STAC}/collections/{RADAR}/items/{day:%Y%m%d}-ch"))
        except urllib.error.HTTPError as e:
            if e.code == 404:
                continue
            raise
        for name, a in item["assets"].items():
            m = re.fullmatch(r"rzc(\d{2})(\d{3})(\d{4})\w*\.\d+\.h5", name)
            if m:
                t = datetime.strptime(m.group(1) + m.group(2) + m.group(3), "%y%j%H%M").replace(tzinfo=timezone.utc)
                found.append((t, a["href"]))
    found.sort()
    if not found:
        return []
    newest = found[-1][0]
    return [(t, u) for t, u in found if t > newest - PAST]


def icon_run(now):
    """The newest ICON-CH1 run with the hours needed: (run, {hour: url})."""
    first = now.replace(minute=0, second=0, microsecond=0)
    run = first - timedelta(hours=first.hour % 3)
    for _ in range(4):
        body = json.dumps({"collections": [ICON], "forecast:reference_datetime": run.strftime("%Y-%m-%dT%H:%M:%SZ"),
                           "forecast:variable": "TOT_PREC", "forecast:perturbed": False, "limit": 100}).encode()
        req = urllib.request.Request(f"{STAC}/search", data=body, headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=60) as r:
            items = json.load(r)["features"]
        hours = {}
        for it in items:
            if not it["assets"]:  # listed before its file is up
                continue
            m = re.fullmatch(r"P(\d+)DT(\d+)H.*", it["properties"]["forecast:horizon"])
            hours[int(m.group(1)) * 24 + int(m.group(2))] = next(iter(it["assets"].values()))["href"]
        offset = int((first - run).total_seconds()) // 3600
        need = range(offset, offset + AHEAD + 1)
        if all(h in hours for h in need):
            return run, {h: hours[h] for h in need}
        run -= timedelta(hours=3)
    return None, {}


def grib_values(data, short):
    """The values of the first message named short in GRIB data."""
    with tempfile.NamedTemporaryFile() as f:
        f.write(data)
        f.flush()
        with open(f.name, "rb") as g:
            while (h := eccodes.codes_grib_new_from_file(g)) is not None:
                try:
                    if eccodes.codes_get(h, "shortName") == short:
                        return eccodes.codes_get_values(h)
                finally:
                    eccodes.codes_release(h)
    raise ValueError(f"no {short}")


def icon_lookup():
    """For each raster pixel the nearest ICON-CH1 cell, -1 outside its area."""
    consts = json.loads(get(f"{STAC}/collections/{ICON}"))["assets"]["horizontal_constants_icon-ch1-eps.grib2"]["href"]
    data = get(consts)
    lon, lat = np.radians(grib_values(data, "tlon")), np.radians(grib_values(data, "tlat"))
    cells = np.column_stack([np.cos(lat) * np.cos(lon), np.cos(lat) * np.sin(lon), np.sin(lat)])
    gt, w, h = grid()
    xs = gt[0] + (np.arange(w) + 0.5) * RES
    ys = gt[3] - (np.arange(h) + 0.5) * RES
    px, py = np.meshgrid(xs, ys)
    plon = px / 6378137.0
    plat = 2 * np.arctan(np.exp(py / 6378137.0)) - math.pi / 2
    pts = np.column_stack([(np.cos(plat) * np.cos(plon)).ravel(), (np.cos(plat) * np.sin(plon)).ravel(), np.sin(plat).ravel()])
    dist, idx = cKDTree(cells).query(pts)
    idx[dist * 6371 > 2] = -1  # more than 2 km from a cell: outside the model
    return idx.reshape(h, w)


def forecast_pngs(run, urls):
    """{valid time: PNG} of the rain in each hour (mm in the hour = mm/h)."""
    lookup = icon_lookup()
    hours = sorted(urls)
    total = {h: grib_values(get(urls[h]), "tp") for h in hours}
    out = {}
    for prev, h in zip(hours, hours[1:]):
        rain = np.clip(total[h] - total[prev], 0, None)
        img = np.where(lookup >= 0, rain[np.maximum(lookup, 0)], np.nan)
        out[run + timedelta(hours=h)] = png(img)
    return out


def main():
    bounds = (WEST, SOUTH, EAST, NORTH)
    with psycopg.connect() as db:
        frames = radar_frames()
        have = {r[0] for r in db.execute("SELECT valid_at FROM precip_frames WHERE kind = 'radar'")}
        for t, url in frames:
            if t not in have:
                db.execute("""INSERT INTO precip_frames (kind, valid_at, png, west, south, east, north)
                    VALUES ('radar', %s, %s, %s, %s, %s, %s) ON CONFLICT DO NOTHING""", (t, radar_png(get(url)), *bounds))
        if frames:
            db.execute("DELETE FROM precip_frames WHERE kind = 'radar' AND valid_at <= %s", (frames[-1][0] - PAST,))
        db.commit()
        print(f"radar: {len(frames)} pictures, {sum(t not in have for t, _ in frames)} new, newest {frames[-1][0] if frames else '-'}")

        now = datetime.now(timezone.utc)
        run, urls = icon_run(now)
        stored = db.execute("SELECT max(run_at) FROM precip_frames WHERE kind = 'forecast'").fetchone()[0]
        if run is None:
            print("forecast: no complete run", file=sys.stderr)
        elif stored != run:
            pngs = forecast_pngs(run, urls)
            for t, img in pngs.items():
                db.execute("""INSERT INTO precip_frames (kind, valid_at, run_at, png, west, south, east, north)
                    VALUES ('forecast', %s, %s, %s, %s, %s, %s, %s)
                    ON CONFLICT (kind, valid_at) DO UPDATE SET run_at = excluded.run_at, png = excluded.png, created_at = now()""",
                           (t, run, img, *bounds))
            print(f"forecast: run {run:%Y-%m-%d %H:%M}Z, {len(pngs)} hours")
        else:
            print(f"forecast: run {run:%Y-%m-%d %H:%M}Z already there")
        db.execute("DELETE FROM precip_frames WHERE kind = 'forecast' AND valid_at < %s", (now - timedelta(hours=1),))
        db.commit()


if __name__ == "__main__":
    main()

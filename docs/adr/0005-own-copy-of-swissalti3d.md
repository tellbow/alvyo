# ADR-0005: Our own copy of swissALTI3D, geo.admin beyond the border

Status: accepted (2026-10-19)

## Decision

Heights come from swissALTI3D kept on our own disk: the 2 m tiles of
swisstopo's download service, one 16-bit PNG per km² in decimetres
(`infra/data-import/swissalti3d.py`, about 6.3 GB for Switzerland and
Liechtenstein), sampled bilinearly by `elevation.SwissALTI3D`. A line with a
point outside the tiles (beyond the border, or before the first import)
goes as a whole to geo.admin's profile service as before (`elevation.Fallback`,
ADR-0002), which has DHM25 there. The import runs monthly and fetches only
tiles that are new or changed; swisstopo renews about a sixth of the country
a year (7000–8300 tiles).

## Why

geo.admin's profile service answered 502/503 on and off on 2026-10-19, and
without heights nothing can be planned (feedback issue 22). The data is the
same: geo.admin's COMB model is swissALTI3D at 2 m in Switzerland. Compared
on the 28 calibration stages (`go run ./swiss/cmd/calibrate -swissalti3d DIR`,
2026-10-19):

- heights: 0.12 m apart on average, 95 % of points within 0.38 m; a few
  single points per stage differ by up to 11 m (spikes in our tiles, cause
  not known);
- against the official values, time within ±10 % 56/56 (geo.admin 46/46 on
  the 23 stages it answered), mean +0.1 % (geo.admin +0.3 %); between the
  two sources the hiking time differs by 0.2 % on average, 0.5 % at most.

The calibration (`docs/hiking-time.md`) stays as it is. Sampling is local:
71 577 points in 2.2 s including decoding 564 tiles.

Licence: swisstopo free geodata (OGD): use, processing, commercial use and
distribution allowed, source mandatory («© swisstopo», shown already). The
first download is about 48 GB, fetched one tile after the other.

## Consequences

- A volume of its own (10 GiB, ReadWriteOnce) that the API mounts read-only,
  not the shared `geodata` volume: the API does not depend on its NFS
  share-manager to start, and the heights change by about 1 GB a year
  instead of 6 GB a week. The import must run on the API's node.
- Mapterhorn (named in ADR-0002 as the alternative) is not needed for
  Switzerland; it would be one for the strip beyond the border.

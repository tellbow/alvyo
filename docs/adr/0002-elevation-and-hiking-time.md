# ADR-0002: swissALTI3D elevation via geo.admin and the SchweizMobil hiking time

Status: accepted (2026-09-22); the heights come from our own copy of
swissALTI3D since ADR-0005, geo.admin only beyond the border

## Decision

- Elevation for every route vertex comes from the geo.admin.ch profile service
  (`api3.geo.admin.ch/rest/services/profile.json`, COMB model = swissALTI3D
  where available, DHM25 elsewhere), implemented in `swiss/elevation`. It is
  sampled once per leg and stored with the route (LineStringZ).
- Hiking time uses the SchweizMobil variant of the Schweizer Wanderwege formula
  exactly as map.geo.admin.ch does (`swiss/hikingtime`, golden-tested against
  the original JavaScript), on a profile resampled every 10 m (`swiss/stats`).

## Why

Users compare our numbers with the swisstopo app, map.geo.admin.ch and the
yellow signposts, which use the same DEM and formula. GraphHopper 11 only
offers 30–90 m global DEMs, which are poor in the Alps.

## Service constraints (verified)

- Input only in LV95/LV03 (`sr=2056`), so coordinates are converted with
  `swiss/lv95` (swisstopo approximate formulas, < 1.5 m vs REFRAME).
- At most 5000 input coordinates and `nb_points` ≤ 5000 per request; the
  client sends chunks of 4000 vertices with `distinct_points=true`.
- No data far outside Switzerland (empty response → `ErrNoCoverage`).

A self-hosted PMTiles DEM (Mapterhorn) can replace the service behind the same
`elevation.Sampler` interface if availability or volume becomes an issue.

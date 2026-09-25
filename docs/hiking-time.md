# Hiking time and ascent: calibration

Alvyo shows the Swiss hiking time of the yellow signposts: the SchweizMobil
variant of the Schweizer Wanderwege formula, as in map.geo.admin.ch
(`swiss/hikingtime`, golden-tested against the original JavaScript). The
formula gives minutes per horizontal kilometre from the slope; the result
depends on how finely the elevation profile is sampled and how ascent is
counted. This page checks both against official figures.

## Reference data

The official Wanderland stages of ASTRA and SchweizMobil
([ch.astra.wanderland](https://data.geo.admin.ch/api/stac/v1/collections/ch.astra.wanderland),
opendata.swiss, open use with source) come with the line of every stage and
its distance, ascent, descent and hiking time in both directions, in minutes.
`swiss/testdata/reference_stages.json` holds 28 of them: Via Alpina stages
1–10 (alpine) and stages 1–3 of the national routes 2–7 (Jura, Pre-Alps,
Mittelland, Engadin). `swiss/testdata/make_reference_stages.py` rebuilds it.

Two checks on the official data itself (their own elevations, not ours):

- Our formula applied to the official 3D lines reproduces the official times:
  mean +0.3 % at the line's own vertices, all 28 within ±10 %. SchweizMobil
  computes on the vertices of the line, like we do on ours.
- Official ascent is the sum of every climb along the vertices, without a
  noise threshold (reproduced exactly).

## Our pipeline

What the API does for every planned or imported leg: densify the line to
≤ 20 m, sample swissALTI3D through the geo.admin profile service, resample
the profile every `stats.ProfileStep` metres, count ascent with
`stats.AscentThreshold`, apply the formula. Run on the official lines of the
28 stages (both directions for time, 56 comparisons):

| Step | Ascent threshold | Time within ±10 % | Time mean | Time worst | Ascent within ±10 % | Ascent mean | Ascent worst | Descent mean |
|---|---|---|---|---|---|---|---|---|
| 10 m (current) | 0 m | 56/56 | +0.3 % | -9.1 % | 27/28 | +0.8 % | +12.7 % | +0.6 % |
| 10 m | 1 m | 56/56 | +0.3 % | -9.1 % | 28/28 | -1.3 % | -9.6 % | -1.8 % |
| 10 m | 2 m | 56/56 | +0.3 % | -9.1 % | 27/28 | -3.0 % | -16.0 % | -3.6 % |
| 10 m | 3 m | 56/56 | +0.3 % | -9.1 % | 27/28 | -4.0 % | -20.0 % | -4.8 % |
| 20 m | 0 m | 55/56 | -0.7 % | -10.7 % | 28/28 | -1.1 % | +8.9 % | -1.5 % |
| 20 m | 1 m | 55/56 | -0.7 % | -10.7 % | 27/28 | -2.5 % | -12.0 % | -3.2 % |
| 20 m | 2 m | 55/56 | -0.7 % | -10.7 % | 27/28 | -3.8 % | -17.7 % | -4.6 % |
| 20 m | 3 m | 55/56 | -0.7 % | -10.7 % | 26/28 | -4.7 % | -20.7 % | -5.6 % |
| 25 m | 0 m | 55/56 | -1.1 % | -11.0 % | 28/28 | -2.0 % | -8.4 % | -2.5 % |
| 25 m | 1 m | 55/56 | -1.1 % | -11.0 % | 27/28 | -3.2 % | -13.2 % | -3.9 % |
| 25 m | 2 m | 55/56 | -1.1 % | -11.0 % | 26/28 | -4.4 % | -20.4 % | -5.2 % |
| 25 m | 3 m | 55/56 | -1.1 % | -11.0 % | 25/28 | -5.3 % | -25.5 % | -6.3 % |
| 50 m | 0 m | 55/56 | -2.2 % | -12.8 % | 25/28 | -4.8 % | -18.2 % | -5.8 % |
| 50 m | 1 m | 55/56 | -2.2 % | -12.8 % | 25/28 | -5.5 % | -21.7 % | -6.6 % |
| 50 m | 2 m | 55/56 | -2.2 % | -12.8 % | 24/28 | -6.3 % | -27.1 % | -7.5 % |
| 50 m | 3 m | 55/56 | -2.2 % | -12.8 % | 22/28 | -7.2 % | -31.8 % | -8.6 % |

**Decision:** keep the 10 m step (every time within ±10 %, mean +0.3 %) and
count every climb (threshold 0), as the official figures do: +0.8 % on
average, 27 of 28 stages within ±10 %. A threshold only lowers the average
(3 m: −4.0 %, −20 % at worst); 1 m
brings the last stage within ±10 % but is −1.3 % on average. (Measured with
the hysteresis counting a climb up to its peak, since 2026-09-24; before, a
climb was cut short at each turn and 3 m looked like −9 %.)

Per stage (Δ = deviation from the official value):

| Stage | From – to | km | Δ km | ↑ m | Δ ↑ | Time | Δ time | Δ way back |
|---|---|---|---|---|---|---|---|---|
| 1.01 | Vorder Bärgälla – Sargans | 28.0 | +0.0 % | 476 | +12.7 % | 7 h 28 | +3.4 % | +3.3 % |
| 1.02 | Sargans – Weisstannen | 13.2 | +0.0 % | 818 | -1.7 % | 4 h 16 | -1.2 % | -1.2 % |
| 1.03 | Weisstannen – Elm Station | 22.3 | +0.3 % | 1420 | -1.0 % | 7 h 50 | +0.2 % | -0.4 % |
| 1.04 | Elm Station – Linthal | 24.8 | +0.1 % | 1654 | -1.0 % | 9 h 09 | +1.0 % | +1.0 % |
| 1.05 | Linthal – _VZ Urnerboden | 15.9 | +0.0 % | 1078 | -1.0 % | 5 h 20 | -0.2 % | +0.5 % |
| 1.06 | _VZ Urnerboden – Altdorf Tellspielhaus | 27.3 | -0.0 % | 1025 | -0.4 % | 8 h 21 | +0.0 % | +0.1 % |
| 1.07 | Altdorf Tellspielhaus – Engelberg | 29.5 | +0.1 % | 2056 | -0.4 % | 10 h 41 | +1.0 % | +0.1 % |
| 1.08 | Engelberg – Engstlenalp | 11.8 | +0.1 % | 1275 | -0.3 % | 4 h 56 | +0.4 % | -0.2 % |
| 1.09 | Engstlenalp – Meiringen | 22.2 | +0.1 % | 731 | +0.5 % | 6 h 53 | +0.2 % | -0.3 % |
| 1.10 | Meiringen – Grindelwald Bhf. | 22.9 | +0.1 % | 1535 | -0.4 % | 7 h 55 | -0.3 % | -0.4 % |
| 2.01 | Porrentruy gare – St-Ursanne centre vieille ville | 16.7 | -0.0 % | 610 | -0.4 % | 4 h 45 | -0.5 % | -0.2 % |
| 2.02 | St-Ursanne centre vieille ville – Soubey | 15.3 | -0.1 % | 258 | +1.4 % | 3 h 50 | -0.1 % | +0.1 % |
| 2.03 | Soubey – 4956 | 12.5 | -0.0 % | 793 | -0.7 % | 4 h 07 | +0.2 % | -0.1 % |
| 3.01 | Rorschach Hafen – Trogen Landsgemeindeplatz | 19.5 | -0.0 % | 1211 | +0.4 % | 6 h 16 | +0.9 % | +0.6 % |
| 3.02 | Trogen Landsgemeindeplatz – Tourist Information | 13.2 | +0.1 % | 568 | +0.4 % | 3 h 58 | -0.5 % | -0.5 % |
| 3.03 | Tourist Information – Schwägalp | 15.6 | +0.0 % | 1149 | -0.6 % | 5 h 29 | -0.8 % | -0.6 % |
| 4.01 | Rorschach Hafen – Platz Herisau Zentrum | 25.9 | -0.0 % | 804 | +9.0 % | 6 h 52 | +3.6 % | +4.0 % |
| 4.02 | Platz Herisau Zentrum – Wattwil | 23.7 | -0.0 % | 1009 | +1.2 % | 7 h 07 | +0.4 % | +0.5 % |
| 4.03 | Wattwil – Rapperswil | 27.9 | -0.1 % | 744 | +7.4 % | 7 h 23 | +2.8 % | +2.7 % |
| 5.01 | Dielsdorf – Brugg | 24.9 | -0.0 % | 926 | -0.8 % | 7 h 09 | +1.1 % | +0.5 % |
| 5.02 | Brugg – Staffelegg | 17.1 | -0.1 % | 609 | +0.8 % | 4 h 38 | +0.3 % | +0.4 % |
| 5.03 | Staffelegg – Hauenstein | 19.8 | -0.1 % | 895 | -0.5 % | 5 h 54 | -0.4 % | -0.5 % |
| 6.01 | Corviglia St. Moritz – Chamanna Jenatsch | 11.1 | +0.4 % | 983 | -2.8 % | 5 h 02 | -9.1 % | +0.6 % |
| 6.02 | Chamanna Jenatsch – Tigias (Alp Flix) | 13.6 | +0.4 % | 766 | -4.2 % | 5 h 11 | -1.4 % | -1.0 % |
| 6.03 | Tigias (Alp Flix) – Savognin Grava | 20.0 | +0.3 % | 935 | -2.8 % | 6 h 43 | -1.0 % | -0.7 % |
| 7.01 | Basel SBB – Liestal | 19.8 | -0.0 % | 599 | +1.8 % | 5 h 24 | +1.0 % | +1.2 % |
| 7.02 | Liestal – Läufelfingen Bahnhof | 20.5 | -0.1 % | 659 | +2.7 % | 5 h 34 | +1.5 % | +0.7 % |
| 7.03 | Läufelfingen Bahnhof – Olten | 7.7 | -0.0 % | 165 | +3.4 % | 1 h 59 | +2.5 % | +0.3 % |

The one larger time deviation (Corviglia – Chamanna Jenatsch, −9 % one way)
has slopes over 40 %, where the formula switches to its linear part.

## Planned like a person would

The same stages planned through GraphHopper (profile hike, alpine where hike
finds no way), with a point of the official line every 5 km – about the
"four clicks" of the M1 acceptance test:

| Stage | Points | Δ km | Δ ↑ | Δ time |
|---|---|---|---|---|
| 1.01 | 7 | -10.9 % | +7.0 % | -6.2 % |
| 1.02 | 4 | +1.1 % | +10.4 % | +4.7 % |
| 1.03 | 5 | -1.6 % | -2.4 % | -1.7 % |
| 1.04 | 6 | -4.0 % | -1.1 % | -0.3 % |
| 1.05 | 4 | -5.5 % | -1.4 % | -2.8 % |
| 1.06 | 6 | -7.3 % | -14.8 % | -9.2 % |
| 1.07 | 7 | -2.4 % | -2.3 % | -1.3 % |
| 1.08 | 3 | -0.8 % | -0.4 % | +0.2 % |
| 1.09 | 5 | -2.3 % | -2.1 % | -1.9 % |
| 1.10 | 6 | -4.5 % | -1.8 % | -4.3 % |
| 2.01 | 4 | -2.6 % | -1.1 % | -2.7 % |
| 2.02 | 4 | -0.4 % | -0.2 % | -0.3 % |
| 2.03 | 3 | -0.2 % | +0.6 % | +0.3 % |
| 3.01 | 5 | -10.1 % | -4.1 % | -7.2 % |
| 3.02 | 4 | -1.4 % | -0.2 % | -1.2 % |
| 3.03 | 4 | -3.6 % | -1.7 % | -3.4 % |
| 4.01 | 6 | -5.6 % | +3.0 % | -2.1 % |
| 4.02 | 6 | -1.3 % | -1.9 % | -1.9 % |
| 4.03 | 7 | -7.4 % | -10.4 % | -7.3 % |
| 5.01 | 6 | -10.6 % | -3.6 % | -7.8 % |
| 5.02 | 4 | -8.1 % | -5.8 % | -7.3 % |
| 5.03 | 5 | -4.2 % | -2.3 % | -3.6 % |
| 6.01 | 3 | +51.9 % | +4.7 % | +11.2 % |
| 6.02 | 4 | -4.5 % | -4.4 % | -2.9 % |
| 6.03 | 5 | -0.5 % | -0.7 % | +0.1 % |
| 7.01 | 5 | -13.8 % | -13.8 % | -12.9 % |
| 7.02 | 5 | -0.9 % | +3.1 % | +1.0 % |
| 7.03 | 3 | +0.7 % | +5.9 % | +3.7 % |

Distance within ±5 %: 18/28 (mean -2.2 %). Time within ±10 %: 26/28 (mean -2.4 %, worst -12.9 %). Ascent within ±10 %: 24/28 (mean -1.5 %).

Acceptance (M1, item 10: at least 80 % of 20+ stages within ±10 % on time,
none beyond ±20 %) is met both on the official lines (100 %, worst −9.1 %)
and planned (93 %, worst −12.9 %). The planned distances are a little
shorter on average: official routes take detours to viewpoints and villages
that a few planning points do not force. Two outliers:

- Via Alpina 1 (Gaflei – Sargans) comes out 11 % shorter (24.7 instead of
  27.9 km, with both profiles): between the planning points the router finds
  shorter ways than the official route. More planning points follow it.
- Corviglia – Chamanna Jenatsch (+52 % distance): one leg, towards the hut,
  is routed 11.8 instead of 6.1 km with both the hike and the alpine profile.
  The official trail there is apparently missing from, or blocked in, our
  routing graph; not investigated yet.

## Rerun

```sh
cd swiss
go run ./cmd/calibrate -graphhopper http://localhost:8989 > /tmp/report.md
```

Elevations are cached (`-cache`, default in the system temp directory), so
variants run offline after the first time. Without `-graphhopper` only the
official lines are checked.

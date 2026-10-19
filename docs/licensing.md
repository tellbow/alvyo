# Licensing

What Alvyo's own license is, the terms of every outside data source and
service it uses, and where each is credited. Before adding a new API, data
source or dependency: `.claude/rules/licensing.md`. Checked 2026-10-12;
terms change, so check again when a source's use changes.

## Alvyo's code

- **AGPL-3.0-only** (`LICENSE`, ADR-0001). The website links the source of
  the running version on the About page (AGPL §13), the app on «Über
  Alvyo». The repository must be public for that link to work.
- It stays AGPL as long as the API embeds the Rust `heic` decoder
  (`AGPL-3.0-only OR LicenseRef-Imazen-Commercial`, via
  `github.com/gen2brain/heic`); moving to a permissive license would mean
  replacing it (the code that came from wanderer went with the Komoot
  import).
- **Contributions** come under the Contributor License Agreement in
  `CLA.md` (`CONTRIBUTING.md`): it lets the maintainer distribute the app
  through the App Store, whose terms the FSF holds incompatible with the
  (A)GPL for code by others. The app contains no third-party (A)GPL code.
- **Dependencies:** `make licenses` lists the licenses of the Go modules in
  the binaries, the npm packages and the app's Dart packages, and fails on
  one that is neither permissive nor reviewed (`infra/ops/licenses.py`).
  2026-10-12: Go 78 (MIT, BSD, Apache-2.0; freetype under the FreeType
  License, credited in NOTICE), npm 316 (permissive; MPL-2.0 only in the
  build tool lightningcss), Dart 142 (permissive; MPL-2.0 only in Linux
  plugins). Only in tests, so in no binary or app: `pgregory.net/rapid`
  (MPL-2.0, checked 2026-10-19). The fonts are OFL-1.1; the app ships their license texts and
  shows them on its license page with every package's. The Android app
  adds Gradle libraries `make licenses` does not list: MapLibre Native
  (BSD-2-Clause), AndroidX and Google's (Apache-2.0), and Google's
  `desugar_jdk_libs` (parts of OpenJDK, GPL-2.0 with the Classpath
  Exception: allowed in an AGPL app, credited in NOTICE; checked
  2026-10-12 on its Maven POM). The ktlint Gradle plugin (MIT) only builds.
- **Commercial use** is allowed by the AGPL and by every data source below
  except as noted (opentransportdata.swiss above its free quota, geo.admin
  services beyond fair use).

## Data sources and services

| Source | Used for | Terms | Credited |
|---|---|---|---|
| swisstopo: national maps, SWISSIMAGE, base map (vector), swissALTI3D, relief, slopes, swissTLM3D trails, place names | maps, heights (swissALTI3D downloaded and kept as tiles, ADR-0005; checked 2026-10-19), trails, place search | [Free geodata (OGD)](https://www.swisstopo.admin.ch/en/terms-of-use-free-geodata-and-geoservices): commercial use and redistribution allowed, source mandatory («© swisstopo») | every map on the website (attribution control) and in the app (`MapCredit`), print sheet, OG images, GPX metadata, About pages |
| geo.admin.ch services (WMTS, `api3`, vector tiles, `data.geo.admin.ch`) | tiles, profiles, identify, search, downloads | [FSDI terms](https://www.geo.admin.ch/en/general-terms-of-use-fsdi): free with fair use (about 20,000 users a day in a web application is fair use); announce high use to info@geo.admin.ch; offline use through downloads, not the web services | — (the tile cache keeps the load down and sends a User-Agent) |
| ASTRA / SchweizMobil: Wanderland routes, trail closures | official routes, closures, calibration | opendata.swiss «open use, source required» | route pages (`OfficialCredit`), the Wanderland overlay on the website, `MapCredit` in the app when it is on, About pages |
| BAFU and cantons: wildlife rest areas, hunting reserves | protected areas | opendata.swiss «open use, source required» | the overlays (website and app), «Quelle: BAFU / Kantone» under the areas, About pages |
| VBS: shooting notices | notices along the route | opendata.swiss «open use, source required» | About pages |
| MeteoSwiss: local forecast, radar, ICON-CH1, climate normals | weather, rain layer | [CC BY 4.0](https://opendatadocs.meteoswiss.ch/general/terms-of-use), «Source: MeteoSwiss»; no suggestion that MeteoSwiss endorses Alvyo; warnings only unaltered (Alvyo shows none) | weather texts, the rain layer's legend, About pages |
| Copernicus Land Monitoring Service: HR-WSI Gap-filled Fractional Snow Cover ([DOI](https://doi.org/10.2909/832c7297-a20f-4b92-8e32-1e2e1548e642)), checked 2026-10-19 | the snow layer | [CLMS data policy](https://land.copernicus.eu/en/data-policy) (Regulation (EU) 1159/2013): full, open and free, also commercially; inform the public of the source, say that it was changed, no suggestion that the EU endorses Alvyo. Read from EEA's public bucket `s3.WAW3-2.cloudferro.com/HRWSI` without keys | the snow layer's attribution on the website («Generated using European Union's Copernicus Land Monitoring Service information»), its box and `MapCredit` in the app («Copernicus (EU)»), About pages, NOTICE |
| opentransportdata.swiss (OJP) | connections | [Terms](https://opentransportdata.swiss/en/terms-of-use/): cite «opentransportdata.swiss»; keep within the key's quota (higher volumes need a paid contract); misuse blocks the key | under every connection list, About pages |
| BAV: list of stops | stops | OGD, source required | About pages |
| OpenStreetMap (Geofabrik extracts) | routing graph, huts, accommodation, places, points of interest, the peak pack's summits | [ODbL](https://www.openstreetmap.org/copyright); [attribution guidelines](https://osmfoundation.org/wiki/Licence/Attribution_Guidelines): «© OpenStreetMap contributors» linked to /copyright, visible without a tap (may collapse after interaction); databases derived from it and used publicly must be offered under the ODbL — Alvyo's are made by the public scripts in `infra/data-import` | every map on the website (attribution control, linked), `MapCredit` in the app, print sheet (with the address), OG images, GPX metadata, the peak camera, About pages |
| Mapterhorn terrain tiles | 3D terrain, the peak pack's height grid | [attribution](https://mapterhorn.com/attribution); sources per region (Copernicus GLO-30, swissALTI3D, neighbouring countries' models: mostly CC BY 4.0 and open government licences) | the 3D map's attribution, the peak camera, About pages, NOTICE |
| AWS Terrain Tiles (Mapzen, skadi) | heights in the GraphHopper graph (reach areas) | [Mapzen attribution](https://github.com/tilezen/joerd/blob/master/docs/attribution.md): EU-DEM («produced using Copernicus data and information funded by the European Union»), SRTM (USGS) | the reach areas' attribution, About pages, NOTICE |
| Google Analytics | page views | consent before cookies; named in the privacy text | About page (privacy) |
| Google and Apple sign-in | optional login | provider terms; Apple requires Sign in with Apple in the app when another provider is offered there (guideline 4.8), its tokens revoked when an account is deleted (5.1.1(v)), and its button as Apple designs it | privacy text |
| Infomaniak (SMTP) | e-mails | provider terms | privacy text |
| GitHub API | bug reports as issues | issues in a public repository are public: the report form says so | the report form, privacy text |

Komoot: the password-based import through Komoot's unofficial API was
removed on 2026-10-12. Komoot's terms forbid exporting tours other than
with its own export (§1.4) and passing on login data (§12), and its API is
for contracted partners only. Users import Komoot's GPX export instead.

## Operator and privacy

The About page names the operator (`PUBLIC_OPERATOR_NAME`,
`PUBLIC_OPERATOR_ADDRESS`) and contact (`PUBLIC_CONTACT_EMAIL`), as Swiss
data protection law (revDSG Art. 19) asks, and holds the privacy text
(`/about#privacy`), which the app links on its login screen and on «Über
Alvyo» (the App Store's privacy policy URL).

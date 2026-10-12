# Licensing before a new API, data source or dependency

Before code calls a new outside API or service, imports or shows a new data
source (tiles, a dataset, an overlay layer, an elevation model), or adds a
package, check its terms first and tell the user what you found before
building on it. Already reviewed: `docs/licensing.md`.

1. **Find the terms** on the provider's own page (terms of use, license,
   API documentation, attribution page; for geo.admin layers the dataset's
   «Legal restrictions» on geocat.ch). Read them; do not go by memory or a
   third-party summary. Note the date checked and the link.
2. **Answer, with a quote or link for each:**
   - May Alvyo use it at all: without a partner contract or key, for an
     automated service, commercially? An unofficial or reverse-engineered
     API, scraping, or asking users for their password at another service
     is a no (that is why the Komoot import was removed).
   - Attribution: the exact wording, and where it must show (on the map
     without a tap, in the app, on print, in exports).
   - Limits: rate limits, quotas, fair use, caching, offline storage,
     redistribution (offline packs, GPX, the API's own answers).
   - Share-alike or copyleft (ODbL, CC BY-SA, GPL): what it means for the
     databases and files Alvyo derives and serves.
   - Personal data: what leaves Alvyo, to whom and where; it goes into the
     privacy text (`about_privacy*` in `web/messages`).
3. **For a package:** its license must be permissive or compatible with
   AGPL-3.0, and nothing (A)GPL may go into the iOS app (App Store). Run
   `make licenses`; a new non-permissive license goes into `REVIEWED` in
   `infra/ops/licenses.py` only with the reason.
4. **Stop and ask** when the terms forbid the use, are unclear, need a
   contract or payment, or cannot be found. Say so; do not build around it.
5. **When it is fine, credit it everywhere the data shows** (website map
   attribution in `web/src/lib/map/styles.ts`, `MapCredit` in the app,
   print, OG images, exports), and add it in the same commit to `NOTICE`,
   `docs/licensing.md` (the table), the About pages' sources
   (`web/src/lib/about/sources.ts`, `dataSources` in `app/lib/map_credit.dart`)
   and, for a new host, the egress list in `docs/operations.md` and the
   diagram in `docs/architecture.md`.

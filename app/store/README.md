# App Store pictures

The pictures for the App Store product page, one folder per language
(`de/`, `en/`, `fr/`, `it/`). They are not in git (about 24 MB per
language): the scripts below make them.

| File | Where in App Store Connect | Size |
|---|---|---|
| `01-route.jpg` … `06-discover.jpg` | Bildschirmfotos, iPhone with Dynamic Island (medium display) | 1206 × 2622 |
| `header.png` | Kopfzeile (product page header, 21:9) | 3840 × 1646 |
| `search.png` | Suchergebnisse (search result, 3:2) | 3840 × 2560 |

They show the real app and website with the local dev stack: copies of
official routes (Wanderland Schweiz) in a local account «storeshots», the
national map (© swisstopo, also on the header and search result).

## Making them again

After a change to the screens or the texts. Needs the dev stack, the API
and the web dev server (`docs/development.md`), and the iPhone 17 Pro
simulator.

```sh
app/store/seed.sh                          # once: the local account and its routes
app/store/capture.sh                       # the app's states → app/store/work/raw/<language>/
bun app/store/render.mjs                   # headlines, map, header → app/store/<language>/
```

Both take the languages first: `capture.sh fr route,nav` captures only
some states in French (their names are in `screenshots_test.dart`), `bun
app/store/render.mjs fr` makes only the French pictures. `capture.sh`
switches the simulator to each language in turn, logs it out (keychain
reset; the app then follows the simulator's language) and puts it back in
English afterwards. Four languages take about 10 minutes.

The headlines and the header's text, in every language, are in
`render.mjs`. Longer ones are set smaller until they fit.

Apple's rules: <https://developer.apple.com/app-store/asset-best-practices/>
(no prices, URLs, logos or awards; short text in every language; key
content inside the safe area). Before uploading, check the header and
search result in App Store Connect's preview: the safe areas are from
Apple's templates, not from its specification page.

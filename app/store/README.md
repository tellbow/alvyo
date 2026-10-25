# App Store pictures

The pictures for the App Store product page, one folder per language
(`de/`, `en/`, `fr/`, `it/`). They are not in git (about 24 MB per
language): the scripts below make them.

| File | Where in App Store Connect | Size |
|---|---|---|
| `01-route.jpg` … `06-discover.jpg` | Bildschirmfotos, iPhone with Dynamic Island (medium display) | 1206 × 2622 |
| `ipad/01-route.jpg` … `ipad/06-discover.jpg` | Bildschirmfotos, iPad 13-inch (the smaller iPads are scaled from it) | 2064 × 2752 |
| `watch/01-tours.png` … `watch/04-controls.png` | Bildschirmfotos, Apple Watch (Series 12, 46 mm; App Store Connect scales them for the others) | 416 × 496 |
| `header.png` | Kopfzeile (product page header, 21:9) | 3840 × 1646 |
| `search.png` | Suchergebnisse (search result, 3:2) | 3840 × 2560 |

They show the real app and website with the local dev stack: copies of
official routes (Wanderland Schweiz) in a local account «storeshots», the
national map (© swisstopo, also on the header and search result).

## Making them again

After a change to the screens or the texts. Needs the dev stack, the API
and the web dev server (`docs/development.md`), and the iPhone 17 Pro and
iPad Pro 13-inch (M5) simulators.

```sh
app/store/seed.sh                          # once: the local account and its routes
app/store/capture.sh                       # the app's states → app/store/work/raw/ and raw-ipad/<language>/
bun app/store/render.mjs                   # headlines, map, header → app/store/<language>/
```

Both take the languages first: `capture.sh fr route,nav` captures only
some states in French (their names are in `screenshots_test.dart`), `bun
app/store/render.mjs fr` makes only the French pictures. Then the devices,
both by default: `capture.sh de route,nav,reach,journey,weather,discover
ipad` and `bun app/store/render.mjs de ipad` only the iPad. On the iPad the
same states show its wide layout (the map beside its panel); the header
and search result keep the iPhone screenshots. `capture.sh`
switches the simulator to each language in turn, logs it out (keychain
reset; the app then follows the simulator's language) and puts it back in
English afterwards. Four languages take about 10 minutes per device.

The headlines and the header's text, in every language, are in
`render.mjs`. Longer ones are set smaller until they fit.

### Apple Watch

```sh
app/store/watch.sh                         # → app/store/<language>/watch/, about half a minute per language
```

Needs the Apple Watch Series 12 (46mm) simulator and, for the state it
shows, the API, the web dev server and `seed.sh`'s account:
`watch-state.mjs` makes the tours and a hike on the Eiger Trail a third of
the way along, as the phone would send them. The watch app's UI test
(`testStoreScreenshots`) shows it with a made-up phone and takes the
pictures, without a frame or headline (Apple shows Watch screenshots
plain). The clock is the Mac's time: watchOS simulators take no status bar
override. The controls are shown scrolled to the buttons, the title cut at
the top.

Apple's rules: <https://developer.apple.com/app-store/asset-best-practices/>
(no prices, URLs, logos or awards; short text in every language; key
content inside the safe area). Before uploading, check the header and
search result in App Store Connect's preview: the safe areas are from
Apple's templates, not from its specification page.

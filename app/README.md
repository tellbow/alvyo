# odysgeh app

Flutter app for iOS (Android later): log in, list your routes, show a route on
the swisstopo national map and save it offline. Offline maps are PMTiles packs
built by the API (see `docs/adr/0004-offline-maps.md`); saved routes open
without a connection.

## Run

```sh
flutter run -d <simulator or phone>   # server: https://odysgeh.tellbow.ch or http://localhost:5173
```

On a phone, sign the Runner target in Xcode with your Apple ID
(`ios/Runner.xcworkspace`, Signing & Capabilities).

## Tests

```sh
flutter analyze
flutter test                                    # unit tests
flutter test integration_test -d <simulator>    # against the local dev stack
```

The integration test expects the API and the web dev server (:5173) from
`docs/development.md`, an account `appdemo` / `sehr-geheim-123` and its route
«Sargans–Weisstannen». It logs in, saves the route offline and then opens it
with an unreachable server.

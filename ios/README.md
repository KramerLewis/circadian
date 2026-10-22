# SunClock (iOS)

- `SunCore/` — Swift package: the NOAA solar calculator. Foundation only, no UI.
- `SunClock/` — the SwiftUI app. The Xcode project uses synchronized folders, so any
  file you add under `SunClock/` is part of the app target automatically.

## Tests

- In Xcode: open `SunClock.xcodeproj`, press ⌘U.
- On the command line (Mac): `swift test --package-path ios/SunCore`

Solar tests compare against `shared/fixtures/solar-reference.json` (±1 minute). To
regenerate it: `python3 shared/tools/generate_solar_fixtures.py --ephem`.

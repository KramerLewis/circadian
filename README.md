# circadian

Clocks and alarms that follow the sun. A monorepo:

| Path | What |
|---|---|
| `ios/` | **SunClock**, the native iOS app (SwiftUI, iOS 26+) and the `SunCore` Swift package |
| `web/` | **SunClock for the web** (TypeScript + canvas, Vite): the dial, events, moon, special days and eclipses |
| `shared/fixtures/` | Reference data every platform tests against (e.g. NOAA solar event times) |
| `shared/tools/` | Generators for those fixtures |

Planned: `android/`, `backend/` + `infra/` (AWS). Each platform reimplements
the solar math natively and is tested against the same `shared/fixtures`.

CI runs per platform, only when that platform's paths change (`.github/workflows/`).

## Credits

Moon imagery: NASA's Scientific Visualization Studio, [CGI Moon Kit](https://svs.gsfc.nasa.gov/4720),
from Lunar Reconnaissance Orbiter data (`ios/tools/lroc_color_2k.jpg`).

Earth imagery (3D view): NASA Earth Observatory, [Blue Marble Next Generation](https://visibleearth.nasa.gov/collection/1484/blue-marble)
(June 2004, topography and bathymetry) and [Black Marble 2016](https://earthobservatory.nasa.gov/features/NightLights)
night lights (`shared/assets/nasa/`, resized by `shared/tools/make_earth_textures.py`).

Sky (3D view): NASA/Goddard Space Flight Center Scientific Visualization Studio, [Deep Star Maps 2020](https://svs.gsfc.nasa.gov/4851)
(`shared/assets/nasa/starmap_2020_4k.jpg`, fetched and tone-mapped from `starmap_2020_4k.exr` by the NASA assets workflow). Credit lines are to be checked against each source page before release (`docs/app-store/README.md`).

Sun (dial sunspots and the 3D sun): courtesy of NASA/SDO and the AIA, EVE, and HMI science teams (HMI intensitygrams,
refreshed monthly for the web by `.github/workflows/nasa-assets.yml`; the iPhone app bundles a copy).

## License

[MIT](LICENSE) © 2026 Kramer Lewis

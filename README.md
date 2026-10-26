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

Earth map (web 3D view): drawn from [Natural Earth](https://www.naturalearthdata.com/) land polygons (public domain) via the
[world-atlas](https://github.com/topojson/world-atlas) package, by `shared/tools/make_earth_texture.py`.

## License

[MIT](LICENSE) © 2026 Kramer Lewis

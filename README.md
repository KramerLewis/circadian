# circadian

Clocks and alarms that follow the sun. A monorepo:

| Path | What |
|---|---|
| `ios/` | **SunClock**, the native iOS app (SwiftUI, iOS 26+) and the `SunCore` Swift package |
| `shared/fixtures/` | Reference data every platform tests against (e.g. NOAA solar event times) |
| `shared/tools/` | Generators for those fixtures |

Planned: `android/`, `web/`, `backend/` + `infra/` (AWS). Each platform reimplements
the solar math natively and is tested against the same `shared/fixtures`.

CI runs per platform, only when that platform's paths change (`.github/workflows/`).

## License

[MIT](LICENSE) © 2026 Kramer Lewis

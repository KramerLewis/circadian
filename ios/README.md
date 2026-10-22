# SunClock (iOS)

- `SunCore/` — Swift package: the NOAA solar calculator. Foundation only, no UI.
- `SunClock/` — the SwiftUI app. The Xcode project uses synchronized folders, so any
  file you add under `SunClock/` is part of the app target automatically.

## Tests

- In Xcode: open `SunClock.xcworkspace` (not the `.xcodeproj`), press ⌘U.
- On the command line (Mac): `swift test --package-path ios/SunCore`

Solar tests compare against `shared/fixtures/solar-reference.json` (±1 minute). To
regenerate it: `python3 shared/tools/generate_solar_fixtures.py --ephem`.

## Layout

| Path | Target | What |
|---|---|---|
| `SunCore/` | Swift package | Solar math, dial geometry, alarm planning. Pure, tested. |
| `SunClock/` | App | SwiftUI views, SwiftData models, location, AlarmKit scheduler. |
| `SunClockWidgets/` | Widget extension | Sun Ring widgets; Lock Screen / Dynamic Island UI for a snoozed alarm. |
| `Shared/` | Both | Alarm metadata, the ring view and palette, and the App Group store. |
| `Config/` | | Info.plist keys that can't be build settings. |

## How solar alarms are scheduled

AlarmKit gives real alarms (they ring in silent mode and Focus, with full-screen
Lock Screen UI and Stop/Snooze), but it only takes **fixed** times or fixed
clock-time repeats. Solar events move every day, and with location.

So SunClock never stores fire times. An alarm is a rule (event, offset, weekdays),
and on every refresh `RefreshCoordinator` does the following:

1. Resolves the location (live, last known, or manual; see `Place.resolve`).
2. Turns off one-time alarms whose moment has passed.
3. Plans every occurrence in the next **14 days**, soonest first, capped at **64**
   (`AlarmPlanner.plan`). Days when the event doesn't happen (polar day/night) are
   skipped.
4. Gives each occurrence a deterministic ID built from the alarm, its revision and
   the fire minute. It then cancels any scheduled alarm whose ID isn't in the plan and
   schedules any planned one that's missing (`AlarmReconciler`). An alarm that is
   ringing or snoozed is never cancelled.

A refresh runs on:

| Trigger | Where |
|---|---|
| App launch / return to foreground | `RootView` scene phase |
| Location moved > 5 km, or manual location changed | `RootView` `onChange(of: Place…)` |
| Significant time change (midnight, clock set, DST) | `UIApplication.significantTimeChangeNotification` |
| Time zone change | `NSSystemTimeZoneDidChange` |
| Alarm created, edited, toggled, deleted | `AlarmListView` / `AlarmEditorView` |
| Background app refresh (`com.kray.circadian.refresh`) | `.backgroundTask(.appRefresh)`, requested every ~6 h |

### Limits

- **Background refresh is not guaranteed.** iOS decides whether and when to run it,
  based on how often you use the app, battery, Low Power Mode, and the Background
  App Refresh setting. If the app isn't opened and iOS never runs the task, the
  schedule runs out after 14 days and alarms stop. The 14-day window is there to
  survive two weeks without either.
- **Times can drift between refreshes.** Each occurrence is fixed when it's
  scheduled. Day-to-day drift is already included, because each day is computed
  separately. What isn't included is a change of location or time zone after the last
  refresh. With only "When In Use" location access, the app can't watch location in
  the background, so after travel alarms follow the old location until the app is
  opened or a background refresh runs. A time zone change is picked up on the next
  refresh. Editing the manual location refreshes immediately.
- **The background refresh uses the last known location,** never a new fix.
- **64 alarm cap.** Apple doesn't document a per-app limit, so the plan keeps the
  soonest 64. With many daily alarms the window is shorter than 14 days, so the
  real horizon is about 64 ÷ alarms per day, in days.
- **Polar regions.** An alarm on an event that doesn't occur (sunrise in polar night)
  simply doesn't ring that day. The alarm list says when the next one is, or that
  there isn't one soon.
- **Snooze is fixed at 9 minutes** (`AlarmScheduler.snoozeDuration`).

### Testing it

The planning logic is unit-tested in SunCore (`AlarmPlannerTests`). Alarms ringing,
snooze and background refresh need a real device. To force a background refresh
while debugging on device, pause in the debugger and run:

    e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.kray.circadian.refresh"]

## TestFlight

`.github/workflows/testflight.yml` archives the app (with its widgets and Watch app),
signs it and uploads it to App Store Connect. Run it from the Actions tab with
**Run workflow**. It needs four repository secrets: `ASC_KEY_ID`, `ASC_ISSUER_ID`,
`ASC_KEY_P8` (the text of an App Store Connect API key with the Admin role) and
`APPLE_TEAM_ID`. Signing is automatic: Xcode registers the extra App IDs and the app
group and makes the certificate and profiles through that key. The build number is the
workflow's run number; the version is `MARKETING_VERSION` in the project.

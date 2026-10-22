# Backlog

## Priority order

Proposed; reorder freely. Rationale: get on a real device first (alarms can't be
verified anywhere else), then cheap wins, then the moon (which eclipses, special days
and a richer Watch face all build on), and the open-ended items last.

| # | Item | Size | Depends on / blocked by |
|---|---|---|---|
| 1 | **TestFlight pipeline** (CI builds, signs, uploads), including a real app icon (uploads are rejected without one) | S | Apple Developer enrollment, API key secrets |
| 2 | **On-device shakedown**: alarms ring/snooze/stop, permission prompts, background refresh, widgets, location | S-M | 1 |
| 3 | **App Store readiness**: docs, privacy, listing, screenshots, review notes (see details) | M | 1 for the build; can start now |
| 4 | **Moon ring + phase** | L | - |
| 5 | **Stage 5: Apple Watch face / complications**: design discussion now, build after 4 | L | Design decisions |
| 6 | **Cat feeder on solar time** | M | Which feeder (later, see details) |
| 7 | **Special event days** (solstices, equinoxes, full/new moon) | M | 4 for moon days; design pass |
| 8 | **Eclipses** | L | 4; bundled eclipse data |
| 9 | **More widgets** (Lock Screen rectangular/inline, readout variants) | S | - |
| 10 | **Tides** | L | Data source decision (bundle vs. API) |

### Rest of the system (after the iOS app ships)

| # | Item | Size | Depends on |
|---|---|---|---|
| P1 | **Sync API contract**: `shared/api/openapi.yaml` for settings and alarms (rules, not times), last-write-wins on `updatedAt`, soft deletes | S | - |
| P2 | **AWS backend** (`backend/` + `infra/`): API Gateway + Lambda (TypeScript) + DynamoDB, Cognito with Sign in with Apple / Google, infra as code with CDK, GitHub Actions deploys via OIDC (no long-lived keys) | L | P1 |
| P3 | **iOS sync client**: account sign-in, background sync of `AppSettings` and `SolarAlarm` | M | P2 |
| P4 | **Web app** (`web/`, TypeScript): dial, readouts, events, alarm management; solar math ported and tested against `shared/fixtures` | L | P1; P2 for sync |
| P5 | **Android app** (`android/`, Kotlin + Compose): dial, widgets, exact alarms (`AlarmManager.setAlarmClock`, which, unlike iOS, can be recomputed in the background); solar math ported and tested against `shared/fixtures` | L | P1; P2 for sync |
| P6 | **Shared fixtures for the moon** (and later eclipses), so every platform tests against the same reference | S | 4 |

## Done
- Time display setting for the dial's center: relative to the nearest of sunrise,
  solar noon, sunset, solar midnight (default), 12-hour, or 24-hour. Tap the center
  to cycle, or use the clock menu.
- Sun Ring widget: small, medium (with next sunrise/sunset and next event), large,
  Lock Screen circular.
- Smooth sky gradient driven by solar altitude (replaces hard bands); brightest at
  solar noon, warm near the horizon.
- Glowing sun without an outline, sized to stay inside the ring.

## Details

### Moon ring
An inner ring for the moon on its own timeline, with the same kind of milestones as the
sun: moonrise, lunar transit (highest), moonset, lower transit, and a gradient driven by
the moon's altitude. Show the moon glyph in its current phase (illuminated fraction and
waxing/waning orientation), and list moon events alongside the sun's.
- On-device: Meeus lunar position (ch. 47) for altitude/rise/set, phase from the
  sun-moon elongation. Moonrise/set need a search (the moon moves ~13 deg/day, and some
  days have no moonrise or no moonset).
- Shared fixture + PyEphem cross-check, like the solar one.

### Tides in the center
Show the tide for the current location inside both rings (rising/falling, next
high/low, height curve for the day).
- **Not computable from location alone.** Tide prediction needs per-station harmonic
  constants (NOAA CO-OPS for the US; other agencies elsewhere, often licensed). Options:
  bundle constants for a set of stations and predict on-device (keeps "no network"),
  or fetch from an API (breaks it, and coverage/licensing varies by country).
- Inland locations need a "nearest station" rule or should just hide the tide.
- Decision needed before building.

### Eclipses
Show upcoming solar and lunar eclipses correctly for the location: type (partial,
annular, total; penumbral/partial/total lunar), local contact times, and the visible
magnitude, and render them on the dial.
- On-device from Besselian elements (solar) and Meeus ch. 54/55 (lunar). Solar eclipse
  local circumstances need the elements for each eclipse, which can be bundled as data
  for, say, 2025-2050.

### Special event days
Distinct UI treatments on notable days: solstices, equinoxes, full/new moons,
supermoons, eclipses, maybe cross-quarter days. Needs a design pass: what each looks
like and how loud it is.

### Cat feeder on solar time
Feed the cats relative to solar events (e.g. "at civil dawn", "1 hr before sunset"),
the same rules the alarms use.

**Open question: which feeder?** The approach depends on the hardware:
- **Hackable / DIY (ESP32, ESPHome, Arduino):** run the solar math on the device
  itself, ported to C++ and tested against `shared/fixtures`. Most reliable: no
  phone, no cloud, works through Wi-Fi outages. The app could push the rules to it
  over the local network (or via the sync backend later).
- **Smart plug / HomeKit-controlled feeder:** schedule from the phone with HomeKit
  automations; sunrise/sunset are built in, but twilight, solar noon and offsets
  aren't, and HomeKit can't use our calculations directly.
- **Vendor cloud feeder (Petlibro, PetSafe, etc.):** only if it has a usable API;
  the backend would push daily feed times. Most fragile.
- Whichever it is: expose an App Intent ("next time of <event> + offset") so
  Shortcuts and automations can use SunClock's times too.

### App Store readiness
Everything needed beyond the code to publish:
- **Privacy:** privacy policy (hosted, e.g. GitHub Pages from `docs/`): location is
  used on device only, nothing is collected or sent. App Store "App Privacy" answers
  (Data Not Collected). `PrivacyInfo.xcprivacy` privacy manifests for the app and
  widget extension, declaring required-reason APIs (UserDefaults incl. the App Group).
- **Listing:** name (check "SunClock" availability), subtitle, description, keywords,
  category (Utilities or Weather), age rating, support URL, marketing URL.
- **Screenshots:** required iPhone sizes (6.9" and 6.5"), generated by CI from demo
  mode, since we already capture them deterministically.
- **App icon** (light, dark and tinted variants for iOS 26).
- **Review notes:** why it needs AlarmKit and location; how to test (manual location,
  an alarm a few minutes out).
- **Accessibility pass:** VoiceOver labels on the dial and widgets, Dynamic Type,
  contrast in both modes.
- **Localization plan:** add a String Catalog (the build already extracts strings);
  some UI text is built from strings in code and needs converting first. Decide
  initial languages.
- **Repo docs:** user-facing README section, `CHANGELOG.md` / release notes,
  `LICENSE` (the repo is public, so pick one deliberately; "all rights reserved" is
  an option), `SECURITY.md`.
- **Release process:** versioning (marketing version + CI build number), TestFlight
  external testing (needs a beta review), phased release.

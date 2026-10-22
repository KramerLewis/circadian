# Backlog

## Priority order

Proposed; reorder freely. Rationale: get on a real device first (alarms can't be
verified anywhere else), then cheap wins, then the moon (which eclipses, special days
and a richer Watch face all build on), and the open-ended items last.

| # | Item | Size | Depends on / blocked by |
|---|---|---|---|
| 1 | **TestFlight pipeline** (CI builds, signs, uploads) | S | Apple Developer enrollment, API key secrets |
| 2 | **On-device shakedown**: alarms ring/snooze/stop, permission prompts, background refresh, widgets, location | S-M | 1 |
| 3 | **Time display setting** (relative / 12h / 24h) | S | Your answer on scope (below) |
| 4 | **Moon ring + phase** | L | - |
| 5 | **Stage 5: Apple Watch face / complications**: design discussion now, build after 4 | L | Design decisions |
| 6 | **Special event days** (solstices, equinoxes, full/new moon) | M | 4 for moon days; design pass |
| 7 | **Eclipses** | L | 4; bundled eclipse data |
| 8 | **More widgets** (Lock Screen rectangular/inline, readout variants) | S | - |
| 9 | **Tides** | L | Data source decision (bundle vs. API) |

Later, outside iOS: Android app, web app, AWS sync backend (models are already
sync-ready: stable IDs, `updatedAt`, soft deletes).

## Done
- Sun Ring widget: small, medium (with next sunrise/sunset and next event), large,
  Lock Screen circular.
- Smooth sky gradient driven by solar altitude (replaces hard bands); brightest at
  solar noon, warm near the horizon.
- Glowing sun without an outline, sized to stay inside the ring.

## Details

### Time display setting
A setting for the dial's main readout, with three options:
- **Relative** (default): time measured from the nearest anchor among sunrise, solar
  noon, sunset and solar midnight, e.g. "1h 48m after solar noon".
- **12-hour** clock: "3:00 PM".
- **24-hour** clock: "15:00".

Stored in `AppSettings`. Proposed: the setting drives the center readout; the event
list and ring labels follow 12/24-hour. (Waiting on confirmation.)

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

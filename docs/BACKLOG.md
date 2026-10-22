# Backlog

Not scheduled. Newest at the bottom.

## Planned stages
- **Stage 5: Apple Watch face / complication.** Needs a design discussion first.
- Home Screen and Lock Screen widgets (reuse SunCore).
- TestFlight pipeline via GitHub Actions (waiting on Apple Developer enrollment).

## iOS

### Smooth gradients instead of hard band edges
The night/twilight/day bands should blend into each other continuously rather than
switching color at each threshold. This merges naturally with the daylight gradient
below: color is a continuous function of solar altitude, with the event thresholds
(-18, -12, -6, -0.833 deg) as stops.

### Glowing sun
Drop the hard black outline on the sun marker; draw it as a soft glow (radial
gradient + blur) whose intensity can follow altitude.

### Daylight gradient on the dial
Paint the day band as a gradient that tracks how high the sun is, instead of one flat
yellow: brightest at solar noon (the sun's highest point), shading through warm
sunrise/sunset colors near the horizon. Twilight bands can blend into it the same way.
Light and dark mode variants.
- Drive the color from the sun's altitude at each angle on the ring, not from clock
  time, so it's correct in winter, summer and at high latitudes (in midnight sun, the
  lowest point of the ring stays warm but never goes dark).
- SunCore needs `altitude(at:coordinate:)`; the angular gradient is drawn in the dial.

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

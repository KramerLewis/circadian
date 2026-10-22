# Backlog

Not scheduled. Newest at the bottom.

## Later (from the original brief)
- Home Screen and Lock Screen widgets (reuse SunCore).
- Apple Watch complication.
- TestFlight pipeline via GitHub Actions (waiting on Apple Developer enrollment).

## iOS

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

Stored in `AppSettings`. Should it apply to the event list and the clock labels around
the dial too, or only the center readout? (Open question.)

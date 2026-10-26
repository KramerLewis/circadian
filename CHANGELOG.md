# Changelog

All notable changes to SunClock. Versions follow the app's marketing version.

## [Unreleased]

### Added
- Web app (`web/`): the solar dial with the moon ring, readouts, sun and moon events, special days and eclipses, a time scrubber, and light/dark (follows the system, or pick one). Runs entirely in the browser; tested against the same shared fixtures as iOS.
- Solar calculations on device (NOAA algorithm) for all ten solar events, with polar
  day/night handling; tested against shared reference data cross-checked with PyEphem.
- Realistic moon: NASA LRO imagery lit for the current phase, with a soft glow.
- Physically drawn sun: limb darkening, granulation, two-layer corona, and color by altitude (white-gold at noon to red at the horizon, a dim ember below it).
- Moon ring on the same 24-hour timeline as the sun (ticks at moonrise and moonset), phase glyph, and moon events; lunar math tested against shared reference data.
- Eclipses: lunar (penumbral, partial, total "blood moon") and solar (partial, annular, total) computed on device for your location, shown as special days with a red-tinted moon or the moon crossing the sun on the dial, and the next eclipse in the moon list.
- Moon position now uses Meeus's ELP-2000/82 series (accurate to seconds), so eclipse timing holds up.
- 24-hour solar dial with a sky gradient that follows the sun's altitude, a glowing
  sun, event markers, and relative readouts ("2h 14m after sunrise").
- Center readout setting: relative to the nearest solar anchor, 12-hour, or 24-hour.
- Dial setting: noon at top (fixed dial, the sun travels round) or now at top (the dial turns under the sun), on iPhone, Watch and web.
- Location (when in use, approximate) with a manual fallback.
- Solar alarms via AlarmKit: any event plus an offset, repeat days, labels, snooze.
  A rolling 14-day scheduler refreshes on launch, location and time changes, edits
  and background app refresh.
- Sun Ring widgets: small, medium, large, and Lock Screen circular.
- Special sky days: solstices, equinoxes, full moons, supermoons, blue moons and new moons get a banner and a mark on the dial, with a heads-up a few days ahead; widgets and the Watch show them too.
- App icon (default, dark, tinted).

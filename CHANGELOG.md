# Changelog

All notable changes to SunClock. Versions follow the app's marketing version.

## [Unreleased]

### Added
- Web 3D view: Earth lit by the sun, with NASA's Blue Marble by day and Black Marble city lights at night, against NASA's Deep Star Map sky (stars and the Milky Way where they really are), a pin at your place turning with Earth, Earth's axis, and the moon on its orbit with its phase and eclipse shadow; drag to look around. Follows the time scrubber.
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
- Moon setting: on the clock (moonrise and moonset against the hours) or in the sky (the moon at its real angle from the sun, which shows the phase), with the next moonrise and moonset under the dial.
- Sun periods: a new center readout naming where you are in the solar day: -R R R+ 0 -N N N+ 1 -S S S+ 2 -M M M+ 3 (milestones with a ±15-minute window, thirds of each quarter between), with details below the dial and the moon's equivalent (lowercase) as an option.
- Wadokei: Edo-period temporal hours (six of daylight and six of night between the Kansei calendar's dawn and dusk), with the zodiac kanji around the dial and the current hour lit like embers.
- Real sunspots on the dial's sun and a real sun in the 3D view, from NASA SDO's HMI intensitygrams (monthly on the web; bundled in the app).
- Hand color setting: royal blue, red, cyan, green, krypton purple, white/black (follows light and dark), or shimmering gold (still with Reduce Motion).
- The "now" hand is a glowing blue line beneath both rings, from inside the moon ring to past the sun ring; the sun on the ring is larger.
- Dial setting: noon at top (fixed dial, the sun travels round) or now at top (the dial turns under the sun), on iPhone, Watch and web.
- Location (when in use, approximate) with a manual fallback.
- Solar alarms via AlarmKit: any event plus an offset, repeat days, labels, snooze.
  A rolling 14-day scheduler refreshes on launch, location and time changes, edits
  and background app refresh.
- Sun Ring widgets: small, medium, large, and Lock Screen circular.
- Special sky days: solstices, equinoxes, full moons, supermoons, blue moons and new moons get a banner and a mark on the dial, with a heads-up a few days ahead; widgets and the Watch show them too.
- App icon (default, dark, tinted).

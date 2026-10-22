# Changelog

All notable changes to SunClock. Versions follow the app's marketing version.

## [Unreleased]

### Added
- Solar calculations on device (NOAA algorithm) for all ten solar events, with polar
  day/night handling; tested against shared reference data cross-checked with PyEphem.
- 24-hour solar dial with a sky gradient that follows the sun's altitude, a glowing
  sun, event markers, and relative readouts ("2h 14m after sunrise").
- Center readout setting: relative to the nearest solar anchor, 12-hour, or 24-hour.
- Location (when in use, approximate) with a manual fallback.
- Solar alarms via AlarmKit: any event plus an offset, repeat days, labels, snooze.
  A rolling 14-day scheduler refreshes on launch, location and time changes, edits
  and background app refresh.
- Sun Ring widgets: small, medium, large, and Lock Screen circular.
- App icon (default, dark, tinted).

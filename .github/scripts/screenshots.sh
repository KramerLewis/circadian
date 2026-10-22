#!/usr/bin/env bash
# Build SunClock for a simulator and capture screenshots in demo mode (a fixed place
# and time from launch arguments; see ios/SunClock/App/DemoConfig.swift).
# Usage: screenshots.sh <simulator-udid> <output-dir>
set -euo pipefail
udid=$1
out=$2
bundle=com.kray.circadian
mkdir -p "$out"

xcrun simctl boot "$udid" 2>/dev/null || true
xcrun simctl bootstatus "$udid" -b >/dev/null

xcodebuild build -quiet \
  -workspace ios/SunClock.xcworkspace -scheme SunClock \
  -destination "id=$udid" -derivedDataPath build/screenshots \
  CODE_SIGNING_ALLOWED=NO
xcrun simctl install "$udid" build/screenshots/Build/Products/Debug-iphonesimulator/SunClock.app

# shoot <name> <light|dark> <time zone> <status bar time> <app args...>
shoot() {
  local name=$1 appearance=$2 tz=$3 clock=$4
  shift 4
  xcrun simctl ui "$udid" appearance "$appearance"
  xcrun simctl status_bar "$udid" override --time "$clock" --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4
  xcrun simctl terminate "$udid" "$bundle" 2>/dev/null || true
  SIMCTL_CHILD_TZ="$tz" xcrun simctl launch "$udid" "$bundle" "$@" >/dev/null
  sleep 4
  xcrun simctl io "$udid" screenshot "$out/$name.png" >/dev/null
  echo "captured $name"
}

seattle=(-demoLatitude 47.61 -demoLongitude -122.33 -demoName Seattle)
shoot 1-seattle-june-afternoon-light light America/Los_Angeles 15:00 "${seattle[@]}" -demoDate 2026-06-21T15:00:00-07:00
shoot 2-seattle-june-afternoon-dark  dark  America/Los_Angeles 15:00 "${seattle[@]}" -demoDate 2026-06-21T15:00:00-07:00
shoot 3-seattle-december-night-dark  dark  America/Los_Angeles 21:30 "${seattle[@]}" -demoDate 2026-12-21T21:30:00-08:00
shoot 4-tromso-midnight-sun-light    light Europe/Oslo         23:30 -demoLatitude 69.65 -demoLongitude 18.96 -demoName Tromsø -demoDate 2026-06-21T23:30:00+02:00
shoot 5-tromso-polar-night-dark      dark  Europe/Oslo         12:00 -demoLatitude 69.65 -demoLongitude 18.96 -demoName Tromsø -demoDate 2026-12-21T12:00:00+01:00
shoot 6-location-settings-light      light America/Los_Angeles 15:00 "${seattle[@]}" -demoDate 2026-06-21T15:00:00-07:00 -demoSheet location

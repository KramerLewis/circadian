#!/usr/bin/env bash
# Build the Watch app for a watchOS simulator and capture screenshots in demo mode.
# Usage: watch-screenshots.sh <watch-simulator-udid> <output-dir>
set -euo pipefail
udid=$1
out=$2
bundle=com.kray.circadian.watchkitapp
mkdir -p "$out"

xcrun simctl boot "$udid" 2>/dev/null || true
xcrun simctl bootstatus "$udid" -b >/dev/null

xcodebuild build -quiet \
  -workspace ios/SunClock.xcworkspace -scheme SunClockWatch \
  -destination "id=$udid" -derivedDataPath build/watch \
  CODE_SIGNING_ALLOWED=NO
xcrun simctl install "$udid" build/watch/Build/Products/Debug-watchsimulator/SunClockWatch.app

failures=0
# shoot <name> <time zone> <ISO date> <app args...>
shoot() {
  local name=$1 tz=$2 date=$3
  shift 3
  xcrun simctl terminate "$udid" "$bundle" 2>/dev/null || true
  local launched pid
  launched=$(SIMCTL_CHILD_TZ="$tz" xcrun simctl launch "$udid" "$bundle" -demoDate "$date" "$@")
  pid=${launched##*: }
  sleep 6
  if ! kill -0 "$pid" 2>/dev/null; then
    echo "::error::SunClockWatch exited or crashed while capturing $name"
    report=$(ls -t ~/Library/Logs/DiagnosticReports/SunClockWatch*.ips 2>/dev/null | head -1)
    [[ -n "$report" ]] && head -c 6000 "$report"
    failures=$((failures + 1))
  fi
  xcrun simctl io "$udid" screenshot "$out/$name.png" >/dev/null
  echo "captured $name (pid $pid)"
}

seattle=(-demoLatitude 47.61 -demoLongitude -122.33 -demoName Seattle)
shoot watch-1-dial-afternoon  America/Los_Angeles 2026-11-01T15:00:00-08:00 "${seattle[@]}"
shoot watch-2-dial-night      America/Los_Angeles 2026-11-24T22:00:00-08:00 "${seattle[@]}" -demoTimeDisplay twelveHour
shoot watch-3-scrubbing       America/Los_Angeles 2026-11-01T15:00:00-08:00 "${seattle[@]}" -demoScrub 150
shoot watch-4-events          America/Los_Angeles 2026-11-01T15:00:00-08:00 "${seattle[@]}" -demoSheet events
shoot watch-5-complications   America/Los_Angeles 2026-11-01T15:00:00-08:00 "${seattle[@]}" -demoSheet complications
shoot watch-6-blood-moon      America/Los_Angeles 2026-03-03T03:30:00-08:00 "${seattle[@]}"
shoot watch-7-solar-eclipse   America/Chicago     2024-04-08T13:30:00-05:00 -demoLatitude 32.78 -demoLongitude -96.80 -demoName Dallas
shoot watch-8-now-at-top      America/Los_Angeles 2026-11-01T15:00:00-08:00 "${seattle[@]}" -demoDialOrientation nowAtTop

if (( failures > 0 )); then
  echo "$failures screenshot(s) caught a crashed app"
  exit 1
fi

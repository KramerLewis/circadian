#!/usr/bin/env bash
# Archive SunClock and upload it to App Store Connect (see .github/workflows/testflight.yml).
set -euo pipefail

work="$RUNNER_TEMP/build"
mkdir -p "$work"
key="$work/AuthKey_${ASC_KEY_ID}.p8"
printf '%s\n' "$ASC_KEY_P8" > "$key"
trap 'rm -f "$key"' EXIT
auth=(-allowProvisioningUpdates
      -authenticationKeyPath "$key"
      -authenticationKeyID "$ASC_KEY_ID"
      -authenticationKeyIssuerID "$ASC_ISSUER_ID")

echo "Archiving build $BUILD_NUMBER"
set +e
xcodebuild archive \
  -workspace ios/SunClock.xcworkspace \
  -scheme SunClock \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$work/SunClock.xcarchive" \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
  CODE_SIGN_STYLE=Automatic \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  "${auth[@]}" > "$work/archive.log" 2>&1
status=$?
set -e
if (( status != 0 )); then
  grep -E "error:|warning: .*(provision|sign)" "$work/archive.log" | head -40 || true
  tail -40 "$work/archive.log"
  exit $status
fi
echo "Archived"

cat > "$work/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>teamID</key><string>${APPLE_TEAM_ID}</string>
  <key>signingStyle</key><string>automatic</string>
  <key>manageAppVersionAndBuildNumber</key><false/>
  <key>uploadSymbols</key><true/>
</dict>
</plist>
PLIST

echo "Exporting and uploading"
set +e
xcodebuild -exportArchive \
  -archivePath "$work/SunClock.xcarchive" \
  -exportOptionsPlist "$work/ExportOptions.plist" \
  -exportPath "$work/export" \
  "${auth[@]}" > "$work/export.log" 2>&1
status=$?
set -e
if (( status != 0 )); then
  grep -E "error|Error" "$work/export.log" | head -40 || true
  tail -40 "$work/export.log"
  exit $status
fi
tail -5 "$work/export.log"
echo "Uploaded build $BUILD_NUMBER. It shows up in TestFlight once Apple finishes processing it."

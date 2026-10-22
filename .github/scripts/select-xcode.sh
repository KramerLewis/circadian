#!/usr/bin/env bash
# Select the newest Xcode 26.x installed on the runner.
set -euo pipefail
xcode=$(ls -d /Applications/Xcode_26*.app 2>/dev/null | sort -V | tail -1 || true)
if [[ -z "$xcode" ]]; then
  echo "No Xcode 26 on this runner. Installed:" >&2
  ls -d /Applications/Xcode*.app >&2
  exit 1
fi
sudo xcode-select -s "$xcode/Contents/Developer"
xcodebuild -version

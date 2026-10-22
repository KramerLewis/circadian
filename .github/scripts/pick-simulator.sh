#!/usr/bin/env bash
# Print the UDID of an available simulator on the newest installed runtime of a
# platform, so the workflow doesn't hard-code a device name the runner may not have.
# Usage: pick-simulator.sh [iOS|watchOS]   (default iOS)
set -euo pipefail
platform=${1:-iOS}
xcrun simctl list devices available --json | PLATFORM="$platform" python3 -c '
import json, os, re, sys
platform = os.environ["PLATFORM"]
prefix = "iPhone" if platform == "iOS" else "Apple Watch"
devices = json.load(sys.stdin)["devices"]
def version(runtime):
    m = re.search(platform + r"-(\d+)-(\d+)", runtime)
    return (int(m.group(1)), int(m.group(2))) if m else None
runtimes = sorted((r for r in devices if version(r) and version(r) >= (26, 0)), key=version, reverse=True)
for runtime in runtimes:
    for d in devices[runtime]:
        if d["name"].startswith(prefix):
            name = d["name"]
            print("Using " + name + " on " + runtime, file=sys.stderr)
            print(d["udid"])
            sys.exit(0)
sys.exit("no " + prefix + " simulator with " + platform + " 26+ available")
'

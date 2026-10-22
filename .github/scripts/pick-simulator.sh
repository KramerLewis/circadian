#!/usr/bin/env bash
# Print the UDID of an available iPhone simulator on the newest installed iOS runtime,
# so the workflow doesn't hard-code a device name that the runner image may not have.
set -euo pipefail
xcrun simctl list devices available --json | python3 -c '
import json, re, sys
devices = json.load(sys.stdin)["devices"]
def version(runtime):
    m = re.search(r"iOS-(\d+)-(\d+)", runtime)
    return (int(m.group(1)), int(m.group(2))) if m else None
runtimes = sorted((r for r in devices if version(r) and version(r) >= (26, 0)), key=version, reverse=True)
for runtime in runtimes:
    for d in devices[runtime]:
        if d["name"].startswith("iPhone"):
            name = d["name"]
            print("Using " + name + " on " + runtime, file=sys.stderr)
            print(d["udid"])
            sys.exit(0)
sys.exit("no iPhone simulator with iOS 26+ available")
'

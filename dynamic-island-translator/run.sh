#!/usr/bin/env bash
# Generate the Xcode project and run the app in an iPhone simulator that has a Dynamic Island.
#   ./run.sh          build + launch in the newest "iPhone NN Pro" simulator
#   ./run.sh --open   just generate the project and open it in Xcode (use this for a real iPhone)
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v xcodegen >/dev/null; then
  echo "→ Installing XcodeGen with Homebrew…"
  brew install xcodegen
fi
xcodegen generate --quiet

if [[ "${1:-}" == "--open" ]]; then
  open IslandTranslator.xcodeproj
  exit 0
fi

PICK=$(xcrun simctl list devices available -j | python3 -c '
import json, re, sys
cands = []
for runtime, devs in json.load(sys.stdin)["devices"].items():
    m = re.search(r"iOS-(\d+)-(\d+)", runtime)
    if not m:
        continue
    ver = (int(m.group(1)), int(m.group(2)))
    for d in devs:
        n = re.match(r"iPhone (\d+) Pro", d["name"])
        if n and int(n.group(1)) >= 14:          # 14 Pro and newer have the Dynamic Island
            cands.append((ver, int(n.group(1)), "Max" not in d["name"], d["udid"], d["name"]))
cands.sort()
print(cands[-1][3] + "|" + cands[-1][4] if cands else "")
')
if [[ -z "$PICK" ]]; then
  echo "No 'iPhone NN Pro' simulator found. Add one in Xcode › Window › Devices and Simulators." >&2
  exit 1
fi
UDID="${PICK%%|*}"; NAME="${PICK#*|}"
echo "→ Using simulator: $NAME"

xcrun simctl boot "$UDID" 2>/dev/null || true
# Xcode 27 ships no Simulator.app; the device runs without a window then.
open -a Simulator 2>/dev/null || echo "→ No Simulator app found; the simulator runs without a window."

echo "→ Building…"
xcodebuild -project IslandTranslator.xcodeproj -scheme IslandTranslator \
  -destination "id=$UDID" -derivedDataPath build -quiet build

xcrun simctl install "$UDID" build/Build/Products/Debug-iphonesimulator/IslandTranslator.app
xcrun simctl launch "$UDID" dev.lab.islandtranslator >/dev/null
echo "✓ Launched. Tap 'Run demo conversation', then swipe up to Home and watch the island."

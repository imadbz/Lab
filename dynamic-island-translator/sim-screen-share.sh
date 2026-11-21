#!/usr/bin/env bash
# Stand-in for screen sharing in the Simulator, which can't run the broadcast extension.
# Copies the simulator's screen into the app's App Group folder about once a second, keeping
# the frame from a moment ago (as Broadcast/SampleHandler.swift does on a phone).
# Screenshots use --mask=black: with the default mask, every screenshot briefly hid the
# Dynamic Island, so a screenshot loop made it flash.
#   ./sim-screen-share.sh            # booted simulator
#   ./sim-screen-share.sh <udid>     # a given one
# Stop with Ctrl-C; the frame is removed so the app sees sharing as off.
set -euo pipefail

DEVICE="${1:-booted}"
group() { xcrun simctl get_app_container "$DEVICE" dev.lab.islandtranslator group.dev.lab.islandtranslator 2>/dev/null; }
GROUP=$(group)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"; rm -f "$GROUP/frame.jpg"; echo; echo "Stopped. Screen sharing is off."' EXIT

echo "Sharing the simulator's screen with Island Translator. Ctrl-C to stop."
n=0
while true; do
  slot=$((n % 2))
  if xcrun simctl io "$DEVICE" screenshot --mask=black --type=png "$WORK/shot.png" >/dev/null 2>&1; then
    sips -s format jpeg -s formatOptions 80 -Z 1568 "$WORK/shot.png" --out "$WORK/$slot.jpg" >/dev/null 2>&1
    # Write the previous capture: the expanded island you open to tap Translate isn't in it yet.
    prev="$WORK/$(((n + 1) % 2)).jpg"
    [[ -f "$prev" ]] || prev="$WORK/$slot.jpg"
    # Reinstalling the app gives it a new App Group folder, so look it up again when it's gone.
    [[ -d "$GROUP" ]] || GROUP=$(group)
    # A failed copy (the simulator rebooting, say) skips this frame instead of ending the script.
    { cp "$prev" "$GROUP/frame.jpg.tmp" && mv "$GROUP/frame.jpg.tmp" "$GROUP/frame.jpg"; } 2>/dev/null || true
    n=$((n + 1))
  fi
  sleep 0.7
done

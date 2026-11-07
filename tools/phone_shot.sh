#!/usr/bin/env bash
# A phone-sized (844x390, touch) frame of the client: tools/phone_shot.sh [out.png]. Look at it.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p screenshots
SHOT_OUT="$(realpath -m "${1:-screenshots/phone.png}")" exec xvfb-run -a -s "-screen 0 1280x720x24" "${GODOT:-godot}" --path . --resolution 844x390 res://tools/phone_shot.tscn

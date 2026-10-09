#!/bin/bash
# Obnoví obrázky do README: ikonu a snímky náhledu docs/images/demo.md ve světlém i tmavém vzhledu.
# Vyžaduje Debug build (make build).
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d /tmp/mdview-readme.XXXXXX)

swift "$ROOT/scripts/make-icon.swift" "$ROOT/App/Assets.xcassets/AppIcon.appiconset" "$ROOT/docs/images/icon.png"
for appearance in light dark; do
    "$ROOT/scripts/selftest.sh" "$ROOT/docs/images/demo.md" \
        -MDViewSelfTestSnapshot "$WORK/$appearance.png" -MDViewSelfTestAppearance "$appearance" > /dev/null
    swift "$ROOT/scripts/frame-screenshot.swift" "$WORK/$appearance.png" \
        "$ROOT/docs/images/preview-$appearance.png" "demo.md" "$appearance"
done

#!/bin/bash
# Self-test náhledu v Debug buildu (viz App/Web/SelfTest.swift): otevře kopii dokumentu
# v /tmp, počká na JSON report a vypíše ho.
# Použití: scripts/selftest.sh [soubor.md] [další argumenty aplikace, např. -MDViewSelfTestSnapshot x.png]
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
APP="$HOME/Library/Caches/MDView/DerivedData/Build/Products/Debug/MDView.app"
SOURCE=${1:-$ROOT/Samples/showcase.md}
[ $# -gt 0 ] && shift
EXTRA=("$@")
WORK=$(mktemp -d /tmp/mdview-selftest.XXXXXX)
REPORT="$WORK/report.json"

cp "$SOURCE" "$WORK/"
[ -d "$(dirname "$SOURCE")/img" ] && cp -R "$(dirname "$SOURCE")/img" "$WORK/"
pkill -f "$APP/Contents/MacOS/MDView" 2>/dev/null || true
sleep 0.5

open -n -g -a "$APP" "$WORK/$(basename "$SOURCE")" --args -MDViewSelfTestReport "$REPORT" -ApplePersistenceIgnoreState YES ${EXTRA[@]+"${EXTRA[@]}"}
for _ in $(seq 1 60); do
    [ -f "$REPORT" ] && break
    sleep 0.5
done
if [ ! -f "$REPORT" ]; then
    echo "Self-test nevytvořil report do 30 s" >&2
    exit 1
fi
cat "$REPORT"

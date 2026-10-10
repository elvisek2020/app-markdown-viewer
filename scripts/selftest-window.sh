#!/bin/bash
# Self-test paměti okna (Debug build): rám zavřeného okna se uloží a další okno ho převezme,
# třetí okno se posune kaskádovitě. Test ukládá pod vlastním klíčem a ten na konci smaže.
set -euo pipefail

APP="$HOME/Library/Caches/MDView/DerivedData/Build/Products/Debug/MDView.app"
cleanup() {
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$APP" 2>/dev/null || true
    pluginkit -r "$APP/Contents/PlugIns/MDViewQuickLook.appex" 2>/dev/null || true
}
trap cleanup EXIT

WORK=$(mktemp -d /tmp/mdview-window.XXXXXX)
for name in prvni druhy treti; do printf '# %s\n' "$name" > "$WORK/$name.md"; done
REPORT="$WORK/report.json"

pkill -f "$APP/Contents/MacOS/MDView" 2>/dev/null || true
sleep 0.5
open -n -g -a "$APP" "$WORK/prvni.md" --args -MDViewSelfTestWindowFrame "$REPORT" \
    -MDViewSelfTestFiles "($WORK/druhy.md,$WORK/treti.md)" -ApplePersistenceIgnoreState YES
for _ in $(seq 1 60); do
    [ -f "$REPORT" ] && break
    sleep 0.5
done
[ -f "$REPORT" ] || { echo "Self-test okna nevytvořil report do 30 s" >&2; exit 1; }
cat "$REPORT"

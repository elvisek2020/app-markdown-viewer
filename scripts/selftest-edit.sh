#!/bin/bash
# Self-test režimu úprav (Debug build): psaní a automatické uložení, tichý reload změny od agenta,
# konflikt s bannerem (porovnání, ponechat moje / načíst z disku), synchronizace posunu editor ↔ náhled.
set -euo pipefail

APP="$HOME/Library/Caches/MDView/DerivedData/Build/Products/Debug/MDView.app"
cleanup() {
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$APP" 2>/dev/null || true
    pluginkit -r "$APP/Contents/PlugIns/MDViewQuickLook.appex" 2>/dev/null || true
}
trap cleanup EXIT

WORK=$(mktemp -d /tmp/mdview-edit.XXXXXX)
DOC="$WORK/uprava.md"
REPORT="$WORK/report.json"
{
    printf '# Úpravy\n\nDokument pro self-test editoru.\n'
    for i in $(seq 1 60); do printf '\n## Sekce %d\n\nOdstavec %d s textem, který se v editoru i náhledu vejde na řádek.\n' "$i" "$i"; done
} > "$DOC"

pkill -f "$APP/Contents/MacOS/MDView" 2>/dev/null || true
sleep 0.5
open -n -g -a "$APP" "$DOC" --args -MDViewSelfTestEditReport "$REPORT" -ApplePersistenceIgnoreState YES "$@"
for _ in $(seq 1 80); do
    [ -f "$REPORT" ] && break
    sleep 0.5
done
[ -f "$REPORT" ] || { echo "Self-test úprav nevytvořil report do 40 s" >&2; exit 1; }
cat "$REPORT"

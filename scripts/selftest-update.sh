#!/bin/bash
# Self-test aktualizace v aplikaci (Debug build) bez GitHubu: lokální „vydání“ (JSON + zip Debug buildu
# a podvržená kopie), aplikace ho najde, ověří podpis, podvrh odmítne a po ukončení skriptem vymění
# cílovou kopii v /tmp (bez restartu, nainstalované aplikace se netýká).
# Použití: scripts/selftest-update.sh [-MDViewSelfTestSettingsSnapshot nastaveni.png]
set -euo pipefail

APP="$HOME/Library/Caches/MDView/DerivedData/Build/Products/Debug/MDView.app"
cleanup() {
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$APP" 2>/dev/null || true
    pluginkit -r "$APP/Contents/PlugIns/MDViewQuickLook.appex" 2>/dev/null || true
}
trap cleanup EXIT

WORK=$(mktemp -d /tmp/mdview-update.XXXXXX)
REPORT="$WORK/report.json"
TARGET="$WORK/cil/MDView.app"
mkdir -p "$TARGET/Contents" "$WORK/podvrh"
echo stará > "$TARGET/Contents/stara-verze.txt"
printf '# Aktualizace\n' > "$WORK/doc.md"

ditto -c -k --keepParent "$APP" "$WORK/MDView.zip"
ditto "$APP" "$WORK/podvrh/MDView.app"
echo "podvrh" >> "$WORK/podvrh/MDView.app/Contents/Resources/THIRD_PARTY_LICENSES.md"
ditto -c -k --keepParent "$WORK/podvrh/MDView.app" "$WORK/podvrh.zip"
cat > "$WORK/latest.json" <<JSON
{"tag_name": "v99999999.9999", "html_url": "https://example.com/release",
 "assets": [{"name": "MDView.zip", "browser_download_url": "file://$WORK/MDView.zip"}]}
JSON

pkill -f "$APP/Contents/MacOS/MDView" 2>/dev/null || true
sleep 0.5
open -n -g -a "$APP" "$WORK/doc.md" --args -MDViewSelfTestUpdate "$REPORT" -MDViewUpdateAPI "file://$WORK/latest.json" \
    -MDViewSelfTestUpdateTampered "file://$WORK/podvrh.zip" -MDViewSelfTestUpdateTarget "$TARGET" -ApplePersistenceIgnoreState YES "$@"
for _ in $(seq 1 60); do
    [ -f "$REPORT" ] && break
    sleep 0.5
done
[ -f "$REPORT" ] || { echo "Self-test aktualizace nevytvořil report do 30 s" >&2; exit 1; }

# Výměna proběhne až po ukončení aplikace.
REPLACED=false
for _ in $(seq 1 40); do
    if [ ! -e "$TARGET/Contents/stara-verze.txt" ] && [ -f "$TARGET/Contents/Info.plist" ]; then REPLACED=true; break; fi
    sleep 0.5
done
BUNDLE=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$TARGET/Contents/Info.plist" 2>/dev/null || echo "")
python3 -c 'import json, sys; r = json.load(open(sys.argv[1])); r["replaced"] = sys.argv[2] == "true"; r["bundle"] = sys.argv[3]; print(json.dumps(r, ensure_ascii=False, indent=2))' \
    "$REPORT" "$REPLACED" "$BUNDLE"

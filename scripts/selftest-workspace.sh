#!/bin/bash
# Self-test pracovní složky (Debug build): otevře složku, ověří strom (bez node_modules, .git…),
# výchozí výběr README a režim sledování – po vytvoření nového souboru agentem se na něj náhled přepne.
set -euo pipefail

APP="$HOME/Library/Caches/MDView/DerivedData/Build/Products/Debug/MDView.app"
cleanup() {
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$APP" 2>/dev/null || true
    pluginkit -r "$APP/Contents/PlugIns/MDViewQuickLook.appex" 2>/dev/null || true
}
trap cleanup EXIT

WORK=$(mktemp -d /tmp/mdview-workspace.XXXXXX)
ROOT="$WORK/projekt"
REPORT="$WORK/report.json"
mkdir -p "$ROOT/docs" "$ROOT/node_modules/balik" "$ROOT/.git"
printf '# Projekt\n' > "$ROOT/README.md"
printf '# Návod\n' > "$ROOT/docs/navod.md"
printf '# Ignorovat\n' > "$ROOT/node_modules/balik/README.md"
printf '# Ignorovat\n' > "$ROOT/.git/x.md"
printf 'není markdown\n' > "$ROOT/poznamky.txt"

pkill -f "$APP/Contents/MacOS/MDView" 2>/dev/null || true
sleep 0.5
open -n -g -a "$APP" "$ROOT" --args -MDViewSelfTestWorkspaceReport "$REPORT" -ApplePersistenceIgnoreState YES
for _ in $(seq 1 60); do
    [ -f "$REPORT" ] && break
    sleep 0.5
done
[ -f "$REPORT" ] || { echo "Self-test pracovní složky nevytvořil report do 30 s" >&2; exit 1; }
cat "$REPORT"

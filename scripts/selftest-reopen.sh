#!/bin/bash
# Self-test znovuotevření (Debug build): první spuštění otevře dva soubory a pracovní složku a ukončí se,
# druhé spuštění bez souborů musí samo otevřít poslední dva (limit 2, bez panelu Otevřít). Používá vlastní klíč
# v předvolbách, seznam uživatele nečte ani nemění.
set -euo pipefail

APP="$HOME/Library/Caches/MDView/DerivedData/Build/Products/Debug/MDView.app"
cleanup() {
    defaults delete cz.elvisek.mdview MDViewSelfTestLastDocuments 2>/dev/null || true
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$APP" 2>/dev/null || true
    pluginkit -r "$APP/Contents/PlugIns/MDViewQuickLook.appex" 2>/dev/null || true
}
trap cleanup EXIT

WORK=$(mktemp -d /tmp/mdview-reopen.XXXXXX)
mkdir -p "$WORK/slozka"
printf '# Poznámky\n' > "$WORK/poznamky.md"
printf '# Plán\n' > "$WORK/plan.md"
printf '# Ve složce\n' > "$WORK/slozka/README.md"
REPORT="$WORK/report.json"
ARGS=(-MDViewSelfTestReopen "$REPORT" -MDViewSelfTestReopenCount 3 -reopenLimit 2 -ApplePersistenceIgnoreState YES)

pkill -f "$APP/Contents/MacOS/MDView" 2>/dev/null || true
sleep 0.5
open -n -g -W -a "$APP" "$WORK/poznamky.md" "$WORK/plan.md" "$WORK/slozka" --args "${ARGS[@]}" -MDViewSelfTestReopenPhase 1
open -n -g -a "$APP" --args "${ARGS[@]}" -MDViewSelfTestReopenPhase 2
for _ in $(seq 1 40); do
    [ -f "$REPORT" ] && break
    sleep 0.5
done
[ -f "$REPORT" ] || { echo "Self-test znovuotevření nevytvořil report do 20 s" >&2; exit 1; }
cat "$REPORT"

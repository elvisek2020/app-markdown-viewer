#!/bin/bash
# Self-test znovuotevření (Debug build): první spuštění otevře dva soubory a pracovní složku a ukončí se,
# druhé spuštění bez souborů musí samo otevřít poslední dva (limit 2, bez panelu Otevřít), třetí se souborem
# (jako z Finderu) otevře poslední dva a k nim nový soubor, který musí zůstat vpředu. Používá vlastní klíč
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
printf '# Nový\n' > "$WORK/novy.md"
printf '# Ve složce\n' > "$WORK/slozka/README.md"
ARGS=(-MDViewSelfTestReopenCount 3 -reopenLimit 2 -ApplePersistenceIgnoreState YES)

pkill -f "$APP/Contents/MacOS/MDView" 2>/dev/null || true
sleep 0.5
wait_report() {
    for _ in $(seq 1 40); do
        [ -f "$1" ] && return 0
        sleep 0.5
    done
    echo "Self-test znovuotevření nevytvořil report $1 do 20 s" >&2
    exit 1
}

open -n -g -W -a "$APP" "$WORK/poznamky.md" "$WORK/plan.md" "$WORK/slozka" --args "${ARGS[@]}" \
    -MDViewSelfTestReopen "$WORK/phase1.json" -MDViewSelfTestReopenPhase 1
open -n -g -W -a "$APP" --args "${ARGS[@]}" -MDViewSelfTestReopen "$WORK/phase2.json" -MDViewSelfTestReopenPhase 2
wait_report "$WORK/phase2.json"
open -n -g -W -a "$APP" "$WORK/novy.md" --args "${ARGS[@]}" -MDViewSelfTestReopenExtra 1 \
    -MDViewSelfTestReopen "$WORK/phase3.json" -MDViewSelfTestReopenPhase 3
wait_report "$WORK/phase3.json"
python3 -c 'import json, sys; print(json.dumps({"phase2": json.load(open(sys.argv[1])), "phase3": json.load(open(sys.argv[2]))}, ensure_ascii=False, indent=2))' "$WORK/phase2.json" "$WORK/phase3.json"

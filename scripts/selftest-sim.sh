#!/bin/bash
# Zátěžový test auto-reloadu v reálné aplikaci (Debug build): otevře soubor, pustí všechny
# scénáře agent-sim.sh a změří, za jak dlouho náhled ukáže finální revizi.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
APP="$HOME/Library/Caches/MDView/DerivedData/Build/Products/Debug/MDView.app"
WORK=$(mktemp -d /tmp/mdview-sim.XXXXXX)
FILE="$WORK/agent.md"
STATUS="$WORK/status.jsonl"
SCENARIO=${1:-all}

echo "# Simulace agenta – revize 0" > "$FILE"
pkill -f "$APP/Contents/MacOS/MDView" 2>/dev/null || true
sleep 0.5
open -n -g -a "$APP" "$FILE" --args -MDViewSelfTestStatus "$STATUS" -ApplePersistenceIgnoreState YES
for _ in $(seq 1 40); do [ -s "$STATUS" ] && break; sleep 0.25; done

OUTPUT=$("$ROOT/scripts/agent-sim.sh" "$FILE" "$SCENARIO")
echo "$OUTPUT"
# Čas posledního zápisu souboru (mtime v ms) – od něj se měří zpoždění náhledu.
FINISHED=$(python3 -c 'import os,sys; print(int(os.stat(sys.argv[1]).st_mtime*1000))' "$FILE")
FINAL=$(echo "$OUTPUT" | sed -n 's/.*Revize \([0-9]*\)“.*/\1/p' | tail -1)

for _ in $(seq 1 40); do
    if grep -q "Revize $FINAL\"" "$STATUS"; then break; fi
    sleep 0.1
done

python3 - "$STATUS" "$FINAL" "$FINISHED" <<'PY'
import json, sys
path, final, finished = sys.argv[1], sys.argv[2], int(sys.argv[3])
rows = [json.loads(line) for line in open(path) if line.strip()]
# Dokument končí odstavcem „Revize N“ – teprve ten znamená, že náhled má celý finální obsah.
hit = next((r for r in rows if r["tail"].endswith(f"Revize {final}")), None)
banners = [r for r in rows if r["banner"]]
empty = [r for r in rows if r["blocks"] == 0]
print(f"aktualizací náhledu: {len(rows)}")
print(f"finální revize {final}: {'ANO' if hit else 'NE'}", end="")
print(f", zpoždění od posledního zápisu: {hit['t'] - finished} ms" if hit else "")
print(f"stav posledního zápisu: {rows[-1]['h1']!r}, banner: {rows[-1]['banner']!r}")
print(f"banner „smazáno“ se objevil: {len(banners)}×; prázdný náhled: {len(empty)}×")
PY
pkill -f "$APP/Contents/MacOS/MDView" 2>/dev/null || true

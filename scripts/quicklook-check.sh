#!/bin/bash
# Ověří Quick Look náhled nainstalované aplikace přes `qlmanage -p` (krátce se otevře okno náhledu).
# Rozšíření zapisuje diagnostiku do systémového logu, když existuje /tmp/mdview-quicklook-diagnostics.
# Kontroluje: registraci (jediná, z /Applications), vykreslení, izolaci JS, rychlost a blokování sítě.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d /tmp/mdview-ql.XXXXXX)
FLAG=/tmp/mdview-quicklook-diagnostics
LIMIT_MS=${LIMIT_MS:-500}
touch "$FLAG"
trap 'rm -f "$FLAG"; pkill -x qlmanage 2>/dev/null || true' EXIT

echo "== Registrace"
# Hned po `pluginkit -a` (make install) databáze rozšíření ještě nemusí registraci znát – na CI chvíli trvá.
: > "$WORK/registration.txt"
for _ in $(seq 1 30); do
    pluginkit -m -D -vv -p com.apple.quicklook.preview | grep -A2 "cz.elvisek.mdview.quicklook" > "$WORK/registration.txt" && break
    sleep 0.5
done
cat "$WORK/registration.txt"

cp "$ROOT/Samples/showcase.md" "$WORK/showcase.md"
cp -R "$ROOT/Samples/img" "$WORK/img"
# ~100 KB dokument (opakovaná ukázka bez front matteru).
python3 - "$ROOT/Samples/showcase.md" "$WORK/big.md" <<'PY'
import sys
text = open(sys.argv[1]).read().split("---\n", 2)[2]
with open(sys.argv[2], "w") as out:
    while out.tell() < 100_000:
        out.write(text + "\n")
PY
printf '# Vzdálený obrázek\n\n![badge](https://img.shields.io/badge/a-b-green.svg)\n' > "$WORK/remote.md"

preview() {
    local file=$1
    local since
    since=$(date "+%Y-%m-%d %H:%M:%S")
    qlmanage -p "$file" >/dev/null 2>&1 &
    local pid=$!
    local report=""
    for _ in $(seq 1 30); do
        sleep 0.5
        report=$(/usr/bin/log show --start "$since" --style compact --predicate 'subsystem == "cz.elvisek.mdview"' 2>/dev/null \
            | grep "MDVIEW-QL-REPORT" | grep "\"file\":\"$(basename "$file")\"" | tail -1 | sed -E 's/.*MDVIEW-QL-REPORT //') || true
        [ -n "$report" ] && break
    done
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    # Panel Quick Look se zavírá asynchronně; další náhled hned po něm by se nemusel spustit.
    sleep 1.5
    echo "$report"
}

echo "== Náhledy"
preview "$WORK/showcase.md" > "$WORK/showcase.json"
preview "$WORK/big.md" > "$WORK/big.json"
preview "$WORK/remote.md" > "$WORK/remote.json"

python3 - "$WORK" "$LIMIT_MS" <<'PY'
import json, sys
work, limit = sys.argv[1], int(sys.argv[2])
failures = []

def load(name):
    try:
        return json.load(open(f"{work}/{name}.json"))
    except Exception:
        return {}

def check(name, condition, detail=None):
    print(("✓ " if condition else "✘ ") + name)
    if not condition:
        failures.append(name)
        if detail is not None:
            print(f"    detail: {json.dumps(detail, ensure_ascii=False)}")

registration = open(f"{work}/registration.txt").read()
check("jediná registrace, povolená, z /Applications",
      registration.count("cz.elvisek.mdview.quicklook") == 1 and registration.lstrip().startswith("+")
      and "/Applications/MDView.app" in registration, registration)

showcase = load("showcase")
probe = showcase.get("probe", {})
check("náhled ukázky: KaTeX, kód, alerts s ikonami, obrázek",
      probe.get("katex", 0) >= 4 and probe.get("hljs", 0) >= 2 and probe.get("alerts") == 5
      and probe.get("images", 0) >= 1 and probe.get("imagesLoaded") == probe.get("images"), showcase)
check("JS z dokumentu neběží", probe.get("pwned") is False, probe)
check(f"ukázka do {limit} ms", 0 < showcase.get("renderMs", 0) < limit, showcase.get("renderMs"))

big = load("big")
check(f"100 KB soubor do {limit} ms", big.get("bytes", 0) >= 100_000 and 0 < big.get("renderMs", 0) < limit,
      {k: big.get(k) for k in ("bytes", "renderMs")})

remote = load("remote").get("probe", {})
check("obrázky z internetu blokované (žádné síťové požadavky)",
      remote.get("blockedRemote") == 1 and remote.get("imagesLoaded") == 0, remote)

if failures:
    sys.exit(f"\nSelhalo: {len(failures)}")
print("\nQuick Look: všechny kontroly prošly.")
PY

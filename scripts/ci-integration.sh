#!/bin/bash
# Integrační testy v reálné aplikaci (Debug build) – v CI i lokálně:
#   1. self-test náhledu na Samples/showcase.md (izolace JS, KaTeX, Mermaid, obrázky, reconciliation,
#      poslední platná verze rozbitého diagramu)
#   2. Samples/security.md nic nespustí
#   3. zátěž auto-reloadu (všechny scénáře agent-sim.sh)
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
LIMIT_MS=${LIMIT_MS:-1000}
WORK=$(mktemp -d /tmp/mdview-ci.XXXXXX)

echo "== Self-test náhledu"
"$ROOT/scripts/selftest.sh" "$ROOT/Samples/showcase.md" > "$WORK/showcase.json"
echo "== Bezpečnostní dokument"
"$ROOT/scripts/selftest.sh" "$ROOT/Samples/security.md" > "$WORK/security.json"
echo "== Zátěž auto-reloadu"
"$ROOT/scripts/selftest-sim.sh" | tee "$WORK/sim.txt"

python3 - "$WORK" "$LIMIT_MS" <<'PY'
import json, re, sys
work, limit = sys.argv[1], int(sys.argv[2])
failures = []

def check(name, condition):
    print(("✓ " if condition else "✘ ") + name)
    if not condition:
        failures.append(name)

r = json.load(open(f"{work}/showcase.json"))
p1, p2, p3 = r.get("phase1", {}), r.get("phase2", {}), r.get("phase3", {})
check("JS z dokumentu neběží", p1.get("pwnedByInlineHandler") is False)
check("page world nevidí app.js", r.get("pageWorldSeesMdv") == "undefined")
check("KaTeX vykreslen bez chyb", p1.get("katex", 0) >= 4 and p1.get("katexErrors") == 0 and p1.get("katexFontReady"))
check("Mermaid vykreslen", p1.get("mermaidSvg", 0) >= 1 and not p1.get("mermaidErrors"))
check("zvýraznění kódu", p1.get("hljs", 0) >= 2)
check("alerts s ikonami, footnotes, task listy, front matter",
      p1.get("alerts") == 5 and p1.get("alertIcons") == 5 and p1.get("footnotes") and p1.get("taskItems") == 3 and p1.get("frontMatter"))
check("lokální obrázky přes mdv-file", bool(p1.get("images")) and all(i["loaded"] for i in p1["images"]))
check("změna souboru nepřerenderuje diagram", isinstance(p2, dict) and p2.get("mermaidReused", 0) >= 1)
check("rozbitý diagram ukazuje poslední platnou verzi", isinstance(p3, dict) and p3.get("mermaidStale", 0) >= 1)
theme = r.get("themeSwitch", {})
check("přepnutí vzhledu překreslí diagram", isinstance(theme, dict) and theme.get("mermaidSvg", 0) >= 1 and theme.get("mermaidReused") == 0)

f3 = r.get("f3", {})
check("hledání (i bez diakritiky)", f3.get("findPozn", 0) >= 3 and f3.get("findWithoutDiacritics", 0) >= 1 and f3.get("findMissing") == 0)
html = f3.get("html", {})
check("export HTML: bez skriptů, vložené fonty a obrázky",
      isinstance(html, dict) and html.get("scripts") == 0 and html.get("svg") and html.get("katexFonts")
      and html.get("inlinedImage") and html.get("mdvURLs") == 0 and not html.get("sourcepos"))
pdf = f3.get("pdf", {})
check("export PDF: stránkovaný a s poslední stranou", isinstance(pdf, dict) and pdf.get("pages", 0) >= 2 and pdf.get("lastPageHasEnd"))
sync = f3.get("sync", {})
check("skok na nadpis zarovná zdroj na stejný řádek", f3.get("sourceReady") and abs(sync.get("sourceTop", 0) - sync.get("alerts", -9)) <= 0.5)
check("synchronizace zdroj → náhled", sync.get("previewAfterSource") == sync.get("table"))

s = json.load(open(f"{work}/security.json"))["phase1"]
check("security.md: žádné skripty, iframy, formuláře",
      s.get("scripts") == 0 and s.get("iframes") == 0 and s.get("forms") == 0 and s.get("pwnedByInlineHandler") is False)

sim = open(f"{work}/sim.txt").read()
match = re.search(r"finální revize \d+: ANO, zpoždění od posledního zápisu: (-?\d+) ms", sim)
check(f"auto-reload: finální obsah do {limit} ms", bool(match) and int(match.group(1)) < limit)
check("auto-reload: žádný prázdný náhled", "prázdný náhled: 0×" in sim)

if failures:
    sys.exit(f"\nSelhalo: {len(failures)}")
print("\nVšechny integrační kontroly prošly.")
PY

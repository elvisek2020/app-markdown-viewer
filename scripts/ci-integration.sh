#!/bin/bash
# Integrační testy v reálné aplikaci (Debug build) – v CI i lokálně:
#   1. self-test náhledu na Samples/showcase.md (izolace JS, KaTeX, Mermaid, obrázky, reconciliation,
#      poslední platná verze rozbitého diagramu)
#   2. Samples/security.md nic nespustí
#   3. zátěž auto-reloadu (všechny scénáře agent-sim.sh)
#   4. pracovní složka, paměť okna, režim úprav (ukládání, konflikt se zápisem agenta)
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
echo "== Pracovní složka"
"$ROOT/scripts/selftest-workspace.sh" > "$WORK/workspace.json"
echo "== Paměť okna"
"$ROOT/scripts/selftest-window.sh" > "$WORK/window.json"
echo "== Režim úprav"
"$ROOT/scripts/selftest-edit.sh" > "$WORK/edit.json"
echo "== Znovuotevření"
"$ROOT/scripts/selftest-reopen.sh" > "$WORK/reopen.json"

python3 - "$WORK" "$LIMIT_MS" <<'PY'
import json, re, sys
work, limit = sys.argv[1], int(sys.argv[2])
failures = []

def check(name, condition, detail=None):
    print(("✓ " if condition else "✘ ") + name)
    if not condition:
        failures.append(name)
        if detail is not None:
            print(f"    detail: {json.dumps(detail, ensure_ascii=False)}")

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
check("zvýraznění změny: jen připsaný odstavec + skok na poslední změnu",
      isinstance(p2, dict) and p2.get("changed") == ["Přidaný odstavec self-testu."] and r.get("jumpToLastChange") == "true",
      {"changed": p2.get("changed") if isinstance(p2, dict) else None, "jump": r.get("jumpToLastChange")})
theme = r.get("themeSwitch", {})
check("přepnutí vzhledu překreslí diagram", isinstance(theme, dict) and theme.get("mermaidSvg", 0) >= 1 and theme.get("mermaidReused") == 0)

f3 = r.get("f3", {})
check("hledání (i bez diakritiky)", f3.get("findPozn", 0) >= 3 and f3.get("findWithoutDiacritics", 0) >= 1 and f3.get("findMissing") == 0)
html = f3.get("html", {})
check("export HTML: bez skriptů, vložené fonty a obrázky",
      isinstance(html, dict) and html.get("scripts") == 0 and html.get("svg") and html.get("katexFonts")
      and html.get("inlinedImage") and html.get("mdvURLs") == 0 and not html.get("sourcepos"), html)
pdf = f3.get("pdf", {})
check("export PDF: stránkovaný, celý obsah až po poslední stranu",
      isinstance(pdf, dict) and pdf.get("pages", 0) >= 2 and pdf.get("lastPageHasFinalText") and pdf.get("hasEnd"), pdf)
sync = f3.get("sync", {})
check("skok na nadpis zarovná zdroj na stejný řádek", f3.get("sourceReady") and abs(sync.get("sourceTop", 0) - sync.get("alerts", -9)) <= 0.5, sync)
check("synchronizace zdroj → náhled", sync.get("previewAfterSource") == sync.get("table"), sync)

w = json.load(open(f"{work}/workspace.json"))
check("pracovní složka: strom bez node_modules/.git, výchozí README", w.get("fileCount") == 2 and w.get("initial") == "README.md", w)
check("pracovní složka: sledování přepne na nový soubor agenta",
      w.get("followed") == "agent/vystup.md" and w.get("followedTitle") == "Výstup agenta", w)
check("pracovní složka: režim úprav pokračuje v dalším souboru, sledování v něm nepřepíná",
      w.get("editCarriedOver") is True and w.get("followPausedWhileEditing") is True, w)

win = json.load(open(f"{work}/window.json"))
check("paměť okna: nové okno dostane rám naposledy zavřeného, další dokument jako panel",
      win.get("reopened") == win.get("target") and win.get("thirdTabbedWithSecond") is True, win)

e = json.load(open(f"{work}/edit.json"))
check("úpravy: editor místo zdrojového panelu, fokus v editoru",
      e.get("editing") and e.get("editorFocused") and e.get("sourcePaneHidden"), e)
check("úpravy: psaní hned v náhledu, uložení až po chvíli, vlastní zápis bez reloadu",
      e.get("previewLive") and e.get("notSavedImmediately") and e.get("autosaved") and e.get("ownWriteIgnored"), e)
check("úpravy: ⌘S a ⌥⌘E vede editor do náhledu, ⌘S uloží hned, menu se zpět a schránkou",
      e.get("commandsRouteToPreview") and e.get("saveCommand") and e.get("editMenu") and e.get("undo"), e)
check("úpravy: zápis agenta bez neuložených úprav se tiše načte, kurzor zůstane",
      e.get("silentReload") and e.get("silentReloadNoBanner") and e.get("caretKept") and e.get("reloadPreview"), e)
check("úpravy: konflikt s agentem – banner, soubor se nepřepíše, porovnání",
      e.get("conflict") and e.get("conflictBanner") and e.get("conflictNoOverwrite") and e.get("conflictPreviewShowsMine") and e.get("diffSheet"), e)
check("úpravy: konflikt – ponechat moje / načíst z disku",
      e.get("keptMine") and e.get("conflict2") and e.get("tookDisk") and e.get("tookDiskPreview"), e)
check("úpravy: synchronizace posunu editor ↔ náhled",
      abs(e.get("syncPreviewLine", 0) - e.get("syncEditorLine", -9)) <= 1 and abs(e.get("syncBackEditorLine", 0) - 150) <= 1, e)
check("úpravy: vypnutí režimu uloží rozepsané", e.get("finished") and e.get("savedOnFinish"), e)
check("úpravy: přepínač Zdroj | Upravit (rovnou mezi režimy, vypnutí), zabarvená lišta",
      e.get("switchShowsEdit") and e.get("editTint") and e.get("clickEdit") and e.get("clickSourceWhileEditing")
      and e.get("clickEditWhileSource") and e.get("clickEditOff"), e)

ro = json.load(open(f"{work}/reopen.json"))
check("znovuotevření: po dalším spuštění poslední dva ze tří (limit 2), bez panelu Otevřít",
      len(ro.get("reopened", [])) == 2 and set(ro["reopened"]) <= {"poznamky.md", "plan.md", "slozka"}
      and ro.get("openPanelShown") is False, ro)

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

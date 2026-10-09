# Rozhodnutí

Záznam architektonických rozhodnutí a výsledků spiků. Plné zdůvodnění je v [PLAN.md](PLAN.md).

| # | Rozhodnutí | Stav |
|---|---|---|
| D1 | Okna: AppKit lifecycle + read-only `NSDocument` (ne `DocumentGroup`) | přijato, ověří S4 |
| D2 | Parser: cmark-gfm přes `swiftlang/swift-cmark` `exact: 0.9.0` | přijato |
| D3 | Matika: C syntax extension v inline parseru (`CMarkMath`), ne textový pre-pass | implementováno (S2) |
| D4 | Alerts a kotvy nadpisů: AST transformace ve Swiftu (custom block / custom inline) | implementováno |
| D5 | Front matter: řádky nahrazeny prázdnými (sourcepos sedí), režimy tabulka / sbalené / skryté | implementováno |
| D6 | Watcher: FSEvents na rodičovském adresáři + kqueue na aktuálním inode + stat signatura + pojistný polling | implementováno (S3) |
| D7 | WebView: `allowsContentJavaScript = false`, skripty aplikace v dedikovaném `WKContentWorld` | ověřeno (S1) |
| D8 | Zdrojový panel ve stejném WKWebView (ne TextKit 2) | přijato |
| D9 | Podpis: Apple Development (Personal Team) bez provisioning profilu, záloha self-signed | čeká na S5 |
| D10 | Testy: Swift Testing (CLT nemají XCTest) | přijato |
| D12 | Vendor JS: verze starší než 2 týdny (supply chain); mermaid 11.17.2 místo čerstvé 12.0.0, npm v `~/Library/Caches` s `--ignore-scripts` | přijato |
| D13 | Main menu z Xcode šablony `MainMenuDoc.xib`, přeložené do češtiny (systémové Open Recent funguje bez hacků) | přijato |
| D14 | Golden testy: GitHub API v režimu gfm (alerts, matika, Mermaid) + slugy z režimu markdown, porovnání po sémantické normalizaci | implementováno |
| D15 | Emoji zkratky jen jako samostatná slova (GitHub API se chová nekonzistentně, `a:b:c` nesmí být 🅱️) | přijato |
| D16 | Mermaid líně (IntersectionObserver), při chybě poslední platná verze s odznakem | implementováno |
| D17 | Ikona kreslená skriptem (`scripts/make-icon.swift`), snímky do README přes Debug self-test | přijato |
| D11 | Build výstupy mimo repo (`~/Library/Caches/MDView`), protože `~/Documents` synchronizuje iCloud a xattr rozbíjejí codesign | přijato |

## Spiky

| Spike | Cíl | Výsledek |
|---|---|---|
| S1 | Izolace JS (isolated world, Mermaid, KaTeX fonty, CSS Highlight API) | Hotovo přes `scripts/selftest.sh` (Debug self-test v reálném WKWebView): inline handler vložený mimo DOMPurify neběží, page world nevidí `mdv`, Mermaid 11 se v isolated worldu vykreslí, KaTeX včetně fontů přes `mdv-asset`, CSS Highlight API dostupné, obrázky přes `mdv-file`. Po změně souboru zůstává tentýž SVG uzel diagramu (reconciliation). |
| S2 | Matika a věrnost GitHubu | Hotovo: C extension + 48 testů rendereru (matika vč. `$5 a $10`, code spanů, `\$`, odsazeného kódu, tabulky, citace a seznamu; alerts, slugy, front matter, sourcepos). Golden testy proti `gh api markdown` zbývají. |
| S3 | Watcher | Hotovo: 13 testů stabilně zelených (5× po sobě). **Zjištění:** FSEvents hlásí změnu obsahu až při zavření souboru, ne při každém `write()`. Streamování do otevřeného souboru proto zachytí kqueue `DispatchSource` na drženém fd. **Zátěž v aplikaci** (`scripts/selftest-sim.sh`, 8 scénářů včetně 500 atomických zápisů): finální obsah 84–186 ms po posledním zápisu, žádné prázdné bliknutí, banner jen u smazání delšího než grace perioda. Zátěžový test našel chybu: po „přesunu pryč a zpět“ watcher zůstal na dočasné cestě; opraveno (návrat na původní cestu + ověření inode u přejmenování), pokryto testem. |
| S4 | `NSDocument` jako viewer | — |
| S5 | Quick Look, podpis, TCC | — |
| S6 | Stránkování PDF | — |

## Golden testy (F2)

45 fixtures v `Packages/MarkdownCore/Tests/MarkdownCoreTests/Fixtures/golden`:
- **43 se shoduje s GitHubem přesně.**
- **Dva rozdíly jsou záměrné:**
  - `$$` odstavec: GitHub zpracuje `\,` jako markdown escape a TeX poškodí, MDView ho zachová.
  - Escapované `\$x\$`: GitHub z nich udělá matiku, MDView je respektuje jako escape.
- **Kotvy nadpisů** se shodují ve všech fixtures.
- **Chyba nalezená golden testy:** inline matika `$5 …` přeskočila do code spanu. Opraveno, inline matika nesmí přeskočit backtick.

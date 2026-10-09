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
| D7 | WebView: `allowsContentJavaScript = false`, skripty aplikace v dedikovaném `WKContentWorld` | čeká na S1 |
| D8 | Zdrojový panel ve stejném WKWebView (ne TextKit 2) | přijato |
| D9 | Podpis: Apple Development (Personal Team) bez provisioning profilu, záloha self-signed | čeká na S5 |
| D10 | Testy: Swift Testing (CLT nemají XCTest) | přijato |
| D11 | Build výstupy mimo repo (`~/Library/Caches/MDView`), protože `~/Documents` synchronizuje iCloud a xattr rozbíjejí codesign | přijato |

## Spiky

| Spike | Cíl | Výsledek |
|---|---|---|
| S1 | Izolace JS (isolated world, Mermaid, KaTeX fonty, CSS Highlight API) | — |
| S2 | Matika a věrnost GitHubu | Hotovo: C extension + 48 testů rendereru (matika vč. `$5 a $10`, code spanů, `\$`, odsazeného kódu, tabulky, citace a seznamu; alerts, slugy, front matter, sourcepos). Golden testy proti `gh api markdown` zbývají. |
| S3 | Watcher | Hotovo: 13 testů stabilně zelených (5× po sobě). **Zjištění:** FSEvents hlásí změnu obsahu až při zavření souboru, ne při každém `write()`. Streamování do otevřeného souboru proto zachytí kqueue `DispatchSource` na drženém fd. 10min stres test přes `scripts/agent-sim.sh` zbývá s aplikací. |
| S4 | `NSDocument` jako viewer | — |
| S5 | Quick Look, podpis, TCC | — |
| S6 | Stránkování PDF | — |

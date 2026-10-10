# MDView – pokyny pro agenty

Nativní Markdown **viewer** s jednoduchým režimem úprav pro macOS 15+ na Apple Silicon. Plán a fáze: `docs/PLAN.md`, rozhodnutí: `docs/DECISIONS.md` (režim úprav: D32).

## Příkazy

```bash
make test        # testy jádra (renderer, watcher, politika odkazů) přes swift test
make test-watch  # jen watcher
make build       # XcodeGen + Debug build aplikace
make install     # Release build → /Applications/MDView.app + symlink mdv do /opt/homebrew/bin
make vendor      # aktualizace vendorovaných JS/CSS podle web-vendor/package.json

scripts/selftest.sh [soubor.md] [args]  # Debug self-test náhledu bez UI → JSON report (izolace JS, KaTeX, Mermaid, obrázky)
scripts/selftest-sim.sh [scénář]        # zátěž auto-reloadu v reálné aplikaci, měří zpoždění náhledu
scripts/ci-integration.sh               # obojí + bezpečnostní dokument s kontrolami (běží i v CI)
scripts/gh-golden.sh [fixture]          # referenční výstupy GitHub API pro golden testy (po změně fixtures)
scripts/readme-images.sh                # ikona + snímky náhledu do README (docs/images)
scripts/quicklook-check.sh              # Quick Look nainstalované aplikace (po make install)
scripts/selftest-workspace.sh           # pracovní složka: strom, výchozí výběr, režim sledování
scripts/selftest-edit.sh                # režim úprav: ukládání, tichý reload, konflikt se zápisem agenta
scripts/selftest-window.sh              # paměť pozice a velikosti okna
make ql-status                          # registrace Quick Look rozšíření
```

Ověřování UI dělej přes self-testy (`App/Web/SelfTest.swift`, jen Debug), ne přes ovládání obrazovky.

**Nikdy nebuildit do repa.** Projekt leží v `~/Documents`, který synchronizuje iCloud Drive; buildové výstupy tam dostanou xattr od File Provideru a `codesign` selže. SwiftPM proto vždy s `--scratch-path ~/Library/Caches/MDView/spm` (dělá `Makefile`), Xcode používá DerivedData v `~/Library`.

## Architektura

- `Packages/MarkdownCore` – lokální SPM balíček, vše testovatelné přes `swift test`:
  - `CMarkMath` – C syntax extension pro cmark-gfm (`$…$`, `$$…$$`, `` $`…`$ ``)
  - `MarkdownCore` – `MarkdownRenderer.render(_:options:)` → HTML s `data-sourcepos`, outline, front matter, features; GitHub alerts a kotvy nadpisů jako AST transformace
  - `FileWatch` – `FileWatcher` (FSEvents na rodičovském adresáři + kqueue na inode + stat signatura + pojistný polling; po přesunu pryč a zpět se vrací na původní cestu), `EditSync` (stav disk ↔ editor: vlastní zápisy, tichý reload, konflikt)
  - `WebAssets` – šablona, `app.css`, `app.js` (reconciliation bloků, kotva scrollu, Mermaid/KaTeX/hljs) a vendorované knihovny
- `App/` – AppKit + `NSDocument` (`MarkdownDocument`; ukládá `DocumentModel`, ne NSDocument), `DocumentModel` (watcher + render na pozadí, víc odběratelů, v režimu úprav automatické ukládání), `DocumentWindowController` (osnova ve SwiftUI | náhled, nástrojová lišta), `PreviewController` (+Find, +Export, +Edit; WKWebView, isolated world `mdview`, `allowsContentJavaScript = false`), scheme handlery `mdv-asset://` a `mdv-file://`, `LinkOpener`, `HTMLExporter`, `Preferences` + okno Nastavení
- `App/Editor/` – režim úprav: `MarkdownEditor` (`NSTextView`, TextKit 1, vzniká až při zapnutí – start aplikace nesmí zpomalit), `PreviewContainerView` (banner + split editor | náhled), `EditBanner`, `DiffSheet`. Kód volaný tiskem na pozadí (předci webview) musí být `nonisolated`.
- Debug build sdílí bundle ID a předvolby s nainstalovanou aplikací – self-testy nesmí zapisovat do UserDefaults (rámy oken apod.).
- `App/Workspace/` – pracovní složka (`WorkspaceDocument` pro `public.folder`, `WorkspaceWindowController` se stromem ve SwiftUI a režimem sledování, `ViewerDocumentController` pro výběr složek v Otevřít…); index a hlídání složky jsou ve FileWatch (`FolderIndex`, `FolderWatcher`).
- Cesty v pracovní složce vždy přes `resolvingSymlinksInPath()` (FSEvents hlásí `/private/var…`, URL normalizace `/private` odstraňuje).
- `QuickLook/` – Quick Look rozšíření (`MDViewQuickLook.appex`), sdílí `App/Web/PreviewSupport.swift` a `SchemeHandlers.swift`. Spuštěné buildy z DerivedData se registrují u LaunchServices; self-test skripty a `make install` je odregistrují, aby rozšíření nesoupeřilo s nainstalovaným.
- Systémový log: v zsh je `log` vestavěný příkaz – vždy `/usr/bin/log show …`.
- `CLI/mdv` se kopíruje do `MDView.app/Contents/Resources/bin`
- Parser je `swiftlang/swift-cmark` pinovaný na přesnou verzi, `Package.resolved` je v gitu.
- Verze aplikace = čas buildu RRRRMMDD.HHMM; dosazuje ji `Makefile` (`MARKETING_VERSION` i `CURRENT_PROJECT_VERSION`), ručně se nikde nemění.

## Konvence

- Komentáře a texty UI česky, identifikátory anglicky.
- Testy ve **Swift Testing** (`import Testing`), ne XCTest.
- Změna renderingu → `make test` (golden testy proti GitHubu musí projít; záměrné rozdíly patří do `GoldenTests.knownDifferences` s důvodem).
- CI (`.github/workflows/ci.yml`, macos-26) spouští testy, build i `scripts/ci-integration.sh`.
- Swift 6 strict concurrency. `FileWatcher` drží stav na vlastní sériové frontě a handler volá na ní.
- Bezpečnost: z dokumentu nikdy neběží JS a odkazy nikdy nic nespouštějí (viz `docs/PLAN.md`, sekce Bezpečnost odkazů). `Samples/security.md` musí zůstat neškodný.
- Řádky front matteru se před parsováním nahrazují prázdnými – čísla řádků v `data-sourcepos` musí vždy odpovídat původnímu souboru (scroll sync).

# MDView – pokyny pro agenty

Nativní Markdown **viewer** (bez editoru) pro macOS 15+ na Apple Silicon. Plán a fáze: `docs/PLAN.md`, rozhodnutí: `docs/DECISIONS.md`.

## Příkazy

```bash
make test        # testy jádra (renderer + watcher) přes swift test
make test-watch  # jen watcher
make sim         # simulace zápisů agenta do /tmp/mdview-agent.md (SIM_FILE=…)
```

**Nikdy nebuildit do repa.** Projekt leží v `~/Documents`, který synchronizuje iCloud Drive; buildové výstupy tam dostanou xattr od File Provideru a `codesign` selže. SwiftPM proto vždy s `--scratch-path ~/Library/Caches/MDView/spm` (dělá `Makefile`), Xcode používá DerivedData v `~/Library`.

Aplikační targety (XcodeGen `project.yml`, `make build/install`) přibudou ve fázi F1.

## Architektura

- `Packages/MarkdownCore` – lokální SPM balíček, vše testovatelné přes `swift test`:
  - `CMarkMath` – C syntax extension pro cmark-gfm (`$…$`, `$$…$$`, `` $`…`$ ``)
  - `MarkdownCore` – `MarkdownRenderer.render(_:options:)` → HTML s `data-sourcepos`, outline, front matter, features; GitHub alerts a kotvy nadpisů jako AST transformace
  - `FileWatch` – `FileWatcher` (FSEvents na rodičovském adresáři + stat signatura + pojistný polling)
- Parser je `swiftlang/swift-cmark` pinovaný na přesnou verzi, `Package.resolved` je v gitu.

## Konvence

- Komentáře a texty UI česky, identifikátory anglicky.
- Testy ve **Swift Testing** (`import Testing`), ne XCTest.
- Swift 6 strict concurrency. `FileWatcher` drží stav na vlastní sériové frontě a handler volá na ní.
- Bezpečnost: z dokumentu nikdy neběží JS a odkazy nikdy nic nespouštějí (viz `docs/PLAN.md`, sekce Bezpečnost odkazů). `Samples/security.md` musí zůstat neškodný.
- Řádky front matteru se před parsováním nahrazují prázdnými – čísla řádků v `data-sourcepos` musí vždy odpovídat původnímu souboru (scroll sync).

# MDView – nativní Markdown viewer pro macOS (Apple Silicon)

## Context

Rešerše (`compass_artifact…md`) ukazuje, že pro workflow „AI agent / Cursor zapisuje .md a já sleduji náhled“ jsou rozhodující tři věci: **spolehlivý tichý auto-reload** (přežije atomic save, rychlé série zápisů, smazání a znovuvytvoření, zachová scroll), **rendering věrný GitHubu** (GFM + footnotes + alerts + Mermaid + matika + front matter) a **synchronizovaný scroll zdroj ↔ náhled**. Existující aplikace to mají jen částečně (VS Code/Cursor mají bugy se zastaralým náhledem, MacDown 3000 používá starší Hoedown, Markout nehlídá soubor). Cílem je vlastní **viewer bez editoru**: nativní, offline, bezpečný (žádné spouštění odkazů ani JS z dokumentu, viz CVE-2019-12138/12173 původního MacDownu), s CLI `mdv` a Quick Look rozšířením.

Rozhodnutí uživatele: jen viewer (zdroj max. read-only), Xcode se doinstaluje, aplikace jen pro vlastní použití, kód v soukromém GitHub repu. Pracovní adresář je prázdný (greenfield).

Pracovní název **MDView**, CLI `mdv`, bundle id `cz.elvisek.mdview` (změnitelné v `project.yml`).

## Klíčová technická rozhodnutí

| Oblast | Volba | Proč |
|---|---|---|
| Platforma | macOS 15+, `ARCHS=arm64`, Swift 6 (app target `SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor`) | nic z návrhu nevyžaduje 26+, CI runnery mají Xcode 26.6 |
| Projekt | **XcodeGen** (`project.yml` v gitu, `.xcodeproj` v `.gitignore`) + `Makefile` + `Config/*.xcconfig` | textový projekt bezpečný pro editaci agentem |
| Okna | **AppKit lifecycle + read-only `NSDocument`**, `MainMenu.xib`, `NSSplitViewController` (TOC ve SwiftUI přes `NSHostingView` + WKWebView) | Open/Open Recent, taby, restorace, Finder/`open -a`, deduplikace a proxy ikona zdarma; `DocumentGroup(viewing:)` neumožňuje ovlivnit chování při externí změně a nehodí se pro budoucí folder workspace |
| Parser | **cmark-gfm** přes `swiftlang/swift-cmark` (pin `exact: "0.9.0"` nebo konkrétní revize z `gfm`), volby SOURCEPOS, FOOTNOTES, UNSAFE + extensions table, strikethrough, autolink, tagfilter, tasklist | stejný parser jako GitHub, `data-sourcepos` pro scroll sync, rychlý, sdílený s Quick Look |
| Matika | **vlastní C syntax extension** pro cmark (`$…$`, `$$…$$`, `` $`…`$ ``), ```` ```math ```` jako blok; KaTeX v JS | textový pre-pass by minul odsazený kód, HTML bloky, `\$`; extension zachová sourcepos a TeX projde doslova. Záloha: pre-pass řízený rozsahy code/HTML bloků z prvního parsu |
| Alerts, slugy, front matter | ve Swiftu nad AST (top-level blockquote → custom block; `<a id=slug>` podle GitHub algoritmu; front matter → stejný počet prázdných řádků + režim tabulka / sbalený YAML / skrýt) | testovatelné přes `swift test`, JS jen pro vizuální část |
| WebView | WKWebView, `WKWebsiteDataStore.nonPersistent()`, **`allowsContentJavaScript = false`**, všechny skripty aplikace jako `WKUserScript` / `callAsyncJavaScript` v dedikovaném `WKContentWorld`, DOMPurify s allowlistem jako GitHub, `WKContentRuleList` jako síťový kill-switch | JS z dokumentu nikdy neběží; ověřeno v hlavičkách SDK |
| Assety | schéma `mdv-asset://` (bundlované CSS/JS/fonty), `mdv-file://` (jen obrázky/video, `no-store`); **bez `<base href>`** – relativní URL se přepíšou v JS na `<template>` fragmentu | `<base>` rozbíjí `#kotvy` a footnotes |
| Aktualizace náhledu | HTML posílané jako argument `callAsyncJavaScript`; vlastní **keyed reconciliation top-level bloků** (klíč = hash bloku bez sourcepos) | nezměněné bloky (Mermaid, KaTeX, hljs) se nepřerenderují, žádné blikání |
| Scroll | kotva `{hash prvního viditelného bloku, relativní offset, startLine}`, re-aplikace přes ResizeObserver ~1 s; **follow tail** do 40 px od konce | agent často přepisuje sekce nad čtenou pozicí |
| Watcher | **FSEvents na rodičovském adresáři** (FileEvents, NoDefer, WatchRoot, latence 50 ms) + **kqueue na aktuálním inode** (FSEvents hlásí změnu obsahu až při zavření souboru – zjištěno v S3) + stat signatura + pojistný polling | kqueue/DispatchSource sleduje inode a po atomic save „odpadá“ (přesně bug MacDownu) |
| Zdrojový panel | druhý scroll kontejner **ve stejném WKWebView** (Swift řádkový highlighter → `<div data-line=N>`), sync v JS přes rAF | TextKit 2 odhaduje výšky, mapování řádek→y je nespolehlivé |
| Vendor JS/CSS | mermaid, katex, highlight.js, github-markdown-css, dompurify, octicons – pinované, **commitnuté** v `WebAssets/Resources/web/vendor`, npm jen pro aktualizaci (`web-vendor/update.sh`) | offline, reprodukovatelný build |
| Podpis | **Apple Development (bezplatný Personal Team) ručně, bez provisioning profilu**; záloha self-signed certifikát z Keychain Access | ad-hoc podpis mění identitu při každém buildu → macOS znovu žádá o přístup k `~/Documents` (TCC) |
| Testy | **Swift Testing** (`import Testing`) – CLT nemají XCTest | `swift test` funguje i bez Xcode a na CI |

## Algoritmus watcheru (srdce aplikace)

1. Při otevření vyřešit symlinky, uložit signaturu `(dev, ino, size, mtime_ns, ctime_ns)` a obsah; držet `O_EVTONLY` fd jen kvůli `F_GETPATH` při přejmenování.
2. FSEvents stream na rodičovský adresář, filtrovat `dirname == parentDir` nebo `fileID == lastIno` (rekurzivní šum z `.git`, `node_modules`). `RootChanged` → poll 1 s a nový stream; `*Dropped`/`MustScanSubDirs` → okamžitá kontrola.
3. Coalescer: trailing debounce 80–120 ms, max-wait 400 ms (průběžné aktualizace při dlouhém zápisu).
4. Kontrola: soubor chybí → 1,5 s grace bez banneru, pak `F_GETPATH` (přejmenování → retarget a aktualizace `fileURL`), jinak banner „smazáno, čekám“ a poslední render zůstává. Signatura stejná → nic. Změna → načíst; nesedí velikost stat vs. read → další kontrola; obsah stejný → jen signatura; nový prázdný a starý ne → počkat 200 ms (truncate+write). Neúplná UTF-8 sekvence na konci → odříznout a za 100 ms znovu. Změna inode → znovu otevřít fd.
5. Render na pozadí (actor) s generation counterem, zastaralé výsledky zahodit.
6. Pojistky: stat-poll 2 s při viditelném okně, kontrola při `didBecomeActive` a změně occlusion; síťový svazek (`volumeIsLocal == false`) → poll 1 s.

`NSDocument` overridy: `autosavesInPlace = false`, prázdné `read(from:ofType:)`, `presentedItemDidChange` bez `super` (jen šťouchne watcher), `presentedItemDidMove` se `super` + retarget, `accommodatePresentedItemDeletion` → `h(nil)` (okno zůstává); vypnout Duplicate/Rename/Move/Revert; `applicationShouldOpenUntitledFile` → `false`.

## Bezpečnost odkazů (allowlist)

- `#kotva` → scroll v JS. `.md`/`.markdown` jako regulární soubor (po vyřešení symlinku) → otevřít v MDView.
- Jiné `file:` → **jen Reveal in Finder**, nikdy `NSWorkspace.open` na file URL (.app, .command, .terminal, .webloc…).
- http/https/mailto → výchozí prohlížeč; ostatní schémata (`vscode://`…) jen po potvrzení s celou URL.
- `target=_blank` přes `WKUIDelegate` se stejnou politikou; stahování zrušeno; z kontextového menu pryč „Open Link in New Window“ a „Download…“.

## Struktura repa

```
010-app-markdown_viewer/
├─ project.yml, Makefile, CLAUDE.md, README.md, .gitignore
├─ Config/{Base,App,QuickLook,Signing}.xcconfig, Local.xcconfig.example
├─ App/            AppDelegate, DocumentController, MainMenu.xib, Info.plist, entitlements
│  ├─ Document/    MarkdownDocument.swift, DocumentModel.swift
│  ├─ Window/      DocumentWindowController, SplitViewController, OutlineView (SwiftUI), Banner
│  ├─ Web/         PreviewController, SchemeHandlers, NavigationPolicy, ScriptBridge
│  ├─ Export/      HTMLExporter, PDFExporter
│  └─ Settings/
├─ QuickLook/      PreviewViewController.swift, Info.plist, entitlements
├─ CLI/mdv         (kopíruje se do MDView.app/Contents/Resources/bin)
├─ Packages/MarkdownCore/
│  ├─ Sources/CMarkMath/      C extension pro matiku
│  ├─ Sources/MarkdownCore/   Renderer, FrontMatter, Alerts, Slugger, TOC, SourceHighlighter
│  ├─ Sources/FileWatch/      FSEvents watcher, Coalescer, Signature
│  ├─ Sources/WebAssets/Resources/web/  template.html, app.js, app.css, vendor/
│  └─ Tests/                  MarkdownCoreTests, FileWatchTests, Fixtures/{input,github,snapshots}
├─ web-vendor/     package.json, package-lock.json, update.sh
├─ scripts/        agent-sim.sh, gh-golden.sh, install.sh, ql-reset.sh
├─ Samples/        showcase.md, img/
├─ docs/           ARCHITECTURE.md, DECISIONS.md, SECURITY.md, THIRD_PARTY_LICENSES.md
└─ .github/workflows/ci.yml
```

CLI `mdv` odvozuje cestu k aplikaci od sebe (ne `open -a MDView`, které může chytit kopii v DerivedData); `-g` = nekrást fokus terminálu. `make install`: build Release → `/Applications/MDView.app` → symlink `mdv` do `/opt/homebrew/bin` → `lsregister -f` + `qlmanage -r`.

## Fáze

### F0 – příprava a spiky (S1–S3 jdou ještě bez Xcode)
- `git init`, soukromé repo přes `gh repo create --private` (před vytvořením potvrdím), `.gitignore`, `CLAUDE.md`.
- Uživatel: nainstalovat Xcode z App Store, `sudo xcode-select -s /Applications/Xcode.app`, `xcodebuild -runFirstLaunch`, přihlásit Apple ID (Personal Team); `brew install xcodegen`.
- **S1 izolace JS**: jednosouborová appka přes `swiftc -framework WebKit` – inline `<script>`/`onerror` neběží, Mermaid se v isolated world vyrenderuje, KaTeX fonty přes `mdv-asset`, `CSS.highlights` z isolated world funguje, evaluate Mermaidu < 300 ms.
- **S2 matika a věrnost GitHubu**: C extension + Swift Testing, 30 okrajových případů proti `gh api markdown`, sourcepos se neposune.
- **S3 watcher**: prototyp + `agent-sim.sh`, 10min stres test, nikdy se neztratí finální stav.
- **S4 NSDocument**, **S5 QL + podpis + TCC**, **S6 stránkování PDF** (po instalaci Xcode).
- Výstup: `docs/DECISIONS.md`.

### F1 – MVP: spolehlivý reload a bezpečný základ
AppKit + NSDocument, MarkdownCore (GFM, footnotes, sourcepos, tagfilter), WKWebView se schématy a isolated world, block reconciliation, watcher, kotva scrollu, follow tail, dark mode, navigační politika, `mdv`, `make install`.
**Akceptace:** `agent-sim.sh` projde 10× všechny scénáře (atomic save ×500, append 200 B / 20 ms, truncate+write, delete a znovuvytvoření po 5 s, `mv` pryč a zpět, vim backup, `git checkout`) a náhled skončí na finálním obsahu ≤ 300 ms po posledním zápisu; žádný dialog ani bliknutí prázdna, kotva drží ±1 blok. Dokument s `<script>`, `<img onerror>`, `javascript:` a `file:///System/Applications/Calculator.app` nic nespustí. Otevření z Finderu, `mdv`, Open Recent i po relaunchi (včetně scrollu).

### F2 – plné GitHub renderování
Alerts, matika, ```` ```math ````, Mermaid (líně přes IntersectionObserver, při chybě parse ponechat poslední SVG s odznakem, přerender při změně vzhledu), highlight.js, front matter, slugy, task listy (CSS přes `li:has(> input[type=checkbox])`), copy-tex.
**Akceptace:** golden testy proti GitHub API na ≥ 40 fixtures bez neočekávaných rozdílů (vč. `$5 a $10`, `` `$x$` ``, `\$`, matika v tabulce/citaci/seznamu); `Samples/showcase.md` vykreslí vše; změna jednoho odstavce nepřerenderuje žádný diagram.

### F3 – zdrojový panel, TOC, hledání, export
Read-only zdroj se scroll sync oběma směry, TOC sidebar se zvýrazněním aktuální sekce, hledání (CSS Custom Highlight API, počet výsledků, ⌘G/⇧⌘G, volitelně bez diakritiky), zoom, export HTML (snapshot DOM bez skriptů) a PDF (`printOperation` + `runModal`, záloha Print → Save as PDF), nastavení (vzhled, vzdálené obrázky, front matter režim, follow tail).
**Akceptace:** sync bez oscilace s chybou ≤ 1 řádek; klik v TOC skočí na nadpis; hledání přežije reload; exportované HTML vypadá offline v Safari stejně; PDF stránkované a nerozsekává code bloky ani diagramy.

### F4 – Quick Look extension
View-based `QLPreviewingController` s WKWebView, sdílené MarkdownCore + WebAssets, entitlement `com.apple.security.network.client`, read-only temporary exception pro relativní obrázky, bez app groups, Mermaid v QL defaultně vypnutý; UTI `net.daringfireball.markdown` (+ vlastní odvozená UTI pro .mdown/.mkd), role Viewer, `LSHandlerRank` Alternate.
**Akceptace:** mezerník ve Finderu ukáže GitHub styl, dark mode i obrázky; 100 KB soubor < 500 ms; `pluginkit -mAvvv -p com.apple.quicklook.preview` ukáže jedinou registraci z `/Applications`; žádné síťové požadavky. (Případný QLMarkdown vypnout kvůli konfliktům.)

### F5 – nice-to-have
Folder workspace (`mdv .` přes `WorkspaceDocument` pro `public.folder`, strom souborů, volitelně auto-otevření naposledy změněného .md), zvýraznění změněných bloků + „skoč na poslední změnu“, `:emoji:`, `mdv` na neexistující soubor („čekám na vytvoření“), `mdv -` ze stdin.

## CI (GitHub Actions)

`macos-26` (arm64, Xcode 26.6): `brew install xcodegen`, `swift test` v `Packages/MarkdownCore`, `xcodebuild build CODE_SIGNING_ALLOWED=NO`. Soukromé repo počítá macOS minuty 10× (Free plán ≈ 200 macOS minut/měsíc) → path filtry, `concurrency: cancel-in-progress`, spouštění jen na push do `main` a ručně.

## Verifikace

- `make test` → `swift test` (renderer snapshoty, golden testy proti `Tests/Fixtures/github/` generovaným `scripts/gh-golden.sh`, testy watcheru v temp adresáři) + `xcodebuild test` pro app target.
- `scripts/agent-sim.sh <soubor>` při otevřeném okně – všechny scénáře zápisu, sledovat latenci, scroll, absenci dialogů.
- `Samples/showcase.md` (tabulka, task list, footnote, všech 5 alertů, Mermaid, `$$` matika, front matter, dlouhý code block, relativní obrázek, škodlivé odkazy) – vizuální kontrola v light i dark režimu, porovnání s náhledem na GitHubu.
- `make install` → `mdv Samples/showcase.md`, otevření z Finderu, Open Recent, relaunch; Quick Look přes `qlmanage -p Samples/showcase.md` a mezerník ve Finderu.
- Kontrola TCC: po rebuildu a reinstalaci nesmí macOS znovu žádat o přístup k `~/Documents`.

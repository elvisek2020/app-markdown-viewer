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
| D18 | Zdrojový panel ve stejném WKWebView, zvýraznění řádků ve Swiftu (`SourceHighlighter`) | implementováno |
| D19 | Scroll sync: monotónní mapa řádek ↔ y z `data-sourcepos` (bez footnotes), synchronizace jen z aktivního panelu, skok na řádek zdroj „připíchne“ | implementováno |
| D20 | Hledání přes CSS Custom Highlight API, normalizace NFD bez diakritiky s mapou zpět na DOM | implementováno |
| D21 | Export HTML bez JS (styly, fonty KaTeX a lokální obrázky vložené); PDF a tisk přes `printOperation` + `runModal`, světlé téma, `shouldPrintBackgrounds`, nadpis drží s následujícím blokem | implementováno |
| D22 | Ikony alertů jako inline SVG (CSS maska se netiskne), stejné jako na GitHubu | implementováno |
| D23 | Self-test neukládá rámy oken ani rozdělení (Debug build sdílí předvolby s nainstalovanou aplikací) | implementováno |
| D24 | Quick Look: view-based `QLPreviewingController` s WKWebView a sdíleným `PreviewSupport`; sandbox + `network.client` + read-only výjimka `/`; bez sítě (app.js i `WKContentRuleList`), bez Mermaidu | implementováno |
| D25 | Diagnostika Quick Look přes `Logger` do systémového logu, zapínaná souborem v /tmp (kontejner je od macOS 14 zvenku nečitelný) | implementováno |
| D26 | Pracovní složka jako `WorkspaceDocument` (`public.folder`), `FolderIndex` + `FolderWatcher` (rekurzivní FSEvents) ve FileWatch, režim sledování přepíná na naposledy změněný soubor | implementováno |
| D27 | Zvýraznění změn z reconciliation (nové klíče bloků), potlačené po renderu vyvolaném nastavením; ⌘J skok na poslední změnu | implementováno |
| D28 | `mdv` na neexistující soubor čeká v CLI (bez URL schématu, které by mohly volat cizí aplikace) | implementováno |
| D29 | Lupa per dokument v UserDefaults (nejvýš 200 záznamů, neexistující soubory jdou pryč první) | implementováno |
| D30 | Paměť okna vlastní (`WindowFrameMemory`: uložení při zavření, posunu a změně velikosti, obnova u nového okna) místo `windowFrameAutosaveName`, které patří jen jednomu oknu | implementováno |
| D31 | Přepínač vzhledu v nástrojové liště (`NSMenuToolbarItem`) a v menu Zobrazení, sdílí předvolbu s Nastavením | implementováno |
| D32 | Režim úprav (mění D1 a zadání „jen viewer“): nativní `NSTextView` (TextKit 1) vytvořený až při zapnutí, automatické atomické ukládání, konflikt se zápisem agenta řeší banner | implementováno |
| D11 | Build výstupy mimo repo (`~/Library/Caches/MDView`), protože `~/Documents` synchronizuje iCloud a xattr rozbíjejí codesign | přijato |

## Spiky

| Spike | Cíl | Výsledek |
|---|---|---|
| S1 | Izolace JS (isolated world, Mermaid, KaTeX fonty, CSS Highlight API) | Hotovo přes `scripts/selftest.sh` (Debug self-test v reálném WKWebView): inline handler vložený mimo DOMPurify neběží, page world nevidí `mdv`, Mermaid 11 se v isolated worldu vykreslí, KaTeX včetně fontů přes `mdv-asset`, CSS Highlight API dostupné, obrázky přes `mdv-file`. Po změně souboru zůstává tentýž SVG uzel diagramu (reconciliation). |
| S2 | Matika a věrnost GitHubu | Hotovo: C extension + 48 testů rendereru (matika vč. `$5 a $10`, code spanů, `\$`, odsazeného kódu, tabulky, citace a seznamu; alerts, slugy, front matter, sourcepos). Golden testy proti `gh api markdown` zbývají. |
| S3 | Watcher | Hotovo: 13 testů stabilně zelených (5× po sobě). **Zjištění:** FSEvents hlásí změnu obsahu až při zavření souboru, ne při každém `write()`. Streamování do otevřeného souboru proto zachytí kqueue `DispatchSource` na drženém fd. **Zátěž v aplikaci** (`scripts/selftest-sim.sh`, 8 scénářů včetně 500 atomických zápisů): finální obsah 84–186 ms po posledním zápisu, žádné prázdné bliknutí, banner jen u smazání delšího než grace perioda. Zátěžový test našel chybu: po „přesunu pryč a zpět“ watcher zůstal na dočasné cestě; opraveno (návrat na původní cestu + ověření inode u přejmenování), pokryto testem. |
| S4 | `NSDocument` jako viewer | — |
| S5 | Quick Look, podpis, TCC | Hotovo: rozšíření podepsané Apple Development se načte; po registraci je ve výchozím stavu vypnuté, `make install` ho povolí (`pluginkit -e use`); relativní obrázky ve složce Dokumenty vyžadují jednorázový souhlas TCC pro MDView (přisuzuje se aplikaci, ne rozšíření). |
| S6 | Stránkování PDF | — |

## Golden testy (F2)

45 fixtures v `Packages/MarkdownCore/Tests/MarkdownCoreTests/Fixtures/golden`:
- **43 se shoduje s GitHubem přesně.**
- **Dva rozdíly jsou záměrné:**
  - `$$` odstavec: GitHub zpracuje `\,` jako markdown escape a TeX poškodí, MDView ho zachová.
  - Escapované `\$x\$`: GitHub z nich udělá matiku, MDView je respektuje jako escape.
- **Kotvy nadpisů** se shodují ve všech fixtures.
- **Chyba nalezená golden testy:** inline matika `$5 …` přeskočila do code spanu. Opraveno, inline matika nesmí přeskočit backtick.

## F3: zdroj, osnova, hledání, export

Integrační self-test ověřuje:
- hledání, i bez diakritiky
- export HTML: bez skriptů, s vloženými fonty a obrázky a bez interních URL
- export PDF: stránkovaný, s poslední stranou
- skok na nadpis zarovná zdroj na stejný řádek
- synchronizaci zdroj → náhled

Chyby nalezené při F3:
- **CRLF:** Swift bere `\r\n` jako jeden grafém. Dělení podle `"\n"` nerozdělilo řádky a front matter se v CRLF souborech nerozpoznal.
- **Tisk do PDF bez panelu:** callback `runModal` přichází z vlákna na pozadí, takže kontrola MainActor ukončila aplikaci. Oprava: `nonisolated` callback.
- **requestAnimationFrame:** WebKit ho v zakrytých oknech pozastavuje. Synchronizace proto běží přes microtask.
- **Footnotes v mapě synchronizace:** definice ze středu zdroje se vykreslují na konci dokumentu a zablokovaly monotónní mapu.
- **Vzhled:** znovu se nastavoval při každé notifikaci UserDefaults (třeba při uložení rámu okna) a přepisoval dočasný vzhled.
- **Velikost okna:** `NSHostingController` osnovy zmenšil okno bez uloženého rámu na výšku seznamu. Oprava: `sizingOptions = []`.
- **Předvolby:** self-test ukládal rámy oken do předvoleb nainstalované aplikace.

## F4: Quick Look

`scripts/quicklook-check.sh` ověřuje nainstalovanou aplikaci:
- jediná, povolená registrace z /Applications
- vykreslení: KaTeX, kód, alerts s ikonami, relativní obrázek
- JS z dokumentu neběží
- ukázka za ~160 ms a 100KB dokument (1892 bloků, 244 vzorců, 61 obrázků) za ~340 ms
- obrázek z internetu zablokovaný

Poznatky:
- **Registrace:** nově zaregistrované rozšíření třetí strany je vypnuté (`pluginkit -m` ho bez `-D` vůbec neukáže).
- **Kontejner rozšíření:** od macOS 14 je zvenku nečitelný (`Operation not permitted`).
- **`log` v zsh:** je to vestavěný příkaz, systémový log se musí volat jako `/usr/bin/log`.
- **Délka logu:** dlouhé zprávy systémový log ořízne, takže report musí být krátký.
- **TCC:** čtení obrázku vedle souboru ve složce Dokumenty vyvolá žádost TCC (`kTCCServiceSystemPolicyDocumentsFolder`) pro MDView.

## F5: pracovní složka a doplňky

Integrační testy ověřují:
- strom pracovní složky bez `node_modules` a `.git`, výchozí výběr README
- režim sledování: nový soubor agenta → náhled se přepne a vykreslí ho
- zvýraznění změn: po připsání odstavce je zvýrazněný jen on a ⌘J na něj skočí

Poznatky:
- **`/private` v cestách:** `URL.resolvingSymlinksInPath()` i `standardizedFileURL` odstraňují prefix `/private`, FSEvents ho ale hlásí. Index a watcher proto porovnávají s kanonickou cestou kořene (`F_GETPATH`) a pracovní složka sjednocuje cesty přes `resolvingSymlinksInPath()`.
- **Quick Look v CI:** na virtuálním runneru bez GPU trvá náhled 2–3 s. CI ověřuje funkčnost, rychlost se měří lokálně.

## Režim úprav (D32)

Zadání: co nejjednodušší editor, který nezpomalí start aplikace. Do režimu úprav se přepíná tlačítkem v liště (⌥⌘E), ukládá se automaticky a změnu od agenta při neuložených úpravách rozhodne uživatel v banneru.

- **Editor:** `NSTextView` s TextKit 1 (`init(usingTextLayoutManager: false)`), neproporcionální písmo, bez automatických náhrad a kontroly pravopisu. TextKit 1 kvůli přesným pozicím řádků pro synchronizaci posunu (TextKit 2 výšky odhaduje, viz zdrojový panel). Vzniká až při zapnutí režimu, start aplikace se nemění. Bez nových závislostí, bez zvýraznění syntaxe.
- **Rozložení:** editor nahrazuje zdrojový panel. `PreviewContainerView` drží banner a `NSSplitView` editor | náhled. Podíl šířky se pamatuje v předvolbě `editorWidth`.
- **Náhled:** renderuje text editoru (debounce 60 ms). Zvýraznění změn jen u změn souboru, ne u psaní (`DocumentModel.RenderReason`).
- **Ukládání:** sekundu po posledním psaní, při přepnutí do jiné aplikace (agent hned vidí úpravy), ⌘S, vypnutí režimu, přepnutí souboru v pracovní složce a zavření okna. Zápis je atomický (`Data.write(.atomic)`, práva souboru zůstanou) do cíle symlinku. Před zápisem se soubor znovu přečte: když ho agent mezitím změnil a watcher to ještě neohlásil, vznikne konflikt místo přepsání.
- **Stav disk ↔ editor** drží `EditSync` (FileWatch, testy v `EditSyncTests`):
  - Vlastní zápisy se poznají podle obsahu. Watcher je hlásí se zpožděním, proto se pamatují i poslední 4 uložené verze.
  - Změna od agenta bez neuložených úprav se do editoru tiše načte. Mění se jen změněný úsek, kurzor i pozice zůstanou, historie zpět se zahodí.
  - S neuloženými úpravami vznikne konflikt. Automatické ukládání stojí a banner nabídne Načíst verzi z disku, Ponechat moje úpravy, nebo Porovnat (řádkový diff `LineDiff` v okně nad dokumentem).
- **Zavření a ukončení:** `canClose` a `applicationShouldTerminate` uloží rozepsané úpravy. Při konfliktu nebo chybě zápisu se modálně zeptají a dovolí zavření zrušit.
- **Pracovní složka:** režim úprav pokračuje i ve vybraném dalším souboru. Režim sledování v něm nepřepíná, aby editor uživateli nezmizel pod rukama.
- **Synchronizace posunu:** editor řídí náhled přes zlomkový řádek zdroje a stejnou monotónní mapu jako zdrojový panel (`mdv.syncToLine`). Posun náhledu uživatelem posune editor (`previewLine`).
- **Menu:** menu vieweru mělo v Úpravách jen Kopírovat a Vybrat vše. Doplněné jsou Zpět, Znovu, Vyjmout, Vložit, Smazat a v Souboru Uložit, protože NSTextView dostává ⌘Z, ⌘X, ⌘V a ⌘S jen přes položky menu. Zpět vrací po úsecích psaní mezi uloženími (po uložení `breakUndoCoalescing`).

Poznatky:
- **Tisk na vlákně na pozadí:** export PDF volá `visibleRect` u všech předků webview, tedy i u `PreviewContainerView.isFlipped`. Izolovaný getter by Swift 6 za běhu shodil, proto je `nonisolated`.
- **`saveDocument:`:** Swiftí `NSDocument.save(_:)` je v Objective-C `saveDocument:`. Akce náhledu se proto musí jmenovat `saveDocument(_:)`, jinak ji položka Uložit mine.
- **Skupiny Zpět v self-testu:** NSUndoManager zavírá automatickou skupinu až po zpracování události. Self-test žádné události nemá, takže po každém psaní pošle prázdnou `applicationDefined` událost. Ruční `endUndoGrouping` vyhodí výjimku.
- **Ověření:** `scripts/selftest-edit.sh` (v CI) projde psaní, automatické uložení bez reloadu, tiché načtení změny od agenta, oba konflikty, porovnání, ⌘S, položky menu, Zpět a synchronizaci posunu.
  `scripts/selftest-workspace.sh` ověří, že režim úprav pokračuje v dalším souboru a sledování v něm nepřepíná.

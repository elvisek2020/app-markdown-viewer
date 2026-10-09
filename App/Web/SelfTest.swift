#if DEBUG
import AppKit
import WebKit

/// Self-test náhledu bez UI (jen Debug build): po vykreslení dokumentu spustí sondu v reálné
/// konfiguraci WKWebView, zapíše JSON report a ukončí aplikaci.
///
///     open -a MDView.app /tmp/doc.md --args -MDViewSelfTestReport /tmp/report.json
///
/// Fáze 1 změří vykreslení a izolaci JS a označí vyrenderované diagramy; pak připíše na konec
/// souboru odstavec (atomicky, jen kopie v /tmp!) a fáze 2 ověří, že se diagramy znovu nerenderovaly.
/// Pak rozbije první Mermaid diagram a fáze 3 ověří, že zůstala poslední platná verze.
///
/// `-MDViewSelfTestSnapshot cesta.png` uloží po fázi 1 snímek náhledu (obrázky do README),
/// `-MDViewSelfTestAppearance dark` přepne aplikaci do tmavého vzhledu.
enum SelfTest {
    static var reportPath: String? {
        UserDefaults.standard.string(forKey: "MDViewSelfTestReport")
    }

    /// Režim pro `scripts/selftest-sim.sh`: po každé aktualizaci připíše řádek JSON se stavem náhledu.
    static var statusPath: String? {
        UserDefaults.standard.string(forKey: "MDViewSelfTestStatus")
    }

    @MainActor
    static func recordStatus(webView: WKWebView, world: WKContentWorld) {
        guard let statusPath else { return }
        let script = """
        return JSON.stringify({
          t: Date.now(),
          h1: document.querySelector("#mdv-content h1")?.textContent ?? "",
          banner: document.getElementById("mdv-banner").hidden ? "" : document.getElementById("mdv-banner").textContent,
          blocks: document.getElementById("mdv-content").children.length,
          tail: (document.getElementById("mdv-content").lastElementChild?.textContent ?? "").trim().slice(-40),
          scrollTop: Math.round(document.getElementById("mdv-scroll").scrollTop),
        });
        """
        Task {
            guard let line = try? await webView.callAsyncJavaScript(script, arguments: [:], in: nil, contentWorld: world) as? String else { return }
            appendLine(line, to: statusPath)
        }
    }

    private static func appendLine(_ line: String, to path: String) {
        guard let data = (line + "\n").data(using: .utf8) else { return }
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }

    static var snapshotPath: String? {
        UserDefaults.standard.string(forKey: "MDViewSelfTestSnapshot")
    }

    /// Volá se při startu aplikace.
    @MainActor
    static func configureApplication() {
        if UserDefaults.standard.string(forKey: "MDViewSelfTestAppearance") == "dark" {
            NSApp.appearance = NSAppearance(named: .darkAqua)
        } else if reportPath != nil {
            NSApp.appearance = NSAppearance(named: .aqua)
        }
    }

    @MainActor private static var phase = 0
    @MainActor static var report: [String: Any] = [:]
    @MainActor private static let started = Date()

    @MainActor
    static func didUpdate(webView: WKWebView, fileURL: URL, world: WKContentWorld) {
        guard let reportPath, phase < 3 else { return }
        phase += 1
        let currentPhase = phase
        Task {
            let result = await probe(webView: webView, world: world, phase: currentPhase)
            report["phase\(currentPhase)"] = result
            report["phase\(currentPhase)ElapsedMs"] = Int(Date().timeIntervalSince(started) * 1000)
            if currentPhase == 1 {
                report["pageWorldSeesMdv"] = await pageWorldSeesMdv(webView: webView)
                if let snapshotPath { await saveSnapshot(of: webView, to: snapshotPath) }
                modify(fileURL) { $0 + "\n\nPřidaný odstavec self-testu.\n" }
            } else if currentPhase == 2 {
                // Rozepsaný diagram (agent ho právě píše): poslední platná verze musí zůstat.
                let broken = modify(fileURL) { $0.replacingOccurrences(of: "```mermaid\n", with: "```mermaid\nflowchart LR\n    Rozepsaný -->\n") }
                if !broken {
                    write(report, to: reportPath)
                    NSApp.terminate(nil)
                }
            } else {
                write(report, to: reportPath)
                NSApp.terminate(nil)
            }
        }
        // Pojistka, kdyby fáze 2 nepřišla (watcher nezachytil změnu).
        if currentPhase == 1 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
                MainActor.assumeIsolated {
                    guard phase < 3 else { return }
                    report["phase\(phase + 1)"] = "timeout – změna souboru se do náhledu nedostala"
                    write(report, to: reportPath)
                    NSApp.terminate(nil)
                }
            }
        }
    }

    @MainActor
    private static func probe(webView: WKWebView, world: WKContentWorld, phase: Int) async -> Any {
        let script = """
        await mdv.flushDiagrams();
        const content = document.getElementById("mdv-content");
        // Inline handler vložený přímo do DOM (mimo DOMPurify) nesmí běžet – content JS je vypnutý.
        const trap = document.createElement("img");
        trap.setAttribute("onerror", "document.body.dataset.pwned = '1'");
        trap.src = "mdv-asset://app/neexistuje.png";
        content.append(trap);
        await new Promise((resolve) => setTimeout(resolve, 500));
        trap.remove();
        await document.fonts.ready;
        const svgs = [...content.querySelectorAll(".mdv-mermaid svg")];
        const result = {
          blocks: content.children.length,
          katex: content.querySelectorAll(".katex").length,
          katexErrors: content.querySelectorAll(".katex-error").length,
          mermaidSvg: svgs.length,
          mermaidReused: svgs.filter((svg) => svg.__mdvSelfTest === 1).length,
          mermaidErrors: [...content.querySelectorAll(".mdv-mermaid-error")].map((e) => e.dataset.error),
          mermaidStale: content.querySelectorAll(".mdv-mermaid-stale svg").length,
          mermaidBadge: content.querySelector(".mdv-mermaid-badge")?.textContent ?? null,
          copyTex: !!content.querySelector(".katex") && typeof window.katex === "object",
          hljs: content.querySelectorAll("code.hljs").length,
          alerts: content.querySelectorAll(".markdown-alert").length,
          alertIconMask: (() => {
            const icon = content.querySelector(".mdv-octicon");
            return icon ? getComputedStyle(icon).maskImage : null;
          })(),
          footnotes: !!content.querySelector("section.footnotes"),
          taskItems: content.querySelectorAll(".task-list-item").length,
          frontMatter: !!content.querySelector(".mdv-frontmatter"),
          headingAnchors: [...content.querySelectorAll("a.anchor")].map((a) => a.id).slice(0, 4),
          images: [...content.querySelectorAll("img")].map((img) => ({ src: img.getAttribute("src"), loaded: img.complete && img.naturalWidth > 0 })),
          katexFontReady: document.fonts.check("16px KaTeX_Main"),
          stylesheets: [...document.styleSheets].map((sheet) => { try { return sheet.cssRules.length; } catch (e) { return -1; } }),
          pwnedByInlineHandler: document.body.dataset.pwned === "1",
          scripts: content.querySelectorAll("script").length,
          iframes: content.querySelectorAll("iframe").length,
          forms: content.querySelectorAll("form, button").length,
          cssHighlightApi: typeof CSS !== "undefined" && "highlights" in CSS,
          lastParagraph: content.lastElementChild?.textContent?.slice(0, 80) ?? null,
          libraries: { mermaid: typeof mermaid, katex: typeof katex, hljs: typeof hljs, purify: typeof DOMPurify },
          mermaidCodeBlocks: content.querySelectorAll("pre > code.language-mermaid").length,
        };
        svgs.forEach((svg) => { svg.__mdvSelfTest = 1; });
        return JSON.stringify(result);
        """
        do {
            let value = try await webView.callAsyncJavaScript(script, arguments: [:], in: nil, contentWorld: world)
            guard let json = value as? String, let data = json.data(using: .utf8) else { return "neplatný výsledek" }
            return (try? JSONSerialization.jsonObject(with: data)) ?? json
        } catch {
            return "chyba: \(error)"
        }
    }

    /// Stránka (page world) nesmí vidět globály aplikace – ověřuje izolaci worldů.
    @MainActor
    private static func pageWorldSeesMdv(webView: WKWebView) async -> String {
        await withCheckedContinuation { continuation in
            webView.evaluateJavaScript("typeof mdv", in: nil, in: .page) { result in
                switch result {
                case .success(let value): continuation.resume(returning: "\(value)")
                case .failure(let error): continuation.resume(returning: "chyba: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Upraví kopii dokumentu (jen v /tmp). Vrací, zda se obsah změnil.
    @discardableResult
    private static func modify(_ fileURL: URL, _ transform: (String) -> String) -> Bool {
        guard fileURL.path.hasPrefix("/tmp/") || fileURL.path.hasPrefix("/private/tmp/"),
              let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return false }
        let modified = transform(text)
        guard modified != text else { return false }
        try? modified.write(to: fileURL, atomically: true, encoding: .utf8)
        return true
    }

    @MainActor
    private static func saveSnapshot(of webView: WKWebView, to path: String) async {
        // Snímek ve 2× (Retina) – šířka v bodech dvojnásobná, obrázek se pak vykreslí do bitmapy 1:1.
        let configuration = WKSnapshotConfiguration()
        configuration.snapshotWidth = NSNumber(value: Double(webView.bounds.width * 2))
        // Oříznout prázdné místo pod obsahem (výška podle konce posledního bloku + okraj).
        let bottom = try? await webView.callAsyncJavaScript(
            "return document.getElementById('mdv-content').lastElementChild?.getBoundingClientRect().bottom ?? 0",
            arguments: [:], in: nil, contentWorld: PreviewController.world
        ) as? Double
        if let bottom, bottom > 0 {
            let height = min(webView.bounds.height, CGFloat(bottom) + 48)
            configuration.rect = CGRect(x: 0, y: 0, width: webView.bounds.width, height: height)
        }
        guard let image = try? await webView.takeSnapshot(configuration: configuration),
              let png = pngData(image) else {
            report["snapshot"] = "selhal"
            return
        }
        try? png.write(to: URL(fileURLWithPath: path))
        report["snapshot"] = path
    }

    private static func pngData(_ image: NSImage) -> Data? {
        let width = Int(image.size.width)
        let height = Int(image.size.height)
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .png, properties: [:])
    }

    private static func write(_ report: [String: Any], to path: String) {
        guard let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: URL(fileURLWithPath: path))
    }
}
#endif

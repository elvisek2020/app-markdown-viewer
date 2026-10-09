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

    @MainActor private static var phase = 0
    @MainActor static var report: [String: Any] = [:]
    @MainActor private static let started = Date()

    @MainActor
    static func didUpdate(webView: WKWebView, fileURL: URL, world: WKContentWorld) {
        guard let reportPath, phase < 2 else { return }
        phase += 1
        let currentPhase = phase
        Task {
            let result = await probe(webView: webView, world: world, phase: currentPhase)
            report["phase\(currentPhase)"] = result
            report["phase\(currentPhase)ElapsedMs"] = Int(Date().timeIntervalSince(started) * 1000)
            if currentPhase == 1 {
                report["pageWorldSeesMdv"] = await pageWorldSeesMdv(webView: webView)
                appendParagraph(to: fileURL)
            } else {
                write(report, to: reportPath)
                NSApp.terminate(nil)
            }
        }
        // Pojistka, kdyby fáze 2 nepřišla (watcher nezachytil změnu).
        if currentPhase == 1 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                MainActor.assumeIsolated {
                    guard phase == 1 else { return }
                    report["phase2"] = "timeout – změna souboru se do náhledu nedostala"
                    write(report, to: reportPath)
                    NSApp.terminate(nil)
                }
            }
        }
    }

    @MainActor
    private static func probe(webView: WKWebView, world: WKContentWorld, phase: Int) async -> Any {
        let script = """
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

    private static func appendParagraph(to fileURL: URL) {
        guard fileURL.path.hasPrefix("/tmp/") || fileURL.path.hasPrefix("/private/tmp/"),
              var text = try? String(contentsOf: fileURL, encoding: .utf8) else { return }
        text += "\n\nPřidaný odstavec self-testu.\n"
        try? text.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private static func write(_ report: [String: Any], to path: String) {
        guard let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: URL(fileURLWithPath: path))
    }
}
#endif

import Foundation

/// Co udělat s odkazem z dokumentu. Allowlist – nic se nespouští, soubory se jen ukazují ve Finderu.
public enum LinkAction: Equatable, Sendable {
    /// Markdown soubor otevřít v MDView.
    case openMarkdown(URL)
    /// http(s) a mailto do výchozí aplikace.
    case openExternal(URL)
    /// Jiný lokální soubor nebo složka – jen ukázat ve Finderu, nikdy neotevírat.
    case revealInFinder(URL)
    /// Neznámé schéma (`vscode://` …) – otevřít jen po potvrzení s celou URL.
    case confirmExternal(URL)
    /// Nic (javascript:, data:, interní schémata, neexistující soubory).
    case ignore
}

public enum LinkPolicy {
    public static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd", "mkdn", "mdwn", "mdtxt", "mdtext"]
    private static let externalSchemes: Set<String> = ["http", "https", "mailto"]
    private static let blockedSchemes: Set<String> = ["javascript", "vbscript", "data", "blob", "about", "mdv-asset"]

    /// Schéma, přes které náhled načítá lokální soubory (`mdv-file:///abs/cesta`).
    public static let fileScheme = "mdv-file"

    public static func action(for url: URL, fileManager: FileManager = .default) -> LinkAction {
        guard let scheme = url.scheme?.lowercased() else { return .ignore }
        if externalSchemes.contains(scheme) { return .openExternal(url) }
        if blockedSchemes.contains(scheme) { return .ignore }
        if scheme == "file" || scheme == fileScheme {
            return localAction(path: url.path, fileManager: fileManager)
        }
        return .confirmExternal(url)
    }

    /// `file:` URL → `mdv-file:` URL pro načtení v náhledu.
    public static func previewURL(forFile fileURL: URL) -> URL {
        var components = URLComponents(url: fileURL.standardizedFileURL, resolvingAgainstBaseURL: false)!
        components.scheme = fileScheme
        components.host = ""
        return components.url!
    }

    private static func localAction(path: String, fileManager: FileManager) -> LinkAction {
        guard !path.isEmpty else { return .ignore }
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let resolved = url.resolvingSymlinksInPath()
        guard let values = try? resolved.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey]) else {
            return .ignore
        }
        if values.isRegularFile == true, markdownExtensions.contains(resolved.pathExtension.lowercased()) {
            return .openMarkdown(url)
        }
        if values.isRegularFile == true || values.isDirectory == true {
            return .revealInFinder(url)
        }
        return .ignore
    }
}

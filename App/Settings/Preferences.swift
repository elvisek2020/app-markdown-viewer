import AppKit
import MarkdownCore

/// Uživatelské předvolby (UserDefaults). Okna reagují na `UserDefaults.didChangeNotification`.
enum Preferences {
    enum Key {
        static let appearance = "appearance"
        static let frontMatter = "frontMatterMode"
        static let math = "renderMath"
        static let emoji = "renderEmoji"
        static let remoteImages = "remoteImages"
        static let followTail = "followTail"
        static let pageZoom = "pageZoom"
        static let ignoreDiacritics = "findIgnoreDiacritics"
        static let showSource = "showSourceByDefault"
        static let sourceWidth = "sourceWidth"
        static let editorWidth = "editorWidth"
        static let highlightChanges = "highlightChanges"
        static let zoomByFile = "pageZoomByFile"
    }

    enum Appearance: String, CaseIterable {
        case system, light, dark
    }

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Key.appearance: Appearance.system.rawValue,
            Key.frontMatter: RenderOptions.FrontMatterMode.table.rawValue,
            Key.math: true,
            Key.emoji: true,
            Key.remoteImages: true,
            Key.followTail: true,
            Key.pageZoom: 1.0,
            Key.ignoreDiacritics: true,
            Key.showSource: false,
            Key.sourceWidth: 0.45,
            Key.editorWidth: 0.5,
            Key.highlightChanges: true,
        ])
    }

    private static var defaults: UserDefaults { .standard }

    /// Volby rendereru podle nastavení (zdroj se přidává podle panelu v okně).
    static func renderOptions(includeSource: Bool) -> RenderOptions {
        RenderOptions(
            frontMatter: RenderOptions.FrontMatterMode(rawValue: defaults.string(forKey: Key.frontMatter) ?? "") ?? .table,
            math: defaults.bool(forKey: Key.math),
            emoji: defaults.bool(forKey: Key.emoji),
            includeSource: includeSource
        )
    }

    static var remoteImages: Bool { defaults.bool(forKey: Key.remoteImages) }
    static var followTail: Bool { defaults.bool(forKey: Key.followTail) }
    static var ignoreDiacritics: Bool { defaults.bool(forKey: Key.ignoreDiacritics) }
    static var showSourceByDefault: Bool { defaults.bool(forKey: Key.showSource) }
    static var sourceWidth: Double { defaults.double(forKey: Key.sourceWidth) }
    static var editorWidth: Double { defaults.double(forKey: Key.editorWidth) }
    static var highlightChanges: Bool { defaults.bool(forKey: Key.highlightChanges) }

    /// Lupa je per dokument (podle cesty); dokument bez záznamu má 100 %.
    static func zoom(for url: URL) -> Double {
        (defaults.dictionary(forKey: Key.zoomByFile) as? [String: Double])?[url.path] ?? 1
    }

    static func setZoom(_ zoom: Double, for url: URL) {
        var zooms = (defaults.dictionary(forKey: Key.zoomByFile) as? [String: Double]) ?? [:]
        zooms[url.path] = zoom == 1 ? nil : zoom
        // Nenechat seznam růst donekonečna (soubory, které už neexistují, jdou pryč první).
        if zooms.count > 200 {
            for path in zooms.keys where !FileManager.default.fileExists(atPath: path) { zooms[path] = nil }
            while zooms.count > 200, let any = zooms.keys.first { zooms[any] = nil }
        }
        defaults.set(zooms, forKey: Key.zoomByFile)
    }

    static var appearance: Appearance {
        Appearance(rawValue: defaults.string(forKey: Key.appearance) ?? "") ?? .system
    }

    static func applyAppearance() {
        switch appearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

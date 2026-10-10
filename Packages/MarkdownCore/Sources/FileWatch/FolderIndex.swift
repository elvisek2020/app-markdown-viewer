import Foundation

/// Uzel stromu Markdown souborů ve složce.
public struct FolderNode: Sendable, Hashable, Identifiable {
    public let url: URL
    public let name: String
    public let isDirectory: Bool
    public let modified: Date
    /// Podsložky a soubory (jen u složek; složky bez Markdownu se vynechávají).
    public let children: [FolderNode]?

    public var id: String { url.path }
}

/// Rekurzivní index Markdown souborů ve složce – pro postranní panel pracovní složky.
public enum FolderIndex {
    /// Složky, které se nikdy neprocházejí (závislosti, buildy, VCS).
    public static let ignoredDirectories: Set<String> = [
        ".git", ".hg", ".svn", "node_modules", ".build", "build", "DerivedData", "Pods", "Carthage",
        ".venv", "venv", "__pycache__", "dist", "target", ".next", ".nuxt", ".cache", ".idea", ".vscode",
    ]

    public struct Limits: Sendable {
        public var maximumFiles = 5000
        public var maximumDepth = 12
        public init() {}
    }

    /// Strom seřazený jako ve Finderu (složky první, pak abecedně bez ohledu na velikost písmen).
    public static func scan(_ root: URL, extensions: Set<String>, limits: Limits = Limits()) -> [FolderNode] {
        var remaining = limits.maximumFiles
        return scanDirectory(root.standardizedFileURL, extensions: extensions, depth: 0, limits: limits, remaining: &remaining)
    }

    /// Všechny soubory ve stromu (pro výběr naposledy změněného).
    public static func files(in nodes: [FolderNode]) -> [FolderNode] {
        nodes.flatMap { node in node.isDirectory ? files(in: node.children ?? []) : [node] }
    }

    /// Má se změna na této cestě promítnout do indexu? (Markdown mimo ignorované a skryté složky.)
    /// `root` se nestandardizuje: `standardizedFileURL` odstraňuje `/private`, FSEvents ho ale hlásí.
    public static func isRelevant(_ path: String, root: URL, extensions: Set<String>) -> Bool {
        let rootPath = root.path
        guard path.hasPrefix(rootPath + "/") else { return false }
        let relative = path.dropFirst(rootPath.count + 1).split(separator: "/")
        guard let last = relative.last else { return false }
        for component in relative.dropLast() where component.hasPrefix(".") || ignoredDirectories.contains(String(component)) {
            return false
        }
        return extensions.contains((String(last) as NSString).pathExtension.lowercased())
    }

    private static func scanDirectory(
        _ directory: URL,
        extensions: Set<String>,
        depth: Int,
        limits: Limits,
        remaining: inout Int
    ) -> [FolderNode] {
        guard depth <= limits.maximumDepth, remaining > 0 else { return [] }
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey]
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
        ) else { return [] }

        var folders: [FolderNode] = []
        var files: [FolderNode] = []
        for entry in entries.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
            guard remaining > 0, let values = try? entry.resourceValues(forKeys: Set(keys)) else { continue }
            // Symlinky na složky se neprocházejí (cykly); symlinky na soubory ano.
            if values.isDirectory == true, values.isSymbolicLink != true {
                guard !ignoredDirectories.contains(entry.lastPathComponent) else { continue }
                let children = scanDirectory(entry, extensions: extensions, depth: depth + 1, limits: limits, remaining: &remaining)
                if !children.isEmpty {
                    folders.append(FolderNode(
                        url: entry, name: entry.lastPathComponent, isDirectory: true,
                        modified: children.map(\.modified).max() ?? .distantPast, children: children
                    ))
                }
            } else if extensions.contains(entry.pathExtension.lowercased()) {
                remaining -= 1
                files.append(FolderNode(
                    url: entry, name: entry.lastPathComponent, isDirectory: false,
                    modified: values.contentModificationDate ?? .distantPast, children: nil
                ))
            }
        }
        return folders + files
    }
}

import Foundation

/// Verze aplikace RRRRMMDD.HHMM (čas buildu); porovnává se po číselných složkách.
public struct ReleaseVersion: Comparable, Sendable, CustomStringConvertible {
    public let components: [Int]
    public let description: String

    /// Přijme `20261010.1922` i tag `v20261010.1922`; jiný tvar vrátí `nil`.
    public init?(_ text: String) {
        let trimmed = text.hasPrefix("v") ? String(text.dropFirst()) : text
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return nil }
        components = parts.compactMap { $0 }
        description = trimmed
    }

    public static func < (lhs: ReleaseVersion, rhs: ReleaseVersion) -> Bool {
        for index in 0..<max(lhs.components.count, rhs.components.count) {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    public static func == (lhs: ReleaseVersion, rhs: ReleaseVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}

/// Poslední vydání z GitHub API (`/repos/{repo}/releases/latest`).
public struct Release: Sendable {
    public let version: ReleaseVersion
    public let pageURL: URL
    /// Asset `MDView.zip` – stejný balíček, jaký instaluje install.sh.
    public let zipURL: URL

    public enum ParseError: Error, Equatable {
        case invalidJSON, invalidVersion(String), missingAsset
    }

    public static let assetName = "MDView.zip"

    public static func parse(_ data: Data) throws -> Release {
        struct Payload: Decodable {
            struct Asset: Decodable {
                let name: String
                let browser_download_url: URL
            }
            let tag_name: String
            let html_url: URL
            let assets: [Asset]
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else { throw ParseError.invalidJSON }
        guard let version = ReleaseVersion(payload.tag_name) else { throw ParseError.invalidVersion(payload.tag_name) }
        guard let zip = payload.assets.first(where: { $0.name == assetName }) else { throw ParseError.missingAsset }
        return Release(version: version, pageURL: payload.html_url, zipURL: zip.browser_download_url)
    }
}

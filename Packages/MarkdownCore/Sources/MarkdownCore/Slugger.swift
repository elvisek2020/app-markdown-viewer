/// Kotvy nadpisů stejně jako GitHub (port knihovny github-slugger):
/// malá písmena, odstranit interpunkci a symboly, mezery nahradit `-`,
/// opakované slugy číslovat `-1`, `-2`, …
public struct Slugger: Sendable {
    private var occurrences: [String: Int] = [:]

    public init() {}

    public mutating func slug(for text: String) -> String {
        let original = Self.baseSlug(text)
        var slug = original
        while occurrences[slug] != nil {
            let count = (occurrences[original] ?? 0) + 1
            occurrences[original] = count
            slug = "\(original)-\(count)"
        }
        occurrences[slug] = 0
        return slug
    }

    static func baseSlug(_ text: String) -> String {
        var result = String.UnicodeScalarView()
        for scalar in text.lowercased().unicodeScalars {
            if scalar == " " {
                result.append("-")
            } else if scalar == "-" || scalar == "_" || isKept(scalar) {
                result.append(scalar)
            }
        }
        return String(result)
    }

    /// Písmena, kombinující znaky a číslice zůstávají, vše ostatní (interpunkce,
    /// symboly včetně emoji, řídicí znaky, jiné mezery) se zahodí.
    private static func isKept(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
             .nonspacingMark, .spacingMark, .enclosingMark,
             .decimalNumber, .letterNumber, .otherNumber:
            return true
        default:
            return false
        }
    }
}

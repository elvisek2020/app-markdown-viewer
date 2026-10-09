import Foundation

/// Emoji zkratky jako na GitHubu (`:rocket:` → 🚀). Data z gemoji (web-vendor/update.sh).
enum EmojiShortcodes {
    static let table: [String: String] = {
        guard let url = Bundle.module.url(forResource: "emoji", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let map = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return map
    }()

    /// Text s nahrazenými zkratkami, nebo `nil`, když se nic nezměnilo.
    ///
    /// Pravidlo podle GitHubu (ověřeno přes API): převádí se jen „slovo“ oddělené mezerami,
    /// které celé tvoří jedna či více zkratek – `:tada:` i `:tada::tada:` ano,
    /// `:tada:.`, `(:tada:)` ani `x:rocket:y` ne.
    static func replacing(in text: String) -> String? {
        guard text.contains(":") else { return nil }
        var result = ""
        var changed = false
        var word = ""
        func flush() {
            if let emoji = emojiSequence(word) {
                result += emoji
                changed = true
            } else {
                result += word
            }
            word = ""
        }
        for character in text {
            if character.isWhitespace {
                flush()
                result.append(character)
            } else {
                word.append(character)
            }
        }
        flush()
        return changed ? result : nil
    }

    /// `:a::b:` → emoji, pokud slovo celé tvoří známé zkratky.
    private static func emojiSequence(_ word: String) -> String? {
        guard word.count >= 3, word.first == ":", word.last == ":" else { return nil }
        let inner = word.dropFirst().dropLast()
        let names = inner.components(separatedBy: "::")
        var emoji = ""
        for name in names {
            guard !name.isEmpty, name.allSatisfy(isNameCharacter), let character = table[name] else { return nil }
            emoji += character
        }
        return emoji
    }

    private static func isNameCharacter(_ character: Character) -> Bool {
        character.isASCII && (character.isLetter || character.isNumber || character == "_" || character == "+" || character == "-")
    }
}

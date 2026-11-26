import Foundation

public enum Lang: String, CaseIterable {
    case en, uk, ru

    /// The language a run starts with (core.sh): MACUP_LANG, else `language` in the config, else the system's.
    /// Anything that is not en, uk or ru there is English ("ua" only works for --lang and macup lang).
    public static func initial(env: Env, config: Config, shell: Shell) -> Lang {
        var code = env.langHook ?? config.value("language", "")
        if code.isEmpty { code = system(shell: shell) }
        return Lang(rawValue: code) ?? .en
    }

    /// `--lang`: en, uk, ru, and ua for uk.
    public static func option(_ value: String) -> Lang? {
        value == "ua" ? .uk : Lang(rawValue: value)
    }

    /// The first preferred language of macOS (`defaults read -g AppleLanguages`, its second line).
    static func system(shell: Shell) -> String {
        let lines = Bash.lines(shell.capture(["defaults", "read", "-g", "AppleLanguages"]).output)
        let preferred = lines.count > 1 ? lines[1].filter { $0 != " " && $0 != "\"" && $0 != "," } : ""
        if preferred.hasPrefix("uk") { return "uk" }
        if preferred.hasPrefix("ru") { return "ru" }
        return "en"
    }

    /// `lang_name`.
    public var name: String {
        switch self { case .uk: "Українська"; case .ru: "Русский"; case .en: "English" }
    }
}

/// Messages: core.sh's `_` and `_f`. The English text is the key; a message without a translation stays English.
public struct I18n {
    public let lang: Lang
    private let table: [String: String]

    /// `translations`: src/i18n/translations.json, {"English": {"uk": …, "ru": …}}.
    public init(lang: Lang, translations: [String: [String: String]]) {
        self.lang = lang
        var entries: [String: String] = [:]
        if lang != .en {
            for (en, tr) in translations { if let translated = tr[lang.rawValue], !translated.isEmpty { entries[en] = translated } }
        }
        table = entries
    }

    public init(lang: Lang, translationsJSON: String) {
        let parsed = (try? JSONSerialization.jsonObject(with: Data(translationsJSON.utf8))) as? [String: [String: String]]
        self.init(lang: lang, translations: parsed ?? [:])
    }

    /// `_`. The lookup reads the key as `awk -v k=…` does, escapes and all.
    public func translate(_ en: String) -> String { table.isEmpty ? en : table[Awk.unescape(en)] ?? en }

    /// `_f`: the translated format, then printf.
    public func format(_ en: String, _ args: CustomStringConvertible...) -> String {
        Printf.format(translate(en), args.map { $0.description })
    }

    public func format(_ en: String, args: [String]) -> String {
        Printf.format(translate(en), args)
    }
}

/// The builtin `printf` of bash for what macup's messages use: %s, %d, %%, and backslash escapes in the format
/// (build.sh lets translations have no other conversion; another one is printed as it is written).
/// Like bash, the format is used again while arguments are left, and a missing argument is "" (or 0 for %d).
public enum Printf {
    public static func format(_ fmt: String, _ args: [String]) -> String {
        if fmt.hasPrefix("-") { return "" }   // printf takes it for an option and prints nothing
        let scalars = Array(fmt.unicodeScalars)
        var out = String.UnicodeScalarView()
        var next = 0
        repeat {
            let before = next
            var index = 0
            while index < scalars.count {
                let scalar = scalars[index]
                if scalar == "\\", index + 1 < scalars.count {
                    index += 1
                    index = escape(scalars, index, into: &out)
                    continue
                }
                if scalar == "%", index + 1 == scalars.count { break }   // a lone % at the end prints nothing
                if scalar == "%" {
                    let conversion = scalars[index + 1]
                    index += 2
                    switch conversion {
                    case "%": out.append("%")
                    case "s":
                        if next < args.count { out.append(contentsOf: args[next].unicodeScalars) }
                        next += 1
                    case "d", "i":
                        let argument = next < args.count ? args[next] : ""
                        out.append(contentsOf: String(integer(argument)).unicodeScalars)
                        next += 1
                    default:
                        out.append("%"); out.append(conversion)
                    }
                    continue
                }
                out.append(scalar)
                index += 1
            }
            if next == before { break }
        } while next < args.count
        return String(out)
    }

    /// One backslash escape of a format, `index` past the backslash; returns the index after it.
    private static func escape(_ scalars: [Unicode.Scalar], _ index: Int, into out: inout String.UnicodeScalarView) -> Int {
        let simple: [Unicode.Scalar: Unicode.Scalar] = ["a": "\u{07}", "b": "\u{08}", "e": "\u{1B}", "E": "\u{1B}", "f": "\u{0C}",
                                                        "n": "\n", "r": "\r", "t": "\t", "v": "\u{0B}", "\\": "\\", "\"": "\"", "'": "'", "?": "?"]
        let scalar = scalars[index]
        if let escaped = simple[scalar] { out.append(escaped); return index + 1 }
        if ("0"..."7").contains(scalar) {
            var value: UInt32 = 0, position = index
            while position < scalars.count, position < index + 3, ("0"..."7").contains(scalars[position]) { value = value * 8 + (scalars[position].value - 48); position += 1 }
            if let escaped = Unicode.Scalar(value & 0xFF) { out.append(escaped) }
            return position
        }
        if scalar == "x", index + 1 < scalars.count, scalars[index + 1].properties.isASCIIHexDigit {
            var value: UInt32 = 0, position = index + 1
            while position < scalars.count, position < index + 3, scalars[position].properties.isASCIIHexDigit { value = value * 16 + UInt32(Int(String(scalars[position]), radix: 16)!); position += 1 }
            if let escaped = Unicode.Scalar(value) { out.append(escaped) }
            return position
        }
        out.append("\\"); out.append(scalar)
        return index + 1
    }

    /// An argument of %d as bash reads it: leading blanks, a sign, then decimal, 0x hex or 0 octal, and nothing after;
    /// anything else is 0 (bash also says "invalid number" on stderr).
    static func integer(_ text: String) -> Int64 {
        let trimmed = String(text.drop(while: { $0 == " " || $0 == "\t" || $0 == "\n" }))
        if let quote = trimmed.first, quote == "'" || quote == "\"" { return Int64(trimmed.dropFirst().unicodeScalars.first?.value ?? 0) }
        return trimmed.withCString { pointer -> Int64 in
            var end: UnsafeMutablePointer<CChar>?
            let value = strtoll(pointer, &end, 0)
            guard let stop = end, stop != UnsafeMutablePointer(mutating: pointer), stop.pointee == 0 else { return 0 }
            return value
        }
    }
}

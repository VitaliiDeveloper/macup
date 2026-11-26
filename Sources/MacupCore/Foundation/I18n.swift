import Foundation

public enum Lang: String, CaseIterable {
    case en, uk, ru

    /// The language a run starts with (core.sh): MACUP_LANG, else `language` in the config, else the system's.
    /// Anything that is not en, uk or ru there is English ("ua" only works for --lang and macup lang).
    public static func initial(env: Env, config: Config, shell: Shell) -> Lang {
        var l = env.langHook ?? config.value("language", "")
        if l.isEmpty { l = system(shell: shell) }
        return Lang(rawValue: l) ?? .en
    }

    /// `--lang`: en, uk, ru, and ua for uk.
    public static func option(_ s: String) -> Lang? {
        s == "ua" ? .uk : Lang(rawValue: s)
    }

    /// The first preferred language of macOS (`defaults read -g AppleLanguages`, its second line).
    static func system(shell: Shell) -> String {
        let lines = Bash.lines(shell.capture(["defaults", "read", "-g", "AppleLanguages"]).output)
        let l = lines.count > 1 ? lines[1].filter { $0 != " " && $0 != "\"" && $0 != "," } : ""
        if l.hasPrefix("uk") { return "uk" }
        if l.hasPrefix("ru") { return "ru" }
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
        var t: [String: String] = [:]
        if lang != .en {
            for (en, tr) in translations { if let v = tr[lang.rawValue], !v.isEmpty { t[en] = v } }
        }
        table = t
    }

    public init(lang: Lang, translationsJSON: String) {
        let d = (try? JSONSerialization.jsonObject(with: Data(translationsJSON.utf8))) as? [String: [String: String]]
        self.init(lang: lang, translations: d ?? [:])
    }

    /// `_`. The lookup reads the key as `awk -v k=…` does, escapes and all.
    public func t(_ en: String) -> String { table.isEmpty ? en : table[Awk.unescape(en)] ?? en }

    /// `_f`: the translated format, then printf.
    public func f(_ en: String, _ args: CustomStringConvertible...) -> String {
        Printf.format(t(en), args.map { $0.description })
    }

    public func f(_ en: String, args: [String]) -> String {
        Printf.format(t(en), args)
    }
}

/// The builtin `printf` of bash for what macup's messages use: %s, %d, %%, and backslash escapes in the format
/// (build.sh lets translations have no other conversion; another one is printed as it is written).
/// Like bash, the format is used again while arguments are left, and a missing argument is "" (or 0 for %d).
public enum Printf {
    public static func format(_ fmt: String, _ args: [String]) -> String {
        let f = Array(fmt.unicodeScalars)
        var out = String.UnicodeScalarView()
        var next = 0
        repeat {
            let before = next
            var i = 0
            while i < f.count {
                let c = f[i]
                if c == "\\", i + 1 < f.count {
                    i += 1
                    i = escape(f, i, into: &out)
                    continue
                }
                if c == "%", i + 1 == f.count { break }   // a lone % at the end prints nothing
                if c == "%" {
                    let d = f[i + 1]
                    i += 2
                    switch d {
                    case "%": out.append("%")
                    case "s":
                        if next < args.count { out.append(contentsOf: args[next].unicodeScalars) }
                        next += 1
                    case "d", "i":
                        let a = next < args.count ? args[next] : ""
                        out.append(contentsOf: String(integer(a)).unicodeScalars)
                        next += 1
                    default:
                        out.append("%"); out.append(d)
                    }
                    continue
                }
                out.append(c)
                i += 1
            }
            if next == before { break }
        } while next < args.count
        return String(out)
    }

    /// One backslash escape of a format, `i` past the backslash; returns the index after it.
    private static func escape(_ f: [Unicode.Scalar], _ i: Int, into out: inout String.UnicodeScalarView) -> Int {
        let simple: [Unicode.Scalar: Unicode.Scalar] = ["a": "\u{07}", "b": "\u{08}", "e": "\u{1B}", "E": "\u{1B}", "f": "\u{0C}",
                                                        "n": "\n", "r": "\r", "t": "\t", "v": "\u{0B}", "\\": "\\", "\"": "\"", "'": "'", "?": "?"]
        let c = f[i]
        if let s = simple[c] { out.append(s); return i + 1 }
        if ("0"..."7").contains(c) {
            var v: UInt32 = 0, j = i
            while j < f.count, j < i + 3, ("0"..."7").contains(f[j]) { v = v * 8 + (f[j].value - 48); j += 1 }
            if let s = Unicode.Scalar(v & 0xFF) { out.append(s) }
            return j
        }
        if c == "x", i + 1 < f.count, f[i + 1].properties.isASCIIHexDigit {
            var v: UInt32 = 0, j = i + 1
            while j < f.count, j < i + 3, f[j].properties.isASCIIHexDigit { v = v * 16 + UInt32(Int(String(f[j]), radix: 16)!); j += 1 }
            if let s = Unicode.Scalar(v) { out.append(s) }
            return j
        }
        out.append("\\"); out.append(c)
        return i + 1
    }

    /// An argument of %d as bash reads it: leading blanks, a sign, then decimal, 0x hex or 0 octal; 0 for none.
    static func integer(_ s: String) -> Int64 {
        let t = s.drop(while: { $0 == " " || $0 == "\t" || $0 == "\n" })
        if let q = t.first, q == "'" || q == "\"" { return Int64(t.dropFirst().unicodeScalars.first?.value ?? 0) }
        return t.withCString { strtoll($0, nil, 0) }
    }
}

import Darwin

/// The number rules of macOS awk (bwk awk 20200816), so sizes come out as the bash build prints them.
enum Awk {
    /// A string as awk turns it into a number: the longest prefix `strtod` reads, 0 for none.
    static func number(_ text: String) -> Double {
        text.withCString { strtod($0, nil) }
    }

    /// True when awk treats the string as a number in a comparison (its `is_number`).
    static func isNumber(_ text: String) -> Bool {
        text.withCString { pointer -> Bool in
            var end: UnsafeMutablePointer<CChar>?
            errno = 0
            let value = strtod(pointer, &end)
            guard let stop = end, stop != UnsafeMutablePointer(mutating: pointer), value != Double.infinity, errno != ERANGE else { return false }
            var cursor = stop
            while cursor.pointee == 0x20 || cursor.pointee == 0x09 || cursor.pointee == 0x0A { cursor += 1 }
            return cursor.pointee == 0
        }
    }

    /// `v < 0` for a value passed with `-v`: numeric when it looks like a number, otherwise against the string "0".
    static func lessThanZero(_ text: String) -> Bool {
        if isNumber(text) { return number(text) < 0 }
        return strcmp(text, "0") < 0
    }

    /// awk's `a >= b`: its comparison treats NaN as equal to everything.
    static func ge(_ left: Double, _ right: Double) -> Bool { !((left - right) < 0) }

    /// awk's `printf "%d"` of a double: the value cut to an integer (saturating, NaN as 0, as on arm64).
    static func int(_ value: Double) -> Int64 {
        if value.isNaN { return 0 }
        if value >= 9.2233720368547758e18 { return .max }
        if value <= -9.2233720368547758e18 { return .min }
        return Int64(value)
    }

    /// C `printf` of one double, e.g. `%.1f`.
    static func format(_ fmt: String, _ value: Double) -> String {
        var buf = [CChar](repeating: 0, count: 512)
        _ = withVaList([value]) { vsnprintf(&buf, buf.count, fmt, $0) }
        return String(cString: buf)
    }

    /// A value passed with `awk -v`: awk reads its backslash escapes first.
    static func unescape(_ text: String) -> String {
        guard text.unicodeScalars.contains("\\") else { return text }
        let scalars = Array(text.unicodeScalars)
        var out = String.UnicodeScalarView(), index = 0
        let simple: [Unicode.Scalar: Unicode.Scalar] = ["\\": "\\", "n": "\n", "t": "\t", "b": "\u{08}", "f": "\u{0C}", "r": "\r", "v": "\u{0B}", "a": "\u{07}"]
        while index < scalars.count {
            guard scalars[index] == "\\" else { out.append(scalars[index]); index += 1; continue }
            guard index + 1 < scalars.count else { out.append("\\"); break }
            let scalar = scalars[index + 1]
            index += 2
            if let escaped = simple[scalar] { out.append(escaped); continue }
            if ("0"..."9").contains(scalar) {
                var code = scalar.value - 48
                for _ in 0..<2 where index < scalars.count && ("0"..."9").contains(scalars[index]) { code = 8 * code + scalars[index].value - 48; index += 1 }
                if let escaped = Unicode.Scalar(code & 0xFF) { out.append(escaped) }
                continue
            }
            out.append(scalar)
        }
        return String(out)
    }

    /// awk's `toupper`: ASCII letters only.
    static func upper(_ text: String) -> String {
        String(decoding: text.utf8.map { (0x61...0x7A).contains($0) ? $0 - 0x20 : $0 }, as: UTF8.self)
    }

    /// The records awk reads from `echo "$1"`: the lines of the value, the newline echo adds ending the last one.
    static func records(echoing text: String) -> [String] {
        let out = Bash.echo(text)
        guard !out.isEmpty else { return [] }
        return Bash.lines(String(out.unicodeScalars.dropLast()))
    }

    /// `$1` of a record with the default field separator (blanks, tabs).
    static func firstField(_ record: String) -> String {
        record.unicodeScalars.split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map { String(String.UnicodeScalarView($0)) } ?? ""
    }
}

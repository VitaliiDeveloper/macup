import Darwin

/// The number rules of macOS awk (bwk awk 20200816), so sizes come out as the bash build prints them.
enum Awk {
    /// A string as awk turns it into a number: the longest prefix `strtod` reads, 0 for none.
    static func number(_ s: String) -> Double {
        s.withCString { strtod($0, nil) }
    }

    /// True when awk treats the string as a number in a comparison (its `is_number`).
    static func isNumber(_ s: String) -> Bool {
        s.withCString { p -> Bool in
            var end: UnsafeMutablePointer<CChar>?
            errno = 0
            let r = strtod(p, &end)
            guard let e = end, e != UnsafeMutablePointer(mutating: p), r != Double.infinity, errno != ERANGE else { return false }
            var q = e
            while q.pointee == 0x20 || q.pointee == 0x09 || q.pointee == 0x0A { q += 1 }
            return q.pointee == 0
        }
    }

    /// `v < 0` for a value passed with `-v`: numeric when it looks like a number, otherwise against the string "0".
    static func lessThanZero(_ s: String) -> Bool {
        if isNumber(s) { return number(s) < 0 }
        return strcmp(s, "0") < 0
    }

    /// awk's `a >= b`: its comparison treats NaN as equal to everything.
    static func ge(_ a: Double, _ b: Double) -> Bool { !((a - b) < 0) }

    /// awk's `printf "%d"` of a double: the value cut to an integer (saturating, NaN as 0, as on arm64).
    static func int(_ d: Double) -> Int64 {
        if d.isNaN { return 0 }
        if d >= 9.2233720368547758e18 { return .max }
        if d <= -9.2233720368547758e18 { return .min }
        return Int64(d)
    }

    /// C `printf` of one double, e.g. `%.1f`.
    static func format(_ fmt: String, _ d: Double) -> String {
        var buf = [CChar](repeating: 0, count: 512)
        _ = withVaList([d]) { vsnprintf(&buf, buf.count, fmt, $0) }
        return String(cString: buf)
    }

    /// A value passed with `awk -v`: awk reads its backslash escapes first.
    static func unescape(_ s: String) -> String {
        guard s.unicodeScalars.contains("\\") else { return s }
        let u = Array(s.unicodeScalars)
        var out = String.UnicodeScalarView(), i = 0
        let simple: [Unicode.Scalar: Unicode.Scalar] = ["\\": "\\", "n": "\n", "t": "\t", "b": "\u{08}", "f": "\u{0C}", "r": "\r", "v": "\u{0B}", "a": "\u{07}"]
        while i < u.count {
            guard u[i] == "\\" else { out.append(u[i]); i += 1; continue }
            guard i + 1 < u.count else { out.append("\\"); break }
            let c = u[i + 1]
            i += 2
            if let e = simple[c] { out.append(e); continue }
            if ("0"..."9").contains(c) {
                var n = c.value - 48
                for _ in 0..<2 where i < u.count && ("0"..."9").contains(u[i]) { n = 8 * n + u[i].value - 48; i += 1 }
                if let e = Unicode.Scalar(n & 0xFF) { out.append(e) }
                continue
            }
            out.append(c)
        }
        return String(out)
    }

    /// awk's `toupper`: ASCII letters only.
    static func upper(_ s: String) -> String {
        String(decoding: s.utf8.map { (0x61...0x7A).contains($0) ? $0 - 0x20 : $0 }, as: UTF8.self)
    }

    /// The records awk reads from `echo "$1"`: the lines of the value, the newline echo adds ending the last one.
    static func records(echoing s: String) -> [String] {
        let out = Bash.echo(s)
        guard !out.isEmpty else { return [] }
        return Bash.lines(String(out.unicodeScalars.dropLast()))
    }

    /// `$1` of a record with the default field separator (blanks, tabs).
    static func firstField(_ record: String) -> String {
        record.unicodeScalars.split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map { String(String.UnicodeScalarView($0)) } ?? ""
    }
}

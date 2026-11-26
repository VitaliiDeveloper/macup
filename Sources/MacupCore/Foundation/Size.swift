import Darwin

/// Sizes in KB, as core.sh's `kb`, `hum`, `tokb` and `tokb10` give them.
public enum Size {
    /// `kb`: what `du -sk` says for a path, 0 when it does not exist. du is called as a tool, never re-implemented.
    public static func kb(_ path: String, shell: Shell) -> Int64 {
        guard access(path, F_OK) == 0 else { return 0 }
        let out = shell.capture(["du", "-sk", path]).output
        var sum = 0.0
        for line in Bash.lines(out) where !line.isEmpty {
            sum += Awk.number(Awk.firstField(line))
        }
        return Awk.int(sum)
    }

    /// `hum`: KB as Finder shows it, in decimal units ("1.2 GB", "340 MB", "12 KB"). Takes what bash would pass, text included.
    public static func hum(_ kilobytes: String) -> String {
        let kilobytes = kilobytes.isEmpty ? "0" : kilobytes
        var sign = ""
        var value = Awk.number(kilobytes)
        if Awk.lessThanZero(kilobytes) { sign = "-"; value = -value }
        let bytes = value * 1024
        if Awk.ge(bytes, 1e9) { return sign + Awk.format("%.1f GB", bytes / 1e9) }
        if Awk.ge(bytes, 1e6) { return sign + Awk.format("%.0f MB", bytes / 1e6) }
        return sign + String(Awk.int(bytes / 1e3)) + " KB"
    }

    public static func hum(_ kilobytes: Int64) -> String { hum(String(kilobytes)) }

    /// `tokb`: "1.5GB" (binary units, as `du -h` prints them) → KB.
    public static func tokb(_ text: String) -> String {
        convert(text) { unit in
            switch unit { case "TB": 1_073_741_824; case "GB": 1_048_576; case "MB": 1024; case "KB": 1; default: 0 }
        } scale: { $0 }
    }

    /// `tokb10`: "1.5GB" in decimal units, as Docker counts → KB.
    public static func tokb10(_ text: String) -> String {
        convert(text) { unit in
            switch unit { case "TB": 1e12; case "GB": 1e9; case "MB": 1e6; case "KB": 1e3; case "B": 1; default: 0 }
        } scale: { $0 / 1024 }
    }

    /// One `printf "%d"` per line of input, as awk runs its action on every record of `echo "$1"`.
    private static func convert(_ text: String, unit: (String) -> Double, scale: (Double) -> Double) -> String {
        Awk.records(echoing: text).map { rec -> String in
            let field = Awk.firstField(rec)
            let suffix = Awk.upper(String(field.unicodeScalars.filter { !("0"..."9").contains($0) && $0 != "." }))
            return String(Awk.int(scale(Awk.number(field) * unit(suffix))))
        }.joined()
    }
}

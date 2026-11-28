/// JSON written by hand, byte for byte as 2.9's core.sh's `jstr`, `jlines` and `jarr`: a backslash and a quote are escaped,
/// control characters (0x00–0x1F, newlines and tabs included) are deleted, nothing else changes (no \/ and no \u).
public enum JSON {
    public static func str(_ text: String) -> String {
        var out = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x5C: out.append(contentsOf: "\\\\".unicodeScalars)
            case 0x22: out.append(contentsOf: "\\\"".unicodeScalars)
            case 0x00...0x1F: continue
            default: out.append(scalar)
            }
        }
        return String(out)
    }

    /// `jlines`: the non-empty lines of a text as an array of strings.
    public static func lines(_ text: String) -> String {
        array(Bash.lines(text).filter { !$0.isEmpty })
    }

    /// `jarr`: the values as an array of strings.
    public static func array(_ items: [String]) -> String {
        "[" + items.map { "\"" + str($0) + "\"" }.joined(separator: ",") + "]"
    }
}

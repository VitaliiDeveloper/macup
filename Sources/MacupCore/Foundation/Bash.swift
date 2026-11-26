/// Small bash behaviours the bash build relies on without saying so.
/// Text is split on the newline scalar, never on Swift characters: "\r\n" is one Character.
enum Bash {
    /// What the builtin `echo "$1"` writes: a lone `-n`, `-e`, `-E` (or a mix of those letters) is an option, not text.
    static func echo(_ s: String) -> String {
        let u = s.unicodeScalars
        if u.count > 1, u.first == "-", u.dropFirst().allSatisfy({ $0 == "n" || $0 == "e" || $0 == "E" }) {
            return u.contains("n") ? "" : "\n"
        }
        return s + "\n"
    }

    /// `$(cmd)`: the output without its trailing newlines.
    static func substitution(_ s: String) -> String {
        var u = Substring(s).unicodeScalars
        while u.last == "\n" { u.removeLast() }
        return String(u)
    }

    /// The pieces between newlines; "a\n" gives ["a", ""].
    static func lines(_ s: String) -> [String] {
        s.unicodeScalars.split(separator: "\n", omittingEmptySubsequences: false).map { String(String.UnicodeScalarView($0)) }
    }
}

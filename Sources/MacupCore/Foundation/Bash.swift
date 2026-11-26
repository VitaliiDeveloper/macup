/// Small bash behaviours the bash build relies on without saying so.
/// Text is split on the newline scalar, never on Swift characters: "\r\n" is one Character.
enum Bash {
    /// What the builtin `echo "$1"` writes: a lone `-n`, `-e`, `-E` (or a mix of those letters) is an option, not text.
    static func echo(_ text: String) -> String {
        let scalars = text.unicodeScalars
        if scalars.count > 1, scalars.first == "-", scalars.dropFirst().allSatisfy({ $0 == "n" || $0 == "e" || $0 == "E" }) {
            return scalars.contains("n") ? "" : "\n"
        }
        return text + "\n"
    }

    /// `$(cmd)`: the output without its trailing newlines.
    static func substitution(_ text: String) -> String {
        var scalars = Substring(text).unicodeScalars
        while scalars.last == "\n" { scalars.removeLast() }
        return String(scalars)
    }

    /// The pieces between newlines; "a\n" gives ["a", ""].
    static func lines(_ text: String) -> [String] {
        text.unicodeScalars.split(separator: "\n", omittingEmptySubsequences: false).map { String(String.UnicodeScalarView($0)) }
    }
}

import Foundation

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

    /// What `echo "$1"` hands a pipe, without the newline it adds.
    static func echoed(_ text: String) -> String {
        let out = echo(text)
        return out.isEmpty ? "" : String(String.UnicodeScalarView(out.unicodeScalars.dropLast()))
    }

    /// `$(echo "$1" | tr -d ' ')`: the spaces go first, then $(…) drops the trailing newlines.
    static func echoWithoutSpaces(_ text: String) -> String {
        substitution(String(echo(text).unicodeScalars.filter { $0 != " " }))
    }

    /// `wc -l`: the newlines in the bytes.
    static func lineCount(_ data: Data) -> Int {
        data.reduce(0) { $1 == 0x0A ? $0 + 1 : $0 }
    }

    /// `[ -f "$1" ] && cat "$1"`: the bytes of a file that is there and is not a folder.
    static func regularFileContents(_ path: String) -> Data? {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue else { return nil }
        return FileManager.default.contents(atPath: path)
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

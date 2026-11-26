/// `tildify` and `expand` of core.sh. Both are a sed substitution on every line of the value:
///   tildify: sed "s|^$HOME|~|"   (HOME is a regular expression there)
///   expand:  sed "s|^~|$HOME|"   (HOME is a replacement there: & is the match, \x is x)
public struct Paths {
    public let home: String

    public init(home: String) { self.home = home }

    public func tildify(_ path: String) -> String {
        Bash.substitution(Bash.lines(stripEcho(path)).map { line -> String in
            guard let n = homePrefixLength(line) else { return line }
            return "~" + String(String.UnicodeScalarView(line.unicodeScalars.dropFirst(n)))
        }.joined(separator: "\n"))
    }

    public func expand(_ path: String) -> String {
        let replacement = Self.sedReplacement(home, match: "~")
        return Bash.substitution(Bash.lines(stripEcho(path)).map { line -> String in
            guard line.unicodeScalars.first == "~" else { return line }
            return replacement + String(String.UnicodeScalarView(line.unicodeScalars.dropFirst()))
        }.joined(separator: "\n"))
    }

    /// What `echo "$1"` hands to sed, without the newline it adds (sed keeps lines as they come).
    private func stripEcho(_ s: String) -> String {
        let e = Bash.echo(s)
        return e.isEmpty ? "" : String(String.UnicodeScalarView(e.unicodeScalars.dropLast()))
    }

    /// How many scalars at the start of the line match HOME read as a basic regular expression, nil when it does not match.
    /// HOME is a path: the only special character it realistically has is ".", which matches any one character.
    /// Anything rarer (* [ \ ^ $) is matched literally; the bash build may differ there.
    func homePrefixLength(_ line: String) -> Int? {
        let h = Array(home.unicodeScalars), l = Array(line.unicodeScalars)
        guard l.count >= h.count else { return nil }
        for (i, c) in h.enumerated() where c != "." && c != l[i] { return nil }
        return h.count
    }

    /// The text sed puts in for a replacement: & is the matched text, a backslash takes the next character literally.
    static func sedReplacement(_ r: String, match: String) -> String {
        var out = "", esc = false
        for c in r.unicodeScalars {
            if esc { out.unicodeScalars.append(c); esc = false }
            else if c == "\\" { esc = true }
            else if c == "&" { out += match }
            else { out.unicodeScalars.append(c) }
        }
        return out
    }
}

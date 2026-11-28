/// `tildify` and `expand` of 2.9's core.sh. Both are a sed substitution on every line of the value:
///   tildify: sed "s|^$HOME|~|"   (HOME is a regular expression there)
///   expand:  sed "s|^~|$HOME|"   (HOME is a replacement there: & is the match, \x is x)
public struct Paths {
    public let home: String

    public init(home: String) { self.home = home }

    public func tildify(_ path: String) -> String {
        Bash.substitution(Bash.lines(Bash.echoed(path)).map { line -> String in
            guard let prefix = homePrefixLength(line) else { return line }
            return "~" + String(String.UnicodeScalarView(line.unicodeScalars.dropFirst(prefix)))
        }.joined(separator: "\n"))
    }

    public func expand(_ path: String) -> String {
        let replacement = Self.sedReplacement(home, match: "~")
        return Bash.substitution(Bash.lines(Bash.echoed(path)).map { line -> String in
            guard line.unicodeScalars.first == "~" else { return line }
            return replacement + String(String.UnicodeScalarView(line.unicodeScalars.dropFirst()))
        }.joined(separator: "\n"))
    }

    /// How many scalars at the start of the line match HOME read as a basic regular expression, nil when it does not match.
    /// HOME is a path: the only special character it realistically has is ".", which matches any one character.
    /// Anything rarer (* [ \ ^ $) is matched literally; 2.9 may have differed there.
    func homePrefixLength(_ line: String) -> Int? {
        let homeScalars = Array(home.unicodeScalars), lineScalars = Array(line.unicodeScalars)
        guard lineScalars.count >= homeScalars.count else { return nil }
        for (index, scalar) in homeScalars.enumerated() where scalar != "." && scalar != lineScalars[index] { return nil }
        return homeScalars.count
    }

    /// The text sed puts in for a replacement: & is the matched text, a backslash takes the next character literally.
    static func sedReplacement(_ replacement: String, match: String) -> String {
        var out = "", esc = false
        for scalar in replacement.unicodeScalars {
            if esc { out.unicodeScalars.append(scalar); esc = false }
            else if scalar == "\\" { esc = true }
            else if scalar == "&" { out += match }
            else { out.unicodeScalars.append(scalar) }
        }
        return out
    }
}

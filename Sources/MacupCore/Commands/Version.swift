import Foundation

/// commands.sh `ver_gt`, `update_cmd` and the version check of summary.sh.
public enum Version {
    public static func isNewer(_ version: String, than other: String) -> Bool {
        guard !version.isEmpty, version != other else { return false }
        func parts(_ text: String) -> [Int] {
            let fields = text.split(separator: ".", omittingEmptySubsequences: false)
            return (0..<3).map { index in index < fields.count ? leadingNumber(fields[index]) : 0 }
        }
        let left = parts(version), right = parts(other)
        if left != right { return right.lexicographicallyPrecedes(left) }
        return version.utf8.lexicographicallyPrecedes(other.utf8) == false   // equal keys: sort compares the whole lines
    }

    private static func leadingNumber(_ field: Substring) -> Int {
        var digits = field.drop(while: { $0 == " " || $0 == "\t" })
        let negative = digits.first == "-"
        if negative { digits = digits.dropFirst() }
        let number = Int(digits.prefix(while: \.isASCIIDigit)) ?? 0
        return negative ? -number : number
    }

    /// check.self_update (summary.sh): the version main names, asked once a week; "" unless it is newer than this one.
    static func newerRelease(_ run: Run) -> String {
        let env = run.env
        guard !env.repo.hasPrefix("__") else { return "" }
        let stamp = env.stateDir + "/last_version_check"
        if !Files.isRegular(stamp) || !run.shell.capture(["find", stamp, "-mtime", "+6"]).output.isEmpty {
            let remote = run.shell.capture(["curl", "-fsS", "--max-time", "4", env.raw + "/main/macup"]).output
            let version = Bash.lines(remote).lazy.compactMap(versionLine).first ?? ""
            if !version.isEmpty { try? Bash.echo(version).write(toFile: stamp, atomically: false, encoding: .utf8) }
            else { _ = run.shell.spawn(["touch", stamp]).map(Shell.wait) }
        }
        let known = Bash.substitution(String(decoding: FileManager.default.contents(atPath: stamp) ?? Data(), as: UTF8.self))
        return isNewer(known, than: Env.version) ? known : ""
    }

    /// sed 's/^MACUP_VERSION="\(.*\)"/\1/p': the text up to the last quote, and whatever follows that quote.
    static func versionLine(_ line: String) -> String? {
        let prefix = "MACUP_VERSION=\""
        guard line.hasPrefix(prefix), let quote = line.lastIndex(of: "\""), quote >= line.index(line.startIndex, offsetBy: prefix.count) else { return nil }
        return String(line[line.index(line.startIndex, offsetBy: prefix.count)..<quote]) + String(line[line.index(after: quote)...])
    }

    /// `update_cmd`.
    static func updateCommand(_ run: Run) -> String {
        SelfPath.brewPrefix(SelfPath.current()).isEmpty ? "macup self-update" : "brew upgrade macup"
    }
}

private extension Character {
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}

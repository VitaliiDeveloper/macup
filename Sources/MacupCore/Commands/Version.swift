/// The commands unit fills in newerRelease and updateCommand; until then check.self_update stays on bash.
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

    static func newerRelease(_ run: Run) -> String {
        preconditionFailure("check.self_update is not ported yet")
    }

    static func updateCommand(_ run: Run) -> String {
        preconditionFailure("update_cmd is not ported yet")
    }
}

private extension Character {
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}

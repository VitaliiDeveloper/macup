import Darwin
import Foundation

extension Leftovers {
    /// One launch agent or daemon the scan judged (leftovers.sh's O_* arrays); its index is the `orph:` key.
    public struct Orphan {
        public enum Reason { case broken, empty, missing, gone }
        public let plist: String
        public let label: String
        public let program: String
        public let reason: Reason
        public let system: Bool
        public let vendor: String
        public var name: String
        /// O_DIR: the program's own folder, set when the entry becomes a candidate.
        public var folder = ""
    }

    /// Data of a deleted app (D_*); its index is the `odata:` key.
    public struct AppData {
        public let vendor: String
        public let name: String
        public let paths: String
    }

    struct App {
        let id: String
        var team = ""
        let path: String
    }

    /// What one run found, read again by the startup section and by the cleanup of phase 3.
    public final class State {
        var apps: [App] = []
        var teamsRead = false
        var scanned = false
        public internal(set) var orphans: [Orphan] = []
        public internal(set) var data: [AppData] = []
        /// O_ALLOW: the only paths a picked leftover may move to the Trash.
        public internal(set) var allow = ""
        /// LO_TTY: questions can be asked, so system items and containers are offered.
        public let interactive: Bool

        init(interactive: Bool) { self.interactive = interactive }
    }

    private static weak var owner: Run?
    private static var current: State?

    public static func state(_ run: Run) -> State {
        if let current, owner === run { return current }
        let state = State(interactive: !run.arguments.quiet && isatty(0) == 1 && isatty(1) == 1)
        owner = run
        current = state
        return state
    }

    // MARK: what bash asks its tools

    /// `tr '[:upper:]' '[:lower:]'` in a UTF-8 locale: towlower, one scalar for one (İ is i, not i and a dot).
    static func lc(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.map { scalar in
            let lower = scalar.properties.lowercaseMapping.unicodeScalars
            return lower.count == 1 ? lower.first! : scalar == "\u{130}" ? "i" : scalar
        }))
    }

    /// What `plutil -lint` accepts, parsed; nil when it does not.
    static func plist(_ file: String) -> Any? {
        guard let data = FileManager.default.contents(atPath: file) else { return nil }
        return try? PropertyListSerialization.propertyList(from: data, format: nil)
    }

    /// `pl`: `plutil -extract <key path> raw`, as $(…) keeps it; nil when there is no such value.
    static func raw(_ root: Any?, _ keyPath: String) -> String? {
        var value = root
        for key in keyPath.split(separator: ".", omittingEmptySubsequences: false) {
            if let dictionary = value as? [String: Any] { value = dictionary[String(key)] }
            else if let array = value as? [Any], let index = Int(key), array.indices.contains(index) { value = array[index] }
            else { return nil }
        }
        switch value {
        case let text as String: return Bash.substitution(text)
        case let number as NSNumber where CFGetTypeID(number) == CFBooleanGetTypeID(): return number.boolValue ? "true" : "false"
        case let number as NSNumber: return CFNumberIsFloatType(number) ? String(format: "%f", number.doubleValue) : number.stringValue
        case is [String: Any]: return ""
        case let array as [Any]: return String(array.count)
        default: return nil
        }
    }

    /// `assoc_ids`: AssociatedBundleIdentifiers as plutil writes it in JSON, with `[]"` deleted and split at commas.
    static func associatedIDs(_ root: Any?) -> [String] {
        guard let dictionary = root as? [String: Any], let array = dictionary["AssociatedBundleIdentifiers"] as? [Any] else { return [] }
        let json = array.compactMap { $0 as? String }.map { $0.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "/", with: "\\/") }
        return json.joined(separator: ",").filter { $0 != "[" && $0 != "]" && $0 != "\"" }
            .split(separator: ",", omittingEmptySubsequences: false).map(String.init).filter { !$0.isEmpty }
    }

    /// `codesign -dv --verbose=2 <path> 2>&1`, one line each.
    static func codesign(_ run: Run, _ path: String) -> [String] {
        var fds: [Int32] = [0, 0]
        guard pipe(&fds) == 0 else { return [] }
        guard let pid = run.shell.spawn(["codesign", "-dv", "--verbose=2", path], stdin: .null, stdout: .fd(fds[1]), stderr: .stdout) else {
            close(fds[0]); close(fds[1]); return []
        }
        close(fds[1])
        let data = FileHandle(fileDescriptor: fds[0], closeOnDealloc: true).readDataToEndOfFile()
        _ = Shell.wait(pid)
        return Bash.lines(String(decoding: data, as: UTF8.self))
    }

    /// `team_of`: the signing team, empty when unsigned.
    static func teamOf(_ run: Run, _ path: String) -> String {
        codesign(run, path).lazy.filter { $0.hasPrefix("TeamIdentifier=") }.map { String($0.dropFirst(15)) }.first { $0 != "not set" } ?? ""
    }

    private static let authority = try! NSRegularExpression(pattern: "^Authority=Developer ID Application: (.*) \\([A-Z0-9]*\\)$")
    private static let company = try! NSRegularExpression(pattern: ",? (Inc\\.?|LLC|Ltd\\.?)$")

    /// `signer_of`: the developer's name from the signature, without Inc, LLC or Ltd.
    static func signerOf(_ run: Run, _ path: String) -> String {
        for line in codesign(run, path) {
            let range = NSRange(location: 0, length: (line as NSString).length)
            guard let match = authority.firstMatch(in: line, range: range) else { continue }
            let name = (line as NSString).substring(with: match.range(at: 1))
            return company.stringByReplacingMatches(in: name, range: NSRange(location: 0, length: (name as NSString).length), withTemplate: "")
        }
        return ""
    }

    /// `find <args>` as a tool: its lines and exit status.
    static func find(_ run: Run, _ arguments: [String]) -> (status: Int32, lines: [String]) {
        let result = run.shell.capture(["find"] + arguments)
        return (result.status, Bash.lines(result.output).filter { !$0.isEmpty })
    }

    /// `[ -e ]`, `[ -f ]`: the path or what its symlink points at.
    static func exists(_ path: String) -> Bool {
        var info = stat()
        return !path.isEmpty && stat(path, &info) == 0
    }

    static func isFile(_ path: String) -> Bool {
        var info = stat()
        return stat(path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFREG
    }

    /// A glob of names in one folder, sorted as bash sorts them; the name's start is taken literally.
    static func glob(_ folder: String, prefix: String = "", _ pattern: String) -> [String] {
        let literal = prefix.unicodeScalars.map { "*?[\\".unicodeScalars.contains($0) ? "\\\($0)" : String($0) }.joined()
        return Checks.glob(folder, literal + pattern)
    }

    static func basename(_ path: String) -> String {
        path.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? path
    }

    static func lastComponent(_ id: String) -> String {
        id.split(separator: ".", omittingEmptySubsequences: false).last.map(String.init) ?? id
    }

    /// `sort -u` in the locale (`sort -u -t'|' -k1,1` with `key`): the first of equal ones stays.
    static func sortedUnique<Element>(_ items: [Element], key: (Element) -> String) -> [Element] {
        _ = Checks.collation
        let sorted = items.enumerated().sorted { left, right in
            let order = strcoll(key(left.element), key(right.element))
            return order != 0 ? order < 0 : left.offset < right.offset
        }.map(\.element)
        var unique: [Element] = []
        for item in sorted where unique.last.map({ strcoll(key($0), key(item)) != 0 }) ?? true { unique.append(item) }
        return unique
    }
}

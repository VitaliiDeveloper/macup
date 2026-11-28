import Darwin
import Foundation

/// check.certs and check.crashes: what Keychain and the crash reports say.
extension Tools {
    // signing certificates: Xcode says nothing until the build fails on the day one expires
    static func certs(_ run: Run) {
        let identities = capture(run.shell, 0, ["security", "find-identity", "-v", "-p", "codesigning"]).data
        guard let text = String(data: identities, encoding: .utf8) else { return }   // Python cannot read it and stops
        let expiring = expiringCertificates(text, shell: run.shell)
        guard !expiring.isEmpty else { return }
        run.out.warn("Signing certificates that expire within 30 days: %s — renew them in Xcode → Settings → Accounts", String(Run.count(expiring)))
        run.lines(expiring)
    }

    /// macup_helpers.py `certs-expiring`: of the identities `security find-identity` lists, those whose newest certificate
    /// expires within 30 days (one that already has is left to Keychain Access). Nothing where Python stops with an error.
    static func expiringCertificates(_ identities: String, shell: Shell) -> String {
        let names = Set(all(quoted, in: identities, group: 1).map { Array($0.unicodeScalars) })
        guard !names.isEmpty else { return "" }
        guard let keychain = String(data: capture(shell, 0, ["security", "find-certificate", "-a", "-p"], stdin: .null).data, encoding: .utf8) else { return "" }
        let pems = all(certificate, in: keychain, group: 0)
        var failed = false
        func openssl(_ pem: String, _ arguments: [String]) -> (status: Int32, text: String) {
            let answer = capture(shell, 0, ["openssl", "x509", "-noout"] + arguments, input: pem)
            guard let text = String(data: answer.data, encoding: .utf8) else { failed = true; return (answer.status, "") }
            return (answer.status, text)
        }
        var newest: [[Unicode.Scalar]: (end: time_t, pem: String)] = [:]
        for pem in pems {
            // one field per line: a comma in the name stays
            let subject = openssl(pem, ["-subject", "-nameopt", "multiline"]).text
            let name = Array(pythonStrip(all(commonName, in: subject, group: 1).first ?? "").unicodeScalars)
            guard names.contains(name), openssl(pem, ["-checkend", "0"]).status == 0 else { continue }
            let notAfter = pythonStrip(openssl(pem, ["-enddate"]).text).unicodeScalars.split(separator: "=", omittingEmptySubsequences: false)
            guard notAfter.count > 1, let end = certificateDate(String(String.UnicodeScalarView(notAfter[1]))) else { return "" }
            // renewed in Xcode: same name, the newer one counts
            if newest[name].map({ end > $0.end }) ?? true { newest[name] = (end, pem) }
        }
        let soon = newest.map { (name: String(String.UnicodeScalarView($0.key)), pem: $0.value.pem) }
            .sorted { Names.codePointOrder($0.name, $1.name) }
            .filter { openssl($0.pem, ["-checkend", String(30 * 86400)]).status != 0 }
            .map(\.name).joined(separator: "\n")
        return failed ? "" : soon
    }

    private static let quoted = try! NSRegularExpression(pattern: "\"([^\"]+)\"")
    private static let certificate = try! NSRegularExpression(pattern: "-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----", options: .dotMatchesLineSeparators)
    private static let commonName = try! NSRegularExpression(pattern: "^\\s*commonName\\s*=\\s*(.+)$", options: .anchorsMatchLines)

    /// `strptime(text, "%b %d %H:%M:%S %Y %Z")` (C locale) as seconds, the zone read but not applied, as Python does.
    /// openssl says GMT; Python would also take the local zone's names.
    static func certificateDate(_ text: String) -> time_t? {
        guard let groups = captures(endDate, text) else { return nil }
        let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
        guard let month = months.firstIndex(of: groups[1].lowercased()), let numbers = integers([groups[6], groups[2], groups[3], groups[4], groups[5]]) else { return nil }
        return utcSeconds(year: numbers[0], month: month + 1, day: numbers[1], hour: numbers[2], minute: numbers[3], second: numbers[4])
    }

    private static let endDate = try! NSRegularExpression(pattern: "^(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)\\s+(3[01]|[12]\\d|0[1-9]|[1-9]| [1-9])\\s+(2[0-3]|[0-1]\\d|\\d):([0-5]\\d|\\d):(6[0-1]|[0-5]\\d|\\d)\\s+(\\d\\d\\d\\d)\\s+(utc|gmt)\\z", options: .caseInsensitive)

    // an app that keeps crashing: the reports are in ~/Library/Logs/DiagnosticReports, and in Retired/ once macOS has sent them
    static func crashes(_ run: Run) {
        var apps: [String] = [], system = ""
        for line in Bash.lines(crashCounts(home: run.env.home, now: Date().timeIntervalSince1970)) {
            let fields = line.unicodeScalars.split(whereSeparator: { $0 == " " || $0 == "\t" }).map { String(String.UnicodeScalarView($0)) }
            guard fields.count > 1 else { continue }
            // awk '$1 == "A" {n=$2; $1=$2=""; sub(/^ +/,""); printf "%s ×%d\n", $0, n}'
            if fields[0] == "A" { apps.append(fields.dropFirst(2).joined(separator: " ") + " ×" + String(Awk.int(Awk.number(fields[1])))) }
            if fields[0] == "S" { system += (system.isEmpty ? "" : "\n") + fields[1] }
        }
        let shown = apps.prefix(5).joined(separator: ",").replacingOccurrences(of: ",", with: ", ", options: .literal)
        if !shown.isEmpty { run.out.info("Crashed 3 or more times in the last 7 days: %s", shown) }
        if (Checks.integer(system) ?? 0) >= 3 {
            run.out.info("macOS system processes crashed %s times this week (not yours to fix; Apple gets the reports)", system)
        }
    }

    /// macup_helpers.py `crashes`: "S <system crashes>", then "A <count> <app>" for the apps in /Applications or
    /// ~/Applications that crashed 3 or more times in the last 7 days, most first. Nothing where Python stops with an error.
    static func crashCounts(home givenHome: String, now: Double) -> String {
        var home = String(String.UnicodeScalarView(givenHome.unicodeScalars.reversed().drop(while: { $0 == "/" }).reversed()))
        if home.isEmpty { home = "/" }
        let folder = home + "/Library/Logs/DiagnosticReports"
        // glob.glob: the home folder's name is part of the pattern too
        func reports(_ pattern: String) -> [String] {
            var found = glob_t()
            defer { globfree(&found) }
            guard glob(pattern, GLOB_NOESCAPE, nil, &found) == 0 else { return [] }
            return (0..<Int(found.gl_pathc)).compactMap { found.gl_pathv[$0].map { String(cString: $0) } }
        }
        let files = ["/*.ips", "/Retired/*.ips", "/*.crash", "/Retired/*.crash"].flatMap { reports(folder + $0) }.sorted(by: Names.codePointOrder)
        var seen = Set<[Unicode.Scalar]>(), apps: [(name: [Unicode.Scalar], count: Int)] = [], system = 0
        for file in files {
            let base = PythonPath.basename(file)
            guard !seen.contains(Array(base.unicodeScalars)), !Bash.starts(base, "ExcUserFault_") else { continue }
            seen.insert(Array(base.unicodeScalars))
            var info = stat()
            guard let data = Bash.regularFileContents(file), stat(file, &info) == 0 else { continue }
            let text = universalNewlines(String(decoding: data, as: UTF8.self))
            var when = Double(info.st_mtimespec.tv_sec) + Double(info.st_mtimespec.tv_nsec) / 1e9
            var name = reportDate.stringByReplacingMatches(in: base, range: NSRange(location: 0, length: (base as NSString).length), withTemplate: "")
            var path = "", countable = true
            if file.unicodeScalars.reversed().starts(with: ".ips".unicodeScalars.reversed()) {
                let lines = text.unicodeScalars.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
                guard let header = JSONValue.parse(Data(String(String.UnicodeScalarView(lines[0])).utf8)), case .object = header else { continue }
                guard (header["bug_type"] ?? .null).pythonString == "309" else { continue }
                if let given = [header["app_name"], header["name"]].compactMap({ $0 }).first(where: \.isTruthy) {
                    switch given {
                    case .array, .object: countable = false
                    default: name = given.pythonString
                    }
                }
                if let stamp = header["timestamp"]?.string, let seconds = reportTimestamp(stamp) { when = seconds }
                let body = lines.count > 1 ? String(String.UnicodeScalarView(lines[1])) : ""
                if let literal = all(procPath, in: body, group: 1).first {
                    guard case .string(let given)? = JSONValue.parse(Data(literal.utf8)) else { continue }
                    path = given
                }
            } else {
                path = pythonStrip(all(crashPath, in: text, group: 1).first ?? "")
            }
            if now - when > 7 * 86400 { continue }
            guard Bash.starts(path, "/Applications/") || Bash.starts(path, home + "/Applications/") else { system += 1; continue }
            guard countable else { return "" }   // a list or a dict as the name: Python cannot count it and stops
            let key = Array(name.unicodeScalars)
            if let index = apps.firstIndex(where: { $0.name == key }) { apps[index].count += 1 } else { apps.append((key, 1)) }
        }
        let counted = stableSorted(apps) { $0.count > $1.count }.filter { $0.count >= 3 }
        return (["S \(system)"] + counted.map { "A \($0.count) " + String(String.UnicodeScalarView($0.name)) }).joined(separator: "\n")
    }

    private static let reportDate = try! NSRegularExpression(pattern: "[-_][0-9]{4}-[0-9][0-9]-[0-9][0-9].*")
    private static let procPath = try! NSRegularExpression(pattern: "\"procPath\"\\s*:\\s*(\"(?:[^\"\\\\]|\\\\.)*\")")
    private static let crashPath = try! NSRegularExpression(pattern: "^Path:\\s+(.+)$", options: .anchorsMatchLines)
    private static let stampPattern = try! NSRegularExpression(pattern: "^(\\d\\d\\d\\d)-(1[0-2]|0[1-9]|[1-9])-(3[01]|[12]\\d|0[1-9]|[1-9]| [1-9])\\s+(2[0-3]|[0-1]\\d|\\d):([0-5]\\d|\\d):(6[0-1]|[0-5]\\d|\\d)\\.([0-9]{1,6})\\s+((?-i:Z)|[+-]\\d\\d:?[0-5]\\d(?::?[0-5]\\d(?:\\.\\d{1,6})?)?)\\z", options: .caseInsensitive)

    /// `datetime.strptime(text, "%Y-%m-%d %H:%M:%S.%f %z").timestamp()`; nil where Python raises.
    static func reportTimestamp(_ text: String) -> Double? {
        guard let groups = captures(stampPattern, text), let numbers = integers(Array(groups[1...6])) else { return nil }
        guard let base = utcSeconds(year: numbers[0], month: numbers[1], day: numbers[2], hour: numbers[3], minute: numbers[4], second: numbers[5]) else { return nil }
        let fraction = Double(groups[7] + String(repeating: "0", count: 6 - groups[7].count))! / 1e6
        var zone = Array(groups[8].unicodeScalars), offset = 0.0
        if zone != ["Z"] {
            if zone[3] == ":" {
                zone.remove(at: 3)
                if zone.count > 5 { guard zone[5] == ":" else { return nil }; zone.remove(at: 5) }
            }
            let digits = String(String.UnicodeScalarView(zone))
            func part(_ from: Int, _ count: Int) -> Double? {
                from + count <= zone.count ? Double(String(String.UnicodeScalarView(zone[from..<from + count]))) : (from >= zone.count ? 0 : nil)
            }
            guard let hours = part(1, 2), let minutes = part(3, 2), let seconds = part(5, 2) else { return nil }
            let micro = zone.count > 8 ? Double(String(digits.unicodeScalars.dropFirst(8)) + String(repeating: "0", count: 14 - zone.count)) ?? 0 : 0
            offset = hours * 3600 + minutes * 60 + seconds + micro / 1e6
            guard offset < 86400 else { return nil }
            if zone[0] == "-" { offset = -offset }
        }
        return Double(base) + fraction - offset
    }

    /// Seconds since 1970 of a time in UTC; nil for a date datetime refuses (30 February, second 60).
    static func utcSeconds(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int) -> time_t? {
        let days = [31, year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        guard year >= 1, (1...12).contains(month), (1...days[month - 1]).contains(day), second < 60 else { return nil }
        var parts = tm(tm_sec: Int32(second), tm_min: Int32(minute), tm_hour: Int32(hour), tm_mday: Int32(day), tm_mon: Int32(month - 1),
                       tm_year: Int32(year - 1900), tm_wday: 0, tm_yday: 0, tm_isdst: 0, tm_gmtoff: 0, tm_zone: nil)
        return timegm(&parts)
    }

    /// Python's text files: "\r\n" and "\r" read as "\n".
    static func universalNewlines(_ text: String) -> String {
        var out = String.UnicodeScalarView(), afterReturn = false
        for scalar in text.unicodeScalars {
            if scalar == "\n", afterReturn { afterReturn = false; continue }
            afterReturn = scalar == "\r"
            out.append(afterReturn ? "\n" : scalar)
        }
        return String(out)
    }

    /// `str.strip()`.
    static func pythonStrip(_ text: String) -> String {
        let scalars = text.unicodeScalars.drop(while: PythonPath.isSpace).reversed().drop(while: PythonPath.isSpace).reversed()
        return String(String.UnicodeScalarView(scalars))
    }

    /// Every match of the expression (or of one of its groups) in the text, in order.
    static func all(_ expression: NSRegularExpression, in text: String, group: Int) -> [String] {
        expression.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length)).map { (text as NSString).substring(with: $0.range(at: group)) }
    }

    /// The whole match and its groups when the expression matches; a group that took no part is "".
    static func captures(_ expression: NSRegularExpression, _ text: String) -> [String]? {
        guard let match = expression.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) else { return nil }
        return (0..<match.numberOfRanges).map { match.range(at: $0).location == NSNotFound ? "" : (text as NSString).substring(with: match.range(at: $0)) }
    }

    /// Python's int() of each: blanks around are fine.
    static func integers(_ texts: [String]) -> [Int]? {
        let numbers = texts.compactMap { Int(pythonStrip($0)) }
        return numbers.count == texts.count ? numbers : nil
    }
}

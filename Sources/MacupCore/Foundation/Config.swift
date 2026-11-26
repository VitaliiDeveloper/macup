import Foundation

/// The config file (`key = value` lines): core.sh's `conf`, `conf_set`, `load_conf`.
public struct Config {
    public let path: String
    private let text: String?

    /// Reads the file once; a missing or unreadable file reads as empty, like `conf` does.
    public init(path: String) {
        self.path = path
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue,
           let d = FileManager.default.contents(atPath: path) {
            text = String(decoding: d, as: UTF8.self)
        } else {
            text = nil
        }
    }

    /// `conf key default`: the last `key = value` line, without a trailing `# comment` and blanks; the default when that is empty.
    public func value(_ key: String, _ def: String) -> String {
        var v = ""
        if let text {
            for line in Bash.lines(text) {
                if let rest = Self.match(line, key) { v = Self.stripComment(rest) }
            }
        }
        // the value goes through echo: a lone -n, -e or -E is an option there and prints nothing
        return Bash.substitution(Bash.echo(v.isEmpty ? def : v))
    }

    /// The text after `^[[:space:]]*key[[:space:]]*=[[:space:]]*`, nil when the line does not set that key.
    static func match(_ line: String, _ key: String) -> Substring.UnicodeScalarView? {
        var u = Substring(line).unicodeScalars
        u = u.drop(while: isSpace)
        guard u.starts(with: key.unicodeScalars) else { return nil }
        u = u.dropFirst(key.unicodeScalars.count).drop(while: isSpace)
        guard u.first == "=" else { return nil }
        return u.dropFirst().drop(while: isSpace)
    }

    /// sed 's/[[:space:]]*#.*$//; s/[[:space:]]*$//'
    static func stripComment(_ u: Substring.UnicodeScalarView) -> String {
        var s = u
        if let hash = s.firstIndex(of: "#") { s = s[s.startIndex..<hash] }
        while let l = s.last, isSpace(l) { s = s.dropLast() }
        return String(s)
    }

    static func isSpace(_ c: Unicode.Scalar) -> Bool {
        c == " " || c == "\t" || c == "\n" || c == "\u{0B}" || c == "\u{0C}" || c == "\r"
    }

    /// `write_default_conf`: the commented config a first `macup config`, `macup lang` or `conf_set` writes.
    public static func defaultText(lang: Lang) -> String {
        """
        # macup config. Lines starting with # are comments.
        # See every task id with:  macup tasks

        # Interface language: en, uk, ru
        language = \(lang.rawValue)

        # Tasks to never run. Whole groups work too: update.*, clean.*, check.*
        skip =

        # Opt-in tasks to turn on, e.g.: clean.stale_node_modules, clean.trash
        enable =

        # What `macup clean` / `macup all` may remove: safe, standard, aggressive
        #   safe        rebuilds itself (DerivedData, package caches, logs)
        #   standard    downloaded again on next use (Gradle, Maven, old Node/Ruby/Python patches)
        #   aggressive  browser caches; apps may be slower for a while or sign you out
        clean_level = safe

        # Delete DeviceSupport folders older than this many days
        device_support_days = 90

        # Offer to delete simulators nobody used for this many days
        simulator_days = 30

        # A project counts as stale when nothing in it changed for this many days
        stale_project_days = 90

        # Where your code lives (used by --deep and clean.stale_node_modules)
        project_dirs = ~/Developer, ~/Projects, ~/Code, ~/dev, ~/src, ~/repos, ~/work

        # Bundle ids of your own dev builds, e.g. dev.myapp, com.mycompany.myapp. Their containers in
        # ~/Library/Containers whose app is gone are offered by clean.dev_containers. Apple's are never offered.
        dev_container_prefixes =

        # Keep macup reports for this many days, and at most this many runs (one file per run; remove them all: macup reports clean)
        keep_reports_days = 30
        keep_reports = 20

        # Stop an update or cleanup command that runs longer than this many minutes (App Store installs get four times as long)
        step_timeout_minutes = 60

        """
    }

    /// `level_num`.
    public static func level(_ s: String) -> Int? {
        switch s { case "safe", "1": 1; case "standard", "2": 2; case "aggressive", "3": 3; default: nil }
    }

    /// `num`: the value when it is digits and not just "0", else the default ("007" stays "007", as in bash).
    public static func num(_ s: String, _ def: String) -> String {
        guard !s.isEmpty, s != "0", s.unicodeScalars.allSatisfy({ ("0"..."9").contains($0) }) else { return def }
        return s
    }

    /// `num` read as a number. Bash's arithmetic would read a leading 0 as octal; macup's values never have one.
    public static func num(_ s: String, _ def: Int) -> Int {
        Int(num(s, String(def))) ?? def
    }

    /// `conf_set key value`: replaces the key's lines, or adds one; writes the default config first when there is none.
    public static func set(_ key: String, _ value: String, path: String, defaultText: () -> String) throws {
        let fm = FileManager.default
        try fm.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        if !fm.fileExists(atPath: path) { try defaultText().write(toFile: path, atomically: false, encoding: .utf8) }
        let text = String(decoding: fm.contents(atPath: path) ?? Data(), as: UTF8.self)
        var lines = Bash.lines(text)
        var found = false
        for (i, l) in lines.enumerated() where setsKey(l, key) {
            // sed "s|^…=.*|key = value|": the pattern takes the whole line, and & in the value stands for it
            lines[i] = Paths.sedReplacement("\(key) = \(value)", match: l)
            found = true
        }
        let out: String
        if found {
            out = lines.joined(separator: "\n")
        } else {
            out = text + "\(key) = \(value)\n"
        }
        let h = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
        defer { try? h.close() }
        try h.truncate(atOffset: 0)
        try h.write(contentsOf: Data(out.utf8))
    }

    /// grep -qE "^[[:space:]]*key[[:space:]]*="
    static func setsKey(_ line: String, _ key: String) -> Bool {
        var u = Substring(line).unicodeScalars.drop(while: isSpace)
        guard u.starts(with: key.unicodeScalars) else { return false }
        u = u.dropFirst(key.unicodeScalars.count).drop(while: isSpace)
        return u.first == "="
    }
}

/// What `load_conf` reads: the config's values with the command line's on top.
public struct Settings {
    /// ",<skip from config>,<--skip>," without spaces.
    public var skip: String
    /// ",<enable from config>,<--enable>," without spaces.
    public var enable: String
    /// --only without spaces ("" for none).
    public var only: String
    public var deviceSupportDays: Int
    public var keepReportsDays: Int
    public var keepReports: Int
    public var staleProjectDays: Int
    public var simulatorDays: Int
    public var stepSeconds: Int
    public var level: Int
    public var devPrefixes: String
    public var projectDirs: String

    public init(config: Config, env: Env, cliSkip: String, cliOnly: String, cliEnable: String, cliLevel: Int?) {
        func nospace(_ s: String) -> String { String(s.unicodeScalars.filter { $0 != " " }) }
        // $(echo "$x" | tr -d ' '): the spaces go first, then $(…) drops the trailing newlines
        func cli(_ s: String) -> String { Bash.substitution(nospace(Bash.echo(s))) }
        skip = ",\(nospace(config.value("skip", ""))),\(cli(cliSkip)),"
        enable = ",\(nospace(config.value("enable", ""))),\(cli(cliEnable)),"
        only = cli(cliOnly)
        deviceSupportDays = Config.num(config.value("device_support_days", "90"), 90)
        keepReportsDays = Config.num(config.value("keep_reports_days", "30"), 30)
        keepReports = Config.num(config.value("keep_reports", "20"), 20)
        staleProjectDays = Config.num(config.value("stale_project_days", "90"), 90)
        simulatorDays = Config.num(config.value("simulator_days", "30"), 30)
        var step = Config.num(config.value("step_timeout_minutes", "60"), 60) * 60
        if let h = env.stepSecsHook { step = Config.num(h, step) }   // seconds, for the tests
        stepSeconds = step
        level = cliLevel ?? Config.level(config.value("clean_level", "safe")) ?? 1
        devPrefixes = config.value("dev_container_prefixes", "")
        projectDirs = config.value("project_dirs", "~/Developer, ~/Projects, ~/Code, ~/dev, ~/src, ~/repos, ~/work")
    }
}

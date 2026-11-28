import Foundation

/// The config file (`key = value` lines): core.sh's `conf`, `conf_set`, `load_conf`.
/// It reads the file as sed does in macup's locale: in UTF-8, [[:space:]] includes Unicode blanks (no-break space, ideographic
/// space), and sed stops at the first line that is not valid UTF-8, saying so on stderr every time `conf` runs.
public struct Config {
    public let path: String
    /// The lines sed gets through.
    private let lines: [String]
    /// sed stops at a byte that is not UTF-8.
    public let sedFails: Bool
    /// Whether `value` writes sed's error, as `conf` does; routing reads the config without saying anything.
    public var reportsErrors = true
    let utf8: Bool

    public init(env: Env) { self.init(path: env.conf, utf8: env.utf8Locale) }

    /// Reads the file once; a missing or unreadable file reads as empty, like `conf` does.
    public init(path: String, utf8: Bool = true) {
        self.path = path
        self.utf8 = utf8
        guard let contents = Bash.regularFileContents(path) else { lines = []; sedFails = false; return }
        var out: [String] = [], fails = false
        for raw in contents.split(separator: 0x0A, omittingEmptySubsequences: false) {
            if let line = String(bytes: raw, encoding: .utf8) { out.append(line); continue }
            if utf8 { fails = true; break }
            out.append(String(decoding: raw, as: UTF8.self))
        }
        lines = out
        sedFails = fails
    }

    /// `conf key default`: the last `key = value` line, without a trailing `# comment` and blanks; the default when that is empty.
    public func value(_ key: String, _ def: String) -> String {
        if sedFails, reportsErrors { Shell.writeText("sed: RE error: illegal byte sequence\n", to: 2) }
        var result = ""
        for line in lines {
            if let rest = match(line, key) { result = stripComment(rest) }
        }
        // the value goes through echo: a lone -n, -e or -E is an option there and prints nothing
        return Bash.substitution(Bash.echo(result.isEmpty ? def : result))
    }

    /// The text after `^[[:space:]]*key[[:space:]]*=[[:space:]]*`, nil when the line does not set that key.
    func match(_ line: String, _ key: String) -> Substring.UnicodeScalarView? {
        var scalars = Substring(line).unicodeScalars
        scalars = scalars.drop(while: isSpace)
        guard scalars.starts(with: key.unicodeScalars) else { return nil }
        scalars = scalars.dropFirst(key.unicodeScalars.count).drop(while: isSpace)
        guard scalars.first == "=" else { return nil }
        return scalars.dropFirst().drop(while: isSpace)
    }

    /// sed 's/[[:space:]]*#.*$//; s/[[:space:]]*$//'
    func stripComment(_ scalars: Substring.UnicodeScalarView) -> String {
        var kept = scalars
        if let hash = kept.firstIndex(of: "#") { kept = kept[kept.startIndex..<hash] }
        while let last = kept.last, isSpace(last) { kept = kept.dropLast() }
        return String(kept)
    }

    /// What macOS's iswspace counts beyond ASCII in en_US.UTF-8 (listed from libc; U+0085 is not one).
    private static let unicodeBlanks: Set<UInt32> = [0xA0, 0x1680, 0x2000, 0x2001, 0x2002, 0x2003, 0x2004, 0x2005, 0x2006, 0x2007,
                                                    0x2008, 0x2009, 0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000]

    func isSpace(_ scalar: Unicode.Scalar) -> Bool { Self.isSpace(scalar, utf8: utf8) }

    /// [[:space:]]: the locale's blanks in UTF-8, the six ASCII ones otherwise.
    static func isSpace(_ scalar: Unicode.Scalar, utf8: Bool) -> Bool {
        if scalar.isASCII || !utf8 { return scalar == " " || scalar == "\t" || scalar == "\n" || scalar == "\u{0B}" || scalar == "\u{0C}" || scalar == "\r" }
        return unicodeBlanks.contains(scalar.value)
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
    public static func level(_ text: String) -> Int? {
        switch text { case "safe", "1": 1; case "standard", "2": 2; case "aggressive", "3": 3; default: nil }
    }

    /// `num`: the value when it is digits and not just "0", else the default ("007" stays "007", as in bash).
    public static func num(_ text: String, _ def: String) -> String {
        guard !text.isEmpty, text != "0", text.unicodeScalars.allSatisfy({ ("0"..."9").contains($0) }) else { return def }
        return text
    }

    /// `num` read as a number, leading zeros and all in decimal: 010 is 10. Bash's arithmetic read step_timeout_minutes 010 as
    /// octal 8 and gave up on 08 and 09 (intended difference).
    public static func num(_ text: String, _ def: Int) -> Int {
        Int(num(text, String(def))) ?? def
    }

    /// `conf_set key value`: replaces the key's lines, or adds one; writes the default config first when there is none.
    /// Like `sed -i`, it leaves a symlinked config, or one sed cannot read, alone when it would have to replace a line.
    public static func set(_ key: String, _ value: String, path: String, utf8: Bool = true, defaultText: () -> String) throws {
        let fm = FileManager.default
        try fm.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        if !fm.fileExists(atPath: path) { try defaultText().write(toFile: path, atomically: false, encoding: .utf8) }
        let data = fm.contents(atPath: path) ?? Data()
        let conf = Config(path: path, utf8: utf8)
        var raws = data.split(separator: 0x0A, omittingEmptySubsequences: false).map { Data($0) }
        var found = false
        for (index, raw) in raws.enumerated() {
            let line = String(decoding: raw, as: UTF8.self)
            guard conf.setsKey(line, key) else { continue }
            // sed "s|^…=.*|key = value|": the pattern takes the whole line, and & in the value stands for it
            raws[index] = Data(Paths.sedReplacement("\(key) = \(value)", match: line).utf8)
            found = true
        }
        let out: Data
        if found {
            let link = (try? fm.destinationOfSymbolicLink(atPath: path)) != nil
            if link || conf.sedFails { return }
            out = Data(raws.joined(separator: [0x0A]))
        } else {
            out = data + Data("\(key) = \(value)\n".utf8)
        }
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
        defer { try? handle.close() }
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: out)
    }

    /// grep -qE "^[[:space:]]*key[[:space:]]*="
    func setsKey(_ line: String, _ key: String) -> Bool { match(line, key) != nil }
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
        func nospace(_ text: String) -> String { String(text.unicodeScalars.filter { $0 != " " }) }
        skip = ",\(nospace(config.value("skip", ""))),\(Bash.echoWithoutSpaces(cliSkip)),"
        enable = ",\(nospace(config.value("enable", ""))),\(Bash.echoWithoutSpaces(cliEnable)),"
        only = Bash.echoWithoutSpaces(cliOnly)
        deviceSupportDays = Config.num(config.value("device_support_days", "90"), 90)
        keepReportsDays = Config.num(config.value("keep_reports_days", "30"), 30)
        keepReports = Config.num(config.value("keep_reports", "20"), 20)
        staleProjectDays = Config.num(config.value("stale_project_days", "90"), 90)
        simulatorDays = Config.num(config.value("simulator_days", "30"), 30)
        var step = Config.num(config.value("step_timeout_minutes", "60"), 60) * 60
        if let seconds = env.stepSecsHook { step = Config.num(seconds, step) }   // seconds, for the tests
        stepSeconds = step
        level = cliLevel ?? Config.level(config.value("clean_level", "safe")) ?? 1
        devPrefixes = config.value("dev_container_prefixes", "")
        projectDirs = config.value("project_dirs", "~/Developer, ~/Projects, ~/Code, ~/dev, ~/src, ~/repos, ~/work")
    }
}

/// The command line as arguments.sh reads it: left to right, the last command word wins, options anywhere.
public struct Arguments: Equatable {
    /// One-off commands (arguments.sh's CMD); they run before any check, update or cleanup.
    public enum Command: String, CaseIterable {
        case lang, last, history, reports, tasks, config, selfUpdate = "self_update", uninstall, schedule, help, version
    }

    public var dry = false
    public var doUpdate = true
    public var doClean = true
    public var deep = false
    /// check, all, update or clean.
    public var action: String?
    public var command: Command?
    public var langArg = ""
    public var schedArg = ""
    public var repArg = ""
    public var yes = false
    public var quiet = false
    public var json = false
    public var notify = false
    public var noColor = false
    /// As given: ",a,b" for --skip a,b (spaces are taken out when the config is loaded).
    public var cliSkip = ""
    public var cliOnly = ""
    public var cliEnable = ""
    /// ",<keys>," once `applyPick` has run.
    public var pick = ""
    public var level: Int?
    /// --lang.
    public var lang: Lang?

    /// What makes arguments.sh stop: it prints a message and exits (2 for a bad value, 1 for an unknown word).
    public enum Failure: Error, Equatable {
        case badLevel
        case badLang
        case unknownCommand(String)
    }

    public init() {}

    public static func parse(_ argv: [String]) throws -> Arguments {
        var a = Arguments()
        var i = 0
        // $2: the next word, "" when there is none (bash then shifts past the end, which ends the loop)
        func next() -> String { i + 1 < argv.count ? argv[i + 1] : "" }
        // "schedule weekly": the next word is the command's when it is there and not an option
        func operand() -> String? {
            let n = next()
            return n.isEmpty || n.hasPrefix("-") ? nil : n
        }
        func value(_ w: String) -> String { String(w[w.index(after: w.firstIndex(of: "=")!)...]) }
        while i < argv.count {
            let w = argv[i]
            switch w {
            case "check", "-n", "--dry-run": a.dry = true; a.action = "check"
            case "all", "run": a.action = "all"
            case "update", "--no-clean": a.doClean = false; a.action = "update"
            case "clean", "--no-update": a.doUpdate = false; a.action = "clean"
            case "deep", "--deep": a.deep = true
            case "--skip": a.cliSkip += "," + next(); i += 1
            case "--only": a.cliOnly += "," + next(); i += 1
            case "--enable": a.cliEnable += "," + next(); i += 1
            case "--pick": a.pick += "," + next(); i += 1
            case "--level":
                guard let l = Config.level(next()) else { throw Failure.badLevel }
                a.level = l; i += 1
            case "--lang":
                guard let l = Lang.option(next()) else { throw Failure.badLang }
                a.lang = l; i += 1
            case "--no-color": a.noColor = true
            case "-y", "--yes": a.yes = true
            case "-q", "--quiet": a.quiet = true
            case "--json": a.json = true; a.quiet = true
            case "--notify": a.notify = true
            case "schedule": a.command = .schedule; if let o = operand() { a.schedArg = o; i += 1 }
            case "lang", "language": a.command = .lang; if let o = operand() { a.langArg = o; i += 1 }
            case "last", "--last": a.command = .last
            case "history", "--history": a.command = .history
            case "reports", "--reports": a.command = .reports; if let o = operand() { a.repArg = o; i += 1 }
            case "tasks", "--tasks": a.command = .tasks
            case "config", "--config": a.command = .config
            case "self-update", "selfupdate", "upgrade": a.command = .selfUpdate
            case "uninstall": a.command = .uninstall
            case "help", "-h", "--help": a.command = .help
            case "version", "-v", "--version": a.command = .version
            default:
                if w.hasPrefix("--skip=") { a.cliSkip += "," + value(w) }
                else if w.hasPrefix("--only=") { a.cliOnly += "," + value(w) }
                else if w.hasPrefix("--enable=") { a.cliEnable += "," + value(w) }
                else if w.hasPrefix("--pick=") { a.pick += "," + value(w) }
                else if w.hasPrefix("--level=") {
                    guard let l = Config.level(value(w)) else { throw Failure.badLevel }
                    a.level = l
                } else if w.hasPrefix("--lang=") {
                    guard let l = Lang.option(value(w)) else { throw Failure.badLang }
                    a.lang = l
                } else { throw Failure.unknownCommand(w) }
            }
            i += 1
        }
        a.applyPick()
        return a
    }

    /// --pick: clean exactly the items a check listed (their "key" in --json), nothing else, and run no check either,
    /// unless --only names some.
    mutating func applyPick() {
        guard !pick.isEmpty else { return }
        pick = "," + Bash.substitution(String(Bash.echo(pick).unicodeScalars.filter { $0 != " " })) + ","
        dry = false; doUpdate = false; doClean = true; action = "clean"
        if cliOnly.isEmpty { cliOnly = "clean.*" }
    }

    /// help, version and uninstall run under sudo; anything else refuses to.
    public var runsUnderSudo: Bool {
        command == .help || command == .version || command == .uninstall
    }
}

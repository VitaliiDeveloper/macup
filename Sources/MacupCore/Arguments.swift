/// The command line as 2.9's arguments.sh reads it: left to right, the last command word wins, options anywhere.
public struct Arguments: Equatable {
    /// One-off commands (2.9's arguments.sh's CMD); they run before any check, update or cleanup.
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

    /// What makes 2.9's arguments.sh stop: it prints a message and exits (2 for a bad value, 1 for an unknown word, said in the
    /// language a --lang before it chose).
    public enum Failure: Error, Equatable {
        case badLevel
        case badLang
        case unknownCommand(String, lang: Lang?)
    }

    public init() {}

    public static func parse(_ argv: [String]) throws -> Arguments {
        var result = Arguments()
        var index = 0
        // $2: the next word, "" when there is none (bash then shifts past the end, which ends the loop)
        func next() -> String { index + 1 < argv.count ? argv[index + 1] : "" }
        // "schedule weekly": the next word is the command's when it is there and not an option
        func operand() -> String? {
            let following = next()
            return following.isEmpty || following.hasPrefix("-") ? nil : following
        }
        func value(_ option: String) -> String { String(option[option.index(after: option.firstIndex(of: "=")!)...]) }
        while index < argv.count {
            let word = argv[index]
            switch word {
            case "check", "-n", "--dry-run": result.dry = true; result.action = "check"
            case "all", "run": result.action = "all"
            case "update", "--no-clean": result.doClean = false; result.action = "update"
            case "clean", "--no-update": result.doUpdate = false; result.action = "clean"
            case "deep", "--deep": result.deep = true
            case "--skip": result.cliSkip += "," + next(); index += 1
            case "--only": result.cliOnly += "," + next(); index += 1
            case "--enable": result.cliEnable += "," + next(); index += 1
            case "--pick": result.pick += "," + next(); index += 1
            case "--level":
                guard let level = Config.level(next()) else { throw Failure.badLevel }
                result.level = level; index += 1
            case "--lang":
                guard let lang = Lang.option(next()) else { throw Failure.badLang }
                result.lang = lang; index += 1
            case "--no-color": result.noColor = true
            case "-y", "--yes": result.yes = true
            case "-q", "--quiet": result.quiet = true
            case "--json": result.json = true; result.quiet = true
            case "--notify": result.notify = true
            case "schedule": result.command = .schedule; if let argument = operand() { result.schedArg = argument; index += 1 }
            case "lang", "language": result.command = .lang; if let argument = operand() { result.langArg = argument; index += 1 }
            case "last", "--last": result.command = .last
            case "history", "--history": result.command = .history
            case "reports", "--reports": result.command = .reports; if let argument = operand() { result.repArg = argument; index += 1 }
            case "tasks", "--tasks": result.command = .tasks
            case "config", "--config": result.command = .config
            case "self-update", "selfupdate", "upgrade": result.command = .selfUpdate
            case "uninstall": result.command = .uninstall
            case "help", "-h", "--help": result.command = .help
            case "version", "-v", "--version": result.command = .version
            default:
                if word.hasPrefix("--skip=") { result.cliSkip += "," + value(word) }
                else if word.hasPrefix("--only=") { result.cliOnly += "," + value(word) }
                else if word.hasPrefix("--enable=") { result.cliEnable += "," + value(word) }
                else if word.hasPrefix("--pick=") { result.pick += "," + value(word) }
                else if word.hasPrefix("--level=") {
                    guard let level = Config.level(value(word)) else { throw Failure.badLevel }
                    result.level = level
                } else if word.hasPrefix("--lang=") {
                    guard let lang = Lang.option(value(word)) else { throw Failure.badLang }
                    result.lang = lang
                } else { throw Failure.unknownCommand(word, lang: result.lang) }
            }
            index += 1
        }
        result.applyPick()
        if result.action == nil, result.deep { result.dry = true }   // `macup --deep` alone is a deep check
        return result
    }

    /// --pick: clean exactly the items a check listed (their "key" in --json), nothing else, and run no check either,
    /// unless --only names some.
    mutating func applyPick() {
        guard !pick.isEmpty else { return }
        pick = "," + Bash.echoWithoutSpaces(pick) + ","
        dry = false; doUpdate = false; doClean = true; action = "clean"
        if cliOnly.isEmpty { cliOnly = "clean.*" }
    }

    /// help, version and uninstall run under sudo; anything else refuses to.
    public var runsUnderSudo: Bool {
        command == .help || command == .version || command == .uninstall
    }
}

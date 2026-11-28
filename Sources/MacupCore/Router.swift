import Darwin

/// Which build runs an invocation (the plan's "Routing"). Whole runs are routed, never split: the Swift build runs a
/// command itself only when it is ported and, for a run, every task it would do is ported. Anything else, a command line
/// arguments.sh would reject included, goes whole to the bash build, which then says what it always says.
public enum Router {
    public enum Route: Equatable {
        case bash
        case swift(Arguments)
    }

    /// Commands the Swift build answers with "not available in this build" instead of handing them to bash:
    /// the bash self-update would write a script over the binary, the bash schedule would run the binary with /bin/bash.
    public static let unavailable: Set<Arguments.Command> = [.selfUpdate, .schedule]

    /// `terminal`: stdin and stdout are a terminal, where a check ends with the pick.
    public static func route(_ argv: [String], env: Env, ported: Set<String> = Ported.commands, portedTasks: Set<String> = Ported.tasks,
                             terminal: Bool = isatty(0) == 1 && isatty(1) == 1) -> Route {
        guard let arguments = try? Arguments.parse(argv) else { return .bash }
        func settings() -> Settings {
            var config = Config(env: env)
            config.reportsErrors = false   // bash says it, once it has the run
            return Settings(config: config, env: env, cliSkip: arguments.cliSkip, cliOnly: arguments.cliOnly, cliEnable: arguments.cliEnable, cliLevel: arguments.level)
        }
        if let command = arguments.command {
            if unavailable.contains(command) { return .swift(arguments) }
            guard ported.contains(command.rawValue) else { return .bash }
            // the one-off commands that load the config (load_conf) share its arithmetic
            if command == .tasks, settings().bashArithmeticFails { return .bash }
            return .swift(arguments)
        }
        // no command word and no run: the menu on a terminal (its choice 8 loads the config), the help anywhere else
        if arguments.action == nil, !arguments.deep { return ported.contains("menu") && !settings().bashArithmeticFails ? .swift(arguments) : .bash }
        // a run: check, all, update, clean, or --deep alone
        guard ported.contains("run") else { return .bash }
        // the deep scan is no task; --pick and the pick at the end of a check on a terminal come with phase 3
        if arguments.deep, !ported.contains("deep") { return .bash }
        if !arguments.pick.isEmpty, !ported.contains("pick") { return .bash }
        let settings = settings()
        guard !settings.bashArithmeticFails, Tasks.unknown("\(settings.only),\(arguments.cliSkip),\(arguments.cliEnable)").isEmpty else { return .bash }
        // allowed, not only on: a cleaner registers what it finds for an opt-in task too, to be picked
        let allowed = Tasks.all.map(\.id).filter(Selection(settings).allowed)
        if arguments.dry, terminal, !arguments.quiet, !ported.contains("pick"), allowed.contains(where: { $0.hasPrefix("clean.") }) { return .bash }
        return allowed.allSatisfy(portedTasks.contains) ? .swift(arguments) : .bash
    }
}

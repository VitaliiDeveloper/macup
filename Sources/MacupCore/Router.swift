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

    public static func route(_ argv: [String], env: Env, ported: Set<String> = Ported.commands, portedTasks: Set<String> = Ported.tasks) -> Route {
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
        // no command word: a run (check, all, update, clean, or --deep alone); without one, the menu or the help
        guard arguments.action != nil || arguments.deep, ported.contains("run") else { return .bash }
        let settings = settings()
        guard !settings.bashArithmeticFails, Tasks.unknown("\(settings.only),\(arguments.cliSkip),\(arguments.cliEnable)").isEmpty else { return .bash }
        return Selection(settings).selected.allSatisfy(portedTasks.contains) ? .swift(arguments) : .bash
    }
}

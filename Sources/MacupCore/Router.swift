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
        guard let a = try? Arguments.parse(argv) else { return .bash }
        if let c = a.command {
            if unavailable.contains(c) || ported.contains(c.rawValue) { return .swift(a) }
            return .bash
        }
        // no command word: a run (check, all, update, clean, or --deep alone); without one, the menu or the help
        guard a.action != nil || a.deep, ported.contains("run") else { return .bash }
        let settings = Settings(config: Config(path: env.conf), env: env, cliSkip: a.cliSkip, cliOnly: a.cliOnly, cliEnable: a.cliEnable, cliLevel: a.level)
        guard Tasks.unknown("\(settings.only),\(a.cliSkip),\(a.cliEnable)").isEmpty else { return .bash }
        return Selection(settings).selected.allSatisfy(portedTasks.contains) ? .swift(a) : .bash
    }
}

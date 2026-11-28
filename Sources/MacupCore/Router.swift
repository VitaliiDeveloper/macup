import Darwin

/// Which build runs an invocation (the plan's "Routing"). Whole runs are routed, never split: the Swift build runs a
/// command itself only when it is ported and, for a run, every task it would do is ported; anything else goes whole to the
/// bash build. A command line arguments.sh rejects gets its message from Swift.
public enum Router {
    public enum Route: Equatable {
        case bash
        case swift(Arguments)
        /// A command line arguments.sh rejects.
        case rejected(Arguments.Failure)
    }

    /// Commands the Swift build answers with "not available in this build" instead of handing them to bash:
    /// the bash self-update would write a script over the binary, the bash schedule would run the binary with /bin/bash.
    public static let unavailable: Set<Arguments.Command> = [.selfUpdate, .schedule]

    /// `terminal`: stdin and stdout are a terminal, where a check ends with the pick.
    public static func route(_ argv: [String], env: Env, ported: Set<String> = Ported.commands, portedTasks: Set<String> = Ported.tasks,
                             terminal: Bool = isatty(0) == 1 && isatty(1) == 1) -> Route {
        let arguments: Arguments
        do { arguments = try Arguments.parse(argv) } catch let failure as Arguments.Failure { return .rejected(failure) } catch { return .bash }
        if let command = arguments.command {
            if unavailable.contains(command) { return .swift(arguments) }
            guard ported.contains(command.rawValue) else { return .bash }
            return .swift(arguments)
        }
        // no command word and no run: the menu on a terminal (its choice 8 loads the config), the help anywhere else
        if arguments.action == nil, !arguments.deep { return ported.contains("menu") ? .swift(arguments) : .bash }
        // a run: check, all, update, clean, or --deep alone
        guard ported.contains("run") else { return .bash }
        // the deep scan is no task; --pick and the pick at the end of a check on a terminal come with phase 3
        if arguments.deep, !ported.contains("deep") { return .bash }
        if !arguments.pick.isEmpty, !ported.contains("pick") { return .bash }
        var config = Config(env: env)
        config.reportsErrors = false   // the run says it
        let settings = Settings(config: config, env: env, cliSkip: arguments.cliSkip, cliOnly: arguments.cliOnly, cliEnable: arguments.cliEnable, cliLevel: arguments.level)
        // allowed, not only on: a cleaner registers what it finds for an opt-in task too, to be picked
        let allowed = Tasks.all.map(\.id).filter(Selection(settings).allowed)
        if arguments.dry, terminal, !arguments.quiet, !ported.contains("pick"), allowed.contains(where: { $0.hasPrefix("clean.") }) { return .bash }
        return allowed.allSatisfy(portedTasks.contains) ? .swift(arguments) : .bash
    }
}

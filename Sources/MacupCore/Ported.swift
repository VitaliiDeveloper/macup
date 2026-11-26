/// What the Swift build runs itself; anything else is handed whole to the bash build it carries (see `Router`).
/// Each module keeps its own list in <Module>/Ported+<Module>.swift, so units working in parallel never edit the same file.
public enum Ported {
    public struct Unit {
        /// One-off commands as arguments.sh names them (help, version, tasks, …); "run" is the main pass (check, all, update, clean).
        public var commands: [String] = []
        /// Task ids.
        public var tasks: [String] = []
    }

    static let units: [Unit] = [run, cleanup, checks, updates, tools, cleaners, leftovers, commandsUnit]

    public static let commands: Set<String> = Set(units.flatMap(\.commands))
    public static let tasks: Set<String> = Set(units.flatMap(\.tasks))
}

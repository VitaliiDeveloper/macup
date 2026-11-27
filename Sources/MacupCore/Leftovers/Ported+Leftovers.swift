extension Ported {
    /// orphan_* are only ever cleaned when picked (the pick is phase 3), so a run without the pick has all there is of them.
    /// The dev container scan moves what it finds to the Trash (phase 3): with a terminal it stays on bash, without one there is nothing to scan.
    static let leftovers = Unit(commands: [], tasks: ["check.startup", "clean.orphan_agents", "clean.orphan_data"], dryTasks: ["clean.dev_containers"])
}

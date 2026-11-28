extension Ported {
    /// orphan_* and dev containers are only ever cleaned when picked; until the pick is ported, a run that would pick goes to bash.
    static let leftovers = Unit(commands: [], tasks: ["check.startup", "clean.orphan_agents", "clean.orphan_data", "clean.dev_containers"])
}

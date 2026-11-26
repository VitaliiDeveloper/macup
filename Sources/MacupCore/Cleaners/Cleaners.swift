/// The cleaners unit fills in the rest; until then the router keeps runs with its tasks on bash.
enum Cleaners {
    static func register(_ run: Run) {
        let paths = run.env.paths
        // the slow measurements start at once and run side by side
        for row in CacheTables.folders where row.tool.isEmpty || run.shell.have(row.tool) {
            if run.taskAllowed(row.task) { run.measure.start(paths.expand(row.folder)) }
        }
        for row in CacheTables.folders where row.tool.isEmpty || run.shell.have(row.tool) {
            Cleanup.registerFolder(run, task: row.task, level: row.level, label: row.label, path: paths.expand(row.folder), busy: row.busy)
        }
    }
}

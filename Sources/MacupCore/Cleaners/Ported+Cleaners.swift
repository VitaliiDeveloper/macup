extension Ported {
    /// Tasks whose candidates are all of the empty kind are cleaned too; the rest register for a check, and phase 3 cleans them.
    static let cleaners = Unit(
        commands: [],
        tasks: ["clean.derived_data", "clean.xcode_previews", "clean.sim_caches", "clean.spm", "clean.cocoapods", "clean.carthage", "clean.yarn", "clean.bun",
                "clean.poetry", "clean.cargo", "clean.android", "clean.trash", "clean.maven", "clean.app_caches", "clean.jetbrains", "clean.editors", "clean.browsers"],
        dryTasks: ["clean.npm", "clean.pnpm", "clean.gradle", "clean.pip", "clean.uv", "clean.go", "clean.go_mod", "clean.deno", "clean.device_support",
                   "clean.sim_runtimes", "clean.sim_erase", "clean.sim_unused", "clean.device_logs", "clean.sim_unavailable", "clean.brew", "clean.logs",
                   "clean.quicklook", "clean.stale_node_modules", "clean.stale_artifacts", "clean.profiles", "clean.docker", "clean.docker_images",
                   "clean.docker_containers", "clean.brew_autoremove", "clean.old_versions", "clean.playwright", "clean.ai_tools", "clean.editor_workspaces"])
}

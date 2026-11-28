/// The task table of 2.9's core.sh (`TASKS`): id, whether it is on by default, what it does. `macup tasks` prints it in this order.
public struct Task: Equatable {
    public let id: String
    /// On unless turned off; an opt-in task is off until `enable` names it.
    public let on: Bool
    public let text: String

    /// "check", "update" or "clean".
    public var group: String { String(id.prefix(while: { $0 != "." })) }
}

public enum Tasks {
    public static let all: [Task] = [
        Task(id: "check.system", on: true, text: "macOS version, model, uptime (warns after 14 days without restart)"),
        Task(id: "check.disk", on: true, text: "Free space, disk health (SMART), local Time Machine snapshots"),
        Task(id: "check.memory", on: true, text: "Memory pressure and swap usage"),
        Task(id: "check.cpu", on: true, text: "Load average, top CPU and memory processes, thermal throttling"),
        Task(id: "check.battery", on: true, text: "Charge, cycle count, maximum capacity, condition"),
        Task(id: "check.security", on: true, text: "FileVault, Firewall, SIP, Gatekeeper, automatic updates"),
        Task(id: "check.time_machine", on: true, text: "Time Machine: last backup date (part of check.security)"),
        Task(id: "check.startup", on: true, text: "Third-party launch agents/daemons, orphaned ones pointing at deleted apps"),
        Task(id: "check.mcp", on: true, text: "Claude Code MCP servers that fail to connect"),
        Task(id: "check.brew_doctor", on: true, text: "brew doctor warnings"),
        Task(id: "check.macos_updates", on: true, text: "Pending macOS updates (never installed automatically)"),
        Task(id: "check.xcode", on: true, text: "Xcode, command line tools, simulator runtimes"),
        Task(id: "check.devtools", on: true, text: "Versions of Swift, CocoaPods, Flutter, Node, Ruby, Python, Codex"),
        Task(id: "check.commands", on: true, text: "Commands that cannot start: a missing interpreter (node, python) or a broken link"),
        Task(id: "check.docker", on: true, text: "Docker disk usage (if Docker is running)"),
        Task(id: "check.gh", on: true, text: "GitHub CLI: a saved login that no longer works"),
        Task(id: "check.certs", on: true, text: "Code signing certificates that expire within 30 days"),
        Task(id: "check.crashes", on: true, text: "Apps that crashed several times in the last 7 days"),
        Task(id: "check.sizes", on: true, text: "Sizes of things macup never deletes: Archives, Trash, caches, pub-cache"),
        Task(id: "check.creative", on: true, text: "Render and preview caches of Final Cut, Premiere, DaVinci, Lightroom, Camera Raw (measured only)"),
        Task(id: "check.trends", on: true, text: "Compare with the previous run: free space, swap, battery capacity"),
        Task(id: "check.self_update", on: true, text: "Tell when a newer macup is on GitHub (once a week)"),
        Task(id: "update.claude", on: true, text: "Claude Code CLI, plugin marketplaces, plugins"),
        Task(id: "update.npm", on: true, text: "Global npm packages (Codex, Playwright, ...)"),
        Task(id: "update.skills", on: true, text: "Agent skills in ~/.agents (npx skills update -g)"),
        Task(id: "update.brew", on: true, text: "Homebrew formulae and casks"),
        Task(id: "update.mas", on: true, text: "App Store apps (needs mas)"),
        Task(id: "update.pipx", on: true, text: "pipx-installed tools"),
        Task(id: "update.uv", on: true, text: "uv-installed tools"),
        Task(id: "update.rustup", on: true, text: "Rust toolchains"),
        Task(id: "update.omz", on: true, text: "Oh My Zsh"),
        Task(id: "update.gh_ext", on: true, text: "GitHub CLI extensions"),
        Task(id: "update.pnpm", on: true, text: "Global pnpm packages"),
        Task(id: "update.bun", on: true, text: "Bun (bun upgrade; a Homebrew install is left to Homebrew)"),
        Task(id: "update.deno", on: true, text: "Deno (deno upgrade; a Homebrew install is left to Homebrew)"),
        Task(id: "update.cargo", on: true, text: "Programs installed with cargo install (needs cargo-update)"),
        Task(id: "update.mise", on: true, text: "Tools managed by mise"),
        Task(id: "update.asdf", on: true, text: "asdf plugins"),
        Task(id: "update.editor_ext", on: true, text: "VS Code, Cursor, Windsurf and VSCodium extensions"),
        Task(id: "update.gcloud", on: true, text: "Google Cloud SDK components (its own install; a Homebrew install is left to Homebrew)"),
        Task(id: "update.dotnet", on: true, text: ".NET global tools (needs .NET 9 or later)"),
        Task(id: "update.composer", on: true, text: "Composer global packages"),
        Task(id: "update.gem", on: false, text: "Ruby gems (opt-in; never the system Ruby)"),
        Task(id: "update.grok", on: true, text: "Grok CLI (grok update)"),
        Task(id: "update.agy", on: true, text: "Antigravity CLI (agy update)"),
        Task(id: "update.apps", on: true, text: "Apps outside Homebrew and the App Store that update themselves (only reported)"),
        Task(id: "clean.derived_data", on: true, text: "Xcode DerivedData (skipped while Xcode is open)"),
        Task(id: "clean.xcode_previews", on: true, text: "SwiftUI previews cache (skipped while Xcode is open)"),
        Task(id: "clean.device_support", on: true, text: "iOS/watchOS DeviceSupport folders older than device_support_days"),
        Task(id: "clean.device_logs", on: true, text: "iOS device logs older than 90 days"),
        Task(id: "clean.sim_unavailable", on: true, text: "Simulators whose runtime is gone"),
        Task(id: "clean.sim_runtimes", on: false, text: "Simulator runtimes you no longer need (only when you pick them; Xcode downloads them again)"),
        Task(id: "clean.sim_erase", on: false, text: "Erase the apps and data of a simulator (only when you pick it)"),
        Task(id: "clean.sim_unused", on: false, text: "Simulators unused for simulator_days (only when you pick them)"),
        Task(id: "clean.sim_caches", on: true, text: "CoreSimulator caches"),
        Task(id: "clean.spm", on: true, text: "SwiftPM cache"),
        Task(id: "clean.cocoapods", on: true, text: "CocoaPods cache"),
        Task(id: "clean.carthage", on: true, text: "Carthage cache"),
        Task(id: "clean.brew", on: true, text: "Old Homebrew versions and downloads"),
        Task(id: "clean.npm", on: true, text: "npm cache garbage (npm cache verify)"),
        Task(id: "clean.yarn", on: true, text: "Yarn cache"),
        Task(id: "clean.pnpm", on: true, text: "pnpm store: unreferenced packages"),
        Task(id: "clean.pip", on: true, text: "pip cache"),
        Task(id: "clean.poetry", on: true, text: "Poetry cache and downloads; its virtualenvs stay"),
        Task(id: "clean.uv", on: true, text: "uv cache: unused entries"),
        Task(id: "clean.go", on: true, text: "Go build cache"),
        Task(id: "clean.go_mod", on: true, text: "Go module cache (standard); go downloads the modules again"),
        Task(id: "clean.bun", on: true, text: "Bun install cache"),
        Task(id: "clean.deno", on: true, text: "Deno cache; localStorage and Deno KV data stay"),
        Task(id: "clean.logs", on: true, text: "Logs and crash reports older than 30 days, also npm and Gradle daemon logs"),
        Task(id: "clean.quicklook", on: true, text: "Quick Look thumbnail cache"),
        Task(id: "clean.reports", on: true, text: "Old macup reports (keep_reports_days, keep_reports), on every run; its history and leftover temp files are trimmed too"),
        Task(id: "clean.gradle", on: true, text: "Gradle caches and old Gradle wrappers (standard)"),
        Task(id: "clean.android", on: true, text: "Android and Android Studio caches (standard); SDK, emulators and keys stay"),
        Task(id: "clean.maven", on: true, text: "Maven repository ~/.m2/repository (standard); settings.xml stays"),
        Task(id: "clean.cargo", on: true, text: "Cargo registry and git downloads (standard, skipped while cargo runs)"),
        Task(id: "clean.jetbrains", on: true, text: "JetBrains IDE caches (standard, skipped while open)"),
        Task(id: "clean.docker", on: true, text: "Docker build cache and dangling images (standard); never volumes"),
        Task(id: "clean.docker_images", on: false, text: "Docker images no container uses (only when you pick them)"),
        Task(id: "clean.docker_containers", on: false, text: "Stopped Docker containers (only when you pick them)"),
        Task(id: "clean.old_versions", on: true, text: "Older patch versions in nvm, fnm, Volta, rbenv, pyenv, mise, asdf (standard); pinned ones stay"),
        Task(id: "clean.playwright", on: true, text: "Old Playwright, Puppeteer and Cypress builds (standard); the newest of each stays"),
        Task(id: "clean.profiles", on: true, text: "Expired provisioning profiles"),
        Task(id: "clean.ai_tools", on: true, text: "Leftovers of AI coding tools: Codex temporary files, backups and unfinished downloads, old Grok and Antigravity CLI versions, edit backups of deleted Claude Code sessions; chat history is never touched"),
        Task(id: "clean.editor_workspaces", on: true, text: "Data VS Code, Cursor and similar editors keep for a workspace whose folder is gone, AI chats included (only when you pick it, to the Trash)"),
        Task(id: "clean.editors", on: true, text: "Caches of Electron apps: VS Code, Cursor, Claude, Slack, Discord and any other found by its folder layout (skipped while open)"),
        Task(id: "clean.browsers", on: true, text: "Browser caches: Chrome, Arc, Edge, Brave, Firefox and any other Chromium or Firefox-based browser (aggressive, skipped while open)"),
        Task(id: "clean.app_caches", on: false, text: "Other big folders in ~/Library/Caches (aggressive, only when you pick them)"),
        Task(id: "clean.stale_node_modules", on: false, text: "node_modules in projects untouched for stale_project_days (opt-in)"),
        Task(id: "clean.stale_artifacts", on: false, text: "Build folders in projects untouched for stale_project_days: Pods, .build, .dart_tool, .next, target, build (opt-in)"),
        Task(id: "clean.brew_autoremove", on: false, text: "Homebrew packages installed only as dependencies that nothing needs any more (only when you pick them)"),
        Task(id: "clean.trash", on: false, text: "Empty the Trash (opt-in)"),
        Task(id: "clean.orphan_agents", on: false, text: "Background programs of deleted apps and their folders (only when you pick them)"),
        Task(id: "clean.orphan_data", on: false, text: "Data of deleted apps: settings, history, saved passwords (only when you pick them)"),
        Task(id: "clean.dev_containers", on: false, text: "Containers in ~/Library/Containers named by dev_container_prefixes whose app is gone (only when you pick them)"),
    ]

    private static let byId: [String: Task] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    public static func task(_ id: String) -> Task? { byId[id] }

    /// The ids in a comma list that are neither a task nor a group (`unknown_tasks`), joined by ", ".
    /// An id is looked up the way `awk -v id=…` hands it over: with its backslash escapes read.
    public static func unknown(_ list: String) -> String {
        list.unicodeScalars.split(whereSeparator: { $0 == "," || $0 == "\n" }).map { String($0) }.filter { id in
            !["check.*", "update.*", "clean.*"].contains(id) && byId[Awk.unescape(id)] == nil
        }.joined(separator: ", ")
    }
}

/// Which tasks a run does: 2.9's core.sh's `task_allowed` and `task`, from the config and the command line.
public struct Selection {
    public let settings: Settings

    public init(_ settings: Settings) { self.settings = settings }

    /// Not skipped by the config or --skip, and in --only when there is one. A group is written "check.*".
    public func allowed(_ id: String) -> Bool {
        let grp = String(id.prefix(while: { $0 != "." }))
        if !settings.only.isEmpty {
            let only = ",\(settings.only),"
            guard only.contains(",\(id),") || only.contains(",\(grp).*,") else { return false }
        }
        return !(settings.skip.contains(",\(id),") || settings.skip.contains(",\(grp).*,"))
    }

    /// Allowed, and an opt-in task only when enabled (by its id: `enable` takes no groups).
    public func runs(_ id: String) -> Bool {
        guard allowed(id) else { return false }
        if Tasks.task(id)?.on == false { return settings.enable.contains(",\(id),") }
        return true
    }

    /// The tasks a run would do, in table order.
    public var selected: [String] { Tasks.all.map(\.id).filter(runs) }
}

import Darwin
import Foundation

/// cleaners.sh up to `leftovers_cands`: every clean.* task registers what it found, in the order bash registers it.
enum Cleaners {
    static func register(_ run: Run) {
        let home = run.env.home, dev = run.env.dev, paths = run.env.paths
        // the slow measurements start at once and run side by side; ~/Library/Caches is one walk that sizes each folder in it too
        let sizes = run.arguments.dry && run.task("check.sizes")
        if run.taskAllowed("clean.app_caches") || sizes { run.measure.start(home + "/Library/Caches", eachFolder: true) }
        if sizes {
            run.measure.start(dev + "/CoreSimulator/Devices")
            run.measure.start(dev + "/Xcode/Archives")
        }
        let brewPreview = startBrewPreview(run)
        let folders = CacheTables.folders.filter { $0.tool.isEmpty || run.shell.have($0.tool) }
        for row in folders where run.taskAllowed(row.task) { run.measure.start(paths.expand(row.folder)) }
        let needCover = ["clean.app_caches", "clean.editors", "clean.browsers"].contains(where: run.taskAllowed)
        // one line per cache, read back as bash reads it: a tool that prints more than one line gives more lines
        var toolCaches = ""
        for row in CacheTables.toolCaches where run.shell.have(row.tool) && (run.taskAllowed(row.task) || needCover) {
            let folder = toolFolder(run, row.folder)
            guard !folder.isEmpty else { continue }
            if run.taskAllowed(row.task) { run.measure.start(folder) }
            toolCaches += "\(row.task)|\(row.level)|\(row.label)|\(row.key)|\(folder)\n"
        }
        for row in folders {
            Cleanup.registerFolder(run, task: row.task, level: row.level, label: row.label, path: paths.expand(row.folder), busy: row.busy)
        }
        // the folders of skipped tools are still covered: the scans of ~/Library/Caches below must not list them as other caches
        for line in Bash.lines(toolCaches) {
            let fields = read(line, "|", 5)
            guard !fields[0].isEmpty else { continue }
            run.candidates.cover(fields[4])
            measureCommand(run, fields[0], level: Int(fields[1]) ?? 1, fields[2], fields[4], fields[3])
        }
        run.candidates.cover(home + "/.npm")
        deno(run)
        for folder in Names.glob(dev + "/Xcode", "*DeviceSupport") where Run.isDirectory(folder) {
            cleanOld(run, "clean.device_support", base(folder), folder, run.settings.deviceSupportDays)
        }
        simulators(run)
        cleanOld(run, "clean.device_logs", "iOS device logs", dev + "/Xcode/iOS Device Logs", 90, type: "f")
        unavailableSimulators(run)
        brew(run, brewPreview)
        logs(run)
        run.register(task: "clean.quicklook", level: 1, label: translate(run, "Quick Look cache"), kb: 0, kind: .cmd, paths: "quicklook")
        staleBuildFolders(run)
        profiles(run)
        trash(run)
        Leftovers.registerDevContainers(run)
        buildCaches(run)
        docker(run)
        brewAutoremove(run)
        oldVersions(run)
        playwright(run)
        aiTools(run)
        editorWorkspaces(run)
        editors(run)
        browsers(run)
        layoutCaches(run)
        appCaches(run)
    }

    /// tool_dir: @name asks the tool where its cache is.
    static func toolFolder(_ run: Run, _ folder: String) -> String {
        switch folder {
        case "@pnpm": Checks.output(run, ["pnpm", "store", "path"])
        case "@uv": Checks.output(run, ["uv", "cache", "dir"])
        case "@go": Checks.output(run, ["go", "env", "GOCACHE"])
        case "@gomod": Checks.output(run, ["go", "env", "GOMODCACHE"])
        default: run.env.paths.expand(folder)
        }
    }

    /// Deno keeps localStorage and the databases of Deno.openKv() in location_data, next to its caches: that folder stays.
    static func deno(_ run: Run) {
        let deno = run.env.home + "/Library/Caches/deno"
        guard realFolder(deno) else { return }
        if run.taskAllowed("clean.deno") {
            let entries = find(run, [deno, "-mindepth", "1", "-maxdepth", "1", "!", "-name", "location_data"])
            let size = run.kbl(entries)
            if size >= 5120 {
                run.register(task: "clean.deno", level: 1, label: translate(run, "Deno cache"), kb: size, kind: .rm, paths: entries,
                             proc: Cleanup.busyPattern("deno"), keySource: "deno")
            }
        }
        run.candidates.cover(deno + "/location_data")
    }

    /// Android, Gradle, Maven: downloaded again by the next build. Only these subfolders: gradle.properties, settings.xml,
    /// keystores and emulators sit next to them and are never touched.
    static func buildCaches(_ run: Run) {
        let home = run.env.home
        cleanOld(run, "clean.gradle", "Old Gradle wrappers", home + "/.gradle/wrapper/dists", 30, level: 2)
        for folder in Names.glob(home + "/Library/Caches/Google", "AndroidStudio*") where Run.isDirectory(folder) {
            Cleanup.registerFolder(run, task: "clean.android", level: 2, label: format(run, "Android Studio cache (%s)", base(folder)), path: folder,
                                   busy: "/Android Studio.app/Contents/")
        }
        jetbrains(run)
        guard run.taskAllowed("clean.maven") else { return }
        // `mvn install` puts your own builds (often SNAPSHOTs) here; those exist nowhere else
        let repository = home + "/.m2/repository"
        let own = !find(run, [repository, "-name", "maven-metadata-local.xml", "-print", "-quit"]).isEmpty
        let before = run.candidates.list.count
        Cleanup.registerFolder(run, task: "clean.maven", level: 2, label: own ? "Maven repository (has your own mvn install builds)" : "Maven repository",
                               path: repository, busy: "maven")
        if own, run.candidates.list.count > before { run.candidates.list[before].auto = false }
    }

    /// Other big folders in ~/Library/Caches (100 MB+), except macOS's own and what is already listed.
    static func appCaches(_ run: Run) {
        guard run.taskAllowed("clean.app_caches") else { return }
        let caches = run.env.home + "/Library/Caches"
        let covered = Bash.lines(run.candidates.covered)
        var found: [(size: Int64, path: String)] = []
        // `du -k -d 1` without its total, from the walk started at the beginning: sort -rn orders equal sizes by the whole line
        let listing = realFolder(caches)
            ? ((try? FileManager.default.contentsOfDirectory(atPath: caches)) ?? []).map { caches + "/" + $0 }.filter(realFolder)
                .map { "\(run.measure.get($0))\t\($0)\n" }.joined()
            : ""
        for line in Checks.sortedBySize(run, listing) {
            let fields = read(line, "\t", 2)
            guard let size = Int64(fields[0]), size >= 102_400 else { break }
            let path = fields[1], name = base(path)
            guard realFolder(path) else { continue }
            if Bash.starts(name, "com.apple.") || Bash.starts(name, "Adobe Camera Raw") || Bash.ends(name, ".ShipIt") { continue }
            if covered.contains(where: { same($0, path) || $0.utf8.firstRange(of: (path + "/").utf8) != nil }) { continue }
            // not a cache whatever the folder is called: Poetry keeps its virtualenvs in ~/Library/Caches/pypoetry
            if !find(run, [path, "-maxdepth", "3", "-name", "pyvenv.cfg", "-print", "-quit"]).isEmpty { continue }
            found.append((size, path))
        }
        for cache in found {
            run.register(task: "clean.app_caches", level: 3, label: format(run, "App cache: %s", base(cache.path)), kb: cache.size, kind: .empty, paths: cache.path)
        }
    }
}

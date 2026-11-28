import Foundation

/// Editors and Electron apps (ELECTRON_APPS), browsers (BROWSERS), and any other Chromium, Electron or Firefox cache found
/// by its layout.
extension Cleaners {
    /// dirs_in: the folders of the list that are there, in a base folder.
    static func foldersIn(_ base: String, _ names: [String]) -> [String] {
        names.filter { !$0.isEmpty }.map { base + "/" + $0 }.filter(realFolder)
    }

    static func editors(_ run: Run) {
        guard run.taskAllowed("clean.editors") else { return }
        for (folder, name) in CacheTables.electronApps {
            let support = run.env.home + "/Library/Application Support/" + folder
            let bases = [support, support + "/Default"] + Names.glob(support + "/Partitions", "*") + Names.glob(support + "/Default/Partitions", "*")
            let caches = bases.filter(realFolder).flatMap { foldersIn($0, CacheTables.electronCaches) }.joined(separator: "\n")
            guard !caches.isEmpty else { continue }
            let size = run.kbl(caches)
            if size < 5120 { continue }
            // Application Support/Codex belongs to ChatGPT.app, so the app name alone misses it
            run.register(task: "clean.editors", level: 1, label: format(run, "%s caches", name), kb: size, kind: .empty, paths: caches,
                         proc: "/\(name).app/Contents/|user-data-dir=\(support)( --|/|$)")
        }
    }

    /// Safari's cache needs Full Disk Access; skipped.
    static func browsers(_ run: Run) {
        guard run.taskAllowed("clean.browsers") else { return }
        for browser in CacheTables.browsers {
            let caches = foldersIn(run.env.home + "/Library/Caches", browser.folders).joined(separator: "\n")
            guard !caches.isEmpty else { continue }
            let size = run.kbl(caches)
            if size < 5120 { continue }
            run.register(task: "clean.browsers", level: 3, label: format(run, "%s cache", browser.name), kb: size, kind: .empty, paths: caches,
                         proc: "/\(browser.app).app/Contents/")
        }
    }

    /// In Application Support a cache folder (ELECTRON_CACHES) next to Chromium's own files; in ~/Library/Caches the name is
    /// enough (cache2 is Firefox's). A browser (History next to it) is aggressive, an app safe. Never inside an .app or an
    /// updater's folder: ShipIt and Sparkle keep downloaded updates there until they are installed. Skipped while any process
    /// has a file open in the app's folders; the tables still give the known names.
    static func layoutCaches(_ run: Run) {
        guard run.taskAllowed("clean.editors") || run.taskAllowed("clean.browsers") else { return }
        let home = run.env.home
        for group in layoutGroups(support: home + "/Library/Application Support", caches: home + "/Library/Caches", covered: run.candidates.covered) {
            let caches = group.paths.joined(separator: "\n"), opened = group.opened.joined(separator: "\n")
            let size = run.kbl(caches)
            if size < 5120 { continue }
            let browser = group.kind == "browser"
            let label = format(run, browser ? "%s cache" : "%s caches", group.name)
            if !run.registerMore(label: label, level: group.level, kb: size, paths: caches, open: opened) {
                run.register(task: browser ? "clean.browsers" : "clean.editors", level: group.level, label: label, kb: size, kind: .empty, paths: caches, open: opened)
            }
        }
    }

    struct LayoutGroup {
        let level: Int
        let kind: String
        let name: String
        let opened: [String]
        let paths: [String]
    }

    /// macup_helpers.py electron_cache_groups, as bash reads its lines back: by kind and name, folders sorted by code point.
    static func layoutGroups(support: String, caches: String, covered: String) -> [LayoutGroup] {
        let names = Set(CacheTables.electronCaches), coveredPaths = Bash.lines(covered).filter { !$0.isEmpty }
        let apps = CacheTables.electronApps, browserFolders = CacheTables.browsers.flatMap { browser in browser.folders.map { ($0, browser.name) } }
        func has(_ folder: String, _ name: String) -> Bool { exists(folder + "/" + name) }
        func chromium(_ folder: String) -> Bool {
            has(folder, "Local State") || (has(folder, "Preferences") && ["Cookies", "TransportSecurity", "Network Persistent State", "DIPS"].contains { has(folder, $0) })
        }
        var groups: [String: (kind: String, name: String, paths: Set<String>, opened: [String])] = [:]
        func record(_ root: String, _ path: String) {
            if coveredPaths.contains(where: { same($0, path) || Bash.starts(path, $0 + "/") }) { return }
            let top = after(root + "/", path).components(separatedBy: "/")[0]
            let profile = Measure.parent(path)
            let appProfile = root == support ? profile : support + after(caches, profile)
            var userData = appProfile
            while Bash.starts(userData, support + "/"), !has(userData, "Local State") { userData = Measure.parent(userData) }
            var key = Bash.starts(userData, support + "/") ? after(support + "/", userData) : top
            if key.hasSuffix("/User Data") { key = String(String.UnicodeScalarView(key.unicodeScalars.dropLast(10))) }
            let kind: String, name: String
            if let app = apps.last(where: { same($0.folder, top) }) {
                (kind, name) = ("app", app.app)
            } else {
                name = browserFolders.last { same($0.0, key) }?.1 ?? browserFolders.last { same($0.0, top) }?.1
                    ?? (key.filter { $0 == "/" }.count < 2 ? key.replacingOccurrences(of: "/", with: " ") : top)
                let browser = path.hasSuffix("/cache2") || has(appProfile, "History") || has(appProfile, "Default/History") || has(userData, "Default/History")
                kind = browser ? "browser" : "app"
            }
            let id = kind + "\u{1F}" + name
            if groups[id] == nil { groups[id] = (kind, name, [], [support + "/" + top, caches + "/" + top]) }
            groups[id]!.paths.insert(path)
        }
        for root in [support, caches] { walk(root, depth: 0, root: root, isCaches: root == caches, names: names, chromium: chromium, record: record) }
        return groups.values.sorted { left, right in
            left.kind != right.kind ? left.kind < right.kind : Names.codePointOrder(left.name, right.name)
        }.map { group in
            LayoutGroup(level: group.kind == "browser" ? 3 : 1, kind: group.kind, name: group.name, opened: Set(group.opened).sorted(by: Names.codePointOrder),
                        paths: group.paths.sorted(by: Names.codePointOrder))
        }
    }

    /// os.walk's top-down pass as electron_cache_groups prunes it: links, apps and updater folders are never entered,
    /// a cache folder is recorded instead of entered, and nothing deeper than five levels is looked at.
    private static func walk(_ folder: String, depth: Int, root: String, isCaches: Bool, names: Set<String>, chromium: (String) -> Bool,
                             record: (String, String) -> Void) {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: folder) else { return }
        var deeper: [String] = []
        for name in entries where Run.isDirectory(folder + "/" + name) {
            let path = folder + "/" + name
            if Run.isSymlink(path) || name.hasSuffix(".app") || name.hasSuffix(".ShipIt") || name == "org.sparkle-project.Sparkle" { continue }
            if depth == 0, Bash.starts(name, "com.apple.") || name == "macup" { continue }
            if names.contains(name) || (name == "cache2" && isCaches) {
                if depth > 0, isCaches || (name != "cache2" && chromium(folder)) { record(root, path) }
                continue
            }
            if depth < 5 { deeper.append(path) }
        }
        for path in deeper { walk(path, depth: depth + 1, root: root, isCaches: isCaches, names: names, chromium: chromium, record: record) }
    }
}

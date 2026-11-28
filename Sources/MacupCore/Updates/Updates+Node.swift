import Darwin
import Foundation

/// Claude Code with its plugins, npm globals and agent skills.
/// bash reads their JSON only `if have python3`; here it is read on every Mac (an intended difference).
extension Updates {
    static func claude(_ run: Run) {
        let out = run.out
        let before = field(run, ["claude", "--version"], 1)
        if run.updates {
            out.step("Claude Code")
            run.run(["claude", "update"])
        }
        let now = field(run, ["claude", "--version"], 1)
        run.versionLine("Claude Code", before, now)
        if !run.updates, run.shell.have("npm") {
            let latest = timedOutput(run, 30, ["npm", "view", "@anthropic-ai/claude-code", "version"]).text
            if Version.isNewer(latest, than: now) { out.info("%s: %s is on npm (fine if you're on the stable channel)", "Claude Code", latest) }
        }
        let installed = run.env.home + "/.claude/plugins/installed_plugins.json"
        let pluginsBefore = plugins(installed)
        if run.updates {
            out.step("Plugin marketplaces")
            if run.run(["claude", "plugin", "marketplace", "update"]) == 0 { out.ok("Plugin marketplaces refreshed") } else { out.err("Plugin marketplaces: refresh failed (see the report)") }
            // no -y: a plugin whose marketplace asks to run a command is left for you to confirm (see the report)
            for line in Bash.lines(pluginsBefore) {
                let name = read(line, 2)[0]
                guard !name.isEmpty else { continue }
                out.step("Plugin %s", name)
                _ = inHome(run, ["claude", "plugin", "update", "--scope", "user", name])
            }
        }
        let pluginsNow = plugins(installed)
        guard !pluginsNow.isEmpty else { return }
        for line in Bash.lines(pluginsNow) {
            let words = read(line, 2), name = words[0], version = words[1]
            guard !name.isEmpty else { continue }
            let old = secondField(of: name, in: pluginsBefore)
            if !old.isEmpty, old != version {
                out.ok("Plugin %s: %s → %s", name, old, version)
                run.doneUpdate("plugin %s %s → %s", name, old, version)
            } else {
                out.mdonly("\(name) \(version)")
            }
        }
        out.ok("Claude Code plugins: %s installed", String(Run.count(pluginsNow)))
    }

    /// macup_helpers.py `plugins`: installed_plugins.json → "name version" of each user-scope plugin, sorted by name.
    /// As there, an entry Python could not read ends the list.
    static func plugins(_ path: String) -> String {
        guard isFile(path), let root = JSONValue.parse(file: path), case .object = root, case .object(let all) = root["plugins"] ?? root else { return "" }
        var lines: [String] = []
        for (name, value) in all.sorted(by: { Names.codePointOrder($0.key, $1.key) }) {
            var entries = [value]
            if case .array(let items) = value { entries = items }
            let user = entries.first { entry in
                guard case .object = entry else { return false }
                return (entry["scope"] ?? .string("user")).string == "user"
            }
            guard let entry = user else { continue }
            var version = "?"
            if let given = entry["version"], given.isTruthy {
                version = given.pythonString
            } else if let sha = entry["gitCommitSha"], sha.isTruthy {
                guard let text = sha.string else { break }
                version = String(String.UnicodeScalarView(text.unicodeScalars.prefix(7)))
            }
            lines.append("\(name) \(version)")
        }
        return lines.joined(separator: "\n")
    }

    static func npm(_ run: Run) {
        let out = run.out
        out.step("npm globals")
        // skips npm-link'ed packages and anything whose versions don't look like registry versions
        let root = output(run, ["npm", "root", "-g"])
        let outdated = npmOutdated(timedOutput(run, 180, ["npm", "outdated", "-g", "--json"]).text, root: root)
        guard !outdated.isEmpty else { out.ok("npm globals: up to date"); return }
        if !run.updates { out.warn("npm globals: %s outdated", String(Run.count(outdated))) }
        for line in Bash.lines(outdated) {
            let words = read(line, 3), package = words[0], current = words[1], latest = words[2]
            guard !package.isEmpty else { continue }
            if run.updates {
                out.step("npm %s", package)
                if run.run(["npm", "install", "-g", "\(package)@\(latest)"]) == 0 {
                    out.ok("%s: %s → %s", package, current, latest)
                    run.updated.append("\(package) \(current) → \(latest)")
                } else {
                    out.err("%s: update failed (see the report)", package)
                }
            } else {
                out.sub("\(package): \(current) → \(latest)")
            }
        }
    }

    /// macup_helpers.py `npm-outdated`: `npm outdated -g --json` → "package current latest" lines, in the order npm gave.
    static func npmOutdated(_ json: String, root: String) -> String {
        guard case .object(let packages) = JSONValue.parse(Data(json.utf8)) ?? .object([]) else { return "" }
        var lines: [String] = []
        for (package, info) in packages {
            guard case .object = info else { break }
            let current = (info["current"] ?? .string("")).pythonString, latest = (info["latest"] ?? .string("")).pythonString
            let path = package.hasPrefix("/") || root.isEmpty ? package : root.hasSuffix("/") ? root + package : root + "/" + package   // os.path.join
            if Run.isSymlink(path) || !isRegistryVersion(current) || !isRegistryVersion(latest) || current == latest { continue }
            lines.append("\(package) \(current) \(latest)")
        }
        return lines.joined(separator: "\n")
    }

    /// `^[0-9]+\.[0-9]+\.[0-9]+`
    private static func isRegistryVersion(_ text: String) -> Bool {
        var scalars = Substring(text).unicodeScalars
        for part in 0..<3 {
            if part > 0 { guard scalars.first == "." else { return false }; scalars.removeFirst() }
            let digits = scalars.prefix(while: { ("0"..."9").contains($0) }).count
            guard digits > 0 else { return false }
            scalars.removeFirst(digits)
        }
        return true
    }

    static func skills(_ run: Run, _ lock: String) {
        let out = run.out
        let before = skillHashes(lock)
        out.step("Agent skills")
        // -g: the global skills in ~/.agents, wherever macup is started from
        guard inHome(run, ["env", "CI=1", "npx", "-y", "skills", "update", "-g"]) == 0 else {
            out.err("Agent skills: update failed (see the report)")
            return
        }
        let now = skillHashes(lock)
        var changed = 0
        for line in Bash.lines(now) {
            let words = read(line, 2), name = words[0]
            guard !name.isEmpty else { continue }
            if secondField(of: name, in: before) != words[1] {
                changed += 1
                run.doneUpdate("skill %s", name)
            }
        }
        out.ok("Agent skills: %s installed, %s updated", String(Run.count(now)), String(changed))
    }

    /// macup_helpers.py `skills`: ~/.agents/.skill-lock.json → "name hash" lines, sorted by name.
    static func skillHashes(_ path: String) -> String {
        guard let root = JSONValue.parse(file: path), case .object = root, case .object(let skills) = root["skills"] ?? .object([]) else { return "" }
        var lines: [String] = []
        for (name, value) in skills.sorted(by: { Names.codePointOrder($0.key, $1.key) }) {
            guard case .object = value else { break }
            guard let hash = (value["skillFolderHash"] ?? .string("")).string else { break }
            lines.append("\(name) \(String(String.UnicodeScalarView(hash.unicodeScalars.prefix(7))))")
        }
        return lines.joined(separator: "\n")
    }

    /// npm and npx are node scripts: with node unlinked (keg-only node@24) they stay on PATH but cannot run.
    static func nodeOK(_ run: Run, _ label: String) -> Bool {
        if run.shell.have("node") { return true }
        let name = run.out.i18n.translate(label), fix = linkFix(run, "node")
        if fix.isEmpty { run.out.warn("%s: skipped, node is not on PATH", name) } else { run.out.warn("%s: skipped, node is not on PATH — run: %s", name, fix) }
        return false
    }

    /// core.sh `link_fix`: the brew link that puts an interpreter back on PATH; nothing when no formula has it.
    static func linkFix(_ run: Run, _ name: String) -> String {
        guard !run.shell.have(name) else { return "" }   // a dead venv interpreter named python3: brew's is linked, a link fixes nothing
        var versioned: [String] = []
        for prefix in [Env.nonEmpty(run.env.vars, "HOMEBREW_PREFIX"), "/opt/homebrew", "/usr/local"].compactMap({ $0 }) {
            if access("\(prefix)/opt/\(name)/bin/\(name)", X_OK) == 0 { return "brew link --overwrite \(name)" }
            let entries = (try? FileManager.default.contentsOfDirectory(atPath: "\(prefix)/opt")) ?? []
            versioned += entries.filter { entry in
                var info = stat()
                return entry.hasPrefix(name + "@") && lstat("\(prefix)/opt/\(entry)/bin/\(name)", &info) == 0
            }
        }
        // --overwrite too: a leftover npm in the prefix blocks the link, and brew's own advice for that omits --force
        guard let newest = versioned.max(by: { versionOrder($0, $1) }) else { return "" }
        return "brew link --force --overwrite \(newest)"
    }

    /// `sort -t@ -k2 -V`: by the version after the "@", runs of digits compared as numbers.
    static func versionOrder(_ left: String, _ right: String) -> Bool {
        func key(_ text: String) -> String { text.split(separator: "@", maxSplits: 1).dropFirst().first.map(String.init) ?? "" }
        let leftKey = key(left), rightKey = key(right)
        if leftKey != rightKey { return leftKey.compare(rightKey, options: .numeric) == .orderedAscending }
        return Names.codePointOrder(left, right)
    }
}

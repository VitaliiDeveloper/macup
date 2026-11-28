import Foundation

/// Build folders of projects nobody touched, older patch versions of Node, Ruby and Python, old test browser builds.
extension Cleaners {
    static let artifactNames = ["node_modules", "Pods", ".build", ".dart_tool", ".next", "target", "build"]

    /// A folder counts only next to the file that makes it again (artifact_ok), never when git tracks files in it (a committed
    /// Pods), and never when it was built recently itself: someone still runs that project.
    static func staleBuildFolders(_ run: Run) {
        guard run.taskAllowed("clean.stale_node_modules") || run.taskAllowed("clean.stale_artifacts") else { return }
        run.out.step("Looking for stale build folders")
        let days = run.settings.staleProjectDays
        var modules = "", artifacts = ""
        for root in run.safePaths.projectRoots() {
            let found = Bash.lines(find(run, [root, "-maxdepth", "5", "-type", "d", "(", "-name", ".git"] + artifactNames.flatMap { ["-o", "-name", $0] }
                                              + [")", "-prune", "-print"])).filter { !$0.hasSuffix("/.git") }
            let real = found.filter { !$0.isEmpty && SafePaths.artifactOK($0) }
            for folder in found where !folder.isEmpty {
                let relative = after(root, folder)
                if Measure.parent(relative).contains("/.") || relative.hasSuffix("/lib/node_modules") { continue }   // hidden, or a global npm install
                guard SafePaths.artifactOK(folder) else { continue }
                // any depth (src/app/components/x.tsx), but never inside build folders, where an install touches every file;
                // a folder only named like one (build/ with source, no build.gradle) is looked into
                let project = Measure.parent(folder)
                var pruned = ["-name", ".git", "-o", "-path", folder]
                for other in real where other.utf8.starts(with: (project + "/").utf8) { pruned += ["-o", "-path", other] }
                if !find(run, [project, "("] + pruned + [")", "-prune", "-o", "-type", "f", "-mtime", "-\(days)", "-print", "-quit"]).isEmpty { continue }
                if !find(run, [folder, "-maxdepth", "2", "-mtime", "-\(days)", "-print", "-quit"]).isEmpty { continue }
                if base(folder) == "node_modules" {
                    modules += folder + "\n"
                } else {
                    guard run.shell.have("git"), !tracked(run, folder) else { continue }
                    artifacts += folder + "\n"
                }
            }
        }
        if !modules.isEmpty {
            run.register(task: "clean.stale_node_modules", level: 2,
                         label: format(run, "Stale node_modules (%s projects untouched for %s days; npm install brings them back)", String(Run.count(modules)), String(days)),
                         kb: run.kbl(modules), kind: .rm, paths: modules, keySource: "stale_nm")
        }
        guard !artifacts.isEmpty else { return }
        let count = Run.count(artifacts)
        var shown = commaList(Bash.lines(artifacts).prefix(4).filter { !$0.isEmpty }.map(run.env.paths.tildify))
        if count > 4 { shown += " +\(count - 4)" }
        run.register(task: "clean.stale_artifacts", level: 2,
                     label: format(run, "Stale build folders (%s, projects untouched for %s days; the next build makes them again): %s", String(count), String(days), shown),
                     kb: run.kbl(artifacts), kind: .rm, paths: artifacts, keySource: "stale_art")
    }

    /// Anything but "not a git repository" keeps the folder: tracked files, or a repository git refuses to read.
    static func tracked(_ run: Run, _ folder: String) -> Bool {
        let output = outputAndErrors(run, ["git", "-C", folder, "ls-files", "."]).output
        guard !output.isEmpty else { return false }
        var lines = Bash.lines(output)
        if output.hasSuffix("\n") { lines.removeLast() }
        return !(lines.first { !$0.contains("not a git repository") } ?? "").isEmpty
    }

    static let threeNumbers = try! NSRegularExpression(pattern: "[0-9]+\\.[0-9]+\\.[0-9]+")
    static let twoNumbersAlone = try! NSRegularExpression(pattern: "(^|[^0-9.])[0-9]+\\.[0-9]+([^0-9.]|$)")
    static let twoNumbers = try! NSRegularExpression(pattern: "[0-9]+\\.[0-9]+")
    static let versionFolder = try! NSRegularExpression(pattern: "^v?[0-9]+\\.[0-9]+\\.[0-9]+$")
    static let plainVersion = try! NSRegularExpression(pattern: "^[0-9]+\\.[0-9]+\\.[0-9]+$")
    static let buildFolder = try! NSRegularExpression(pattern: "^(.+)-([0-9][0-9.]*)$")

    /// Older patch versions of Node, Ruby, Python. The newest of each line stays, and so does every version named in a
    /// global setting or in a project's pin file (.nvmrc, .tool-versions, …).
    static func oldVersions(_ run: Run) {
        guard run.taskAllowed("clean.old_versions") else { return }
        let home = run.env.home, source = pinSources(run)
        // " a b  ": as bash builds them, so a version is looked up the same way
        let pins = " " + Set(matches(threeNumbers, in: source)).sorted().map { $0 + " " }.joined() + " "
        // a pin without the patch ("20.5" in an .nvmrc) means the newest installed 20.5.x
        let minorPins = " " + Set(matches(twoNumbers, in: matches(twoNumbersAlone, in: source).joined(separator: "\n"))).sorted().map { $0 + " " }.joined() + " "
        func versions(_ tool: String, _ manager: String, _ folder: String, _ series: Int) {
            let old = olderVersions(run, folder, series, pins: pins, minorPins: minorPins)
            guard !old.isEmpty else { return }
            let names = old.map { line -> String in
                guard let slash = line.unicodeScalars.lastIndex(of: "/") else { return line }
                return String(String.UnicodeScalarView(line.unicodeScalars[line.unicodeScalars.index(after: slash)...].drop { $0 == "v" }))
            }
            run.register(task: "clean.old_versions", level: 2, label: format(run, "Older %s versions (%s): %s", tool, manager, commaList(names)),
                         kb: run.kbl(old.joined(separator: "\n")), kind: .rm, paths: old.joined(separator: "\n"), keySource: "ver|\(folder)")
        }
        versions("Node.js", "nvm", home + "/.nvm/versions/node", 1)
        versions("Node.js", "fnm", home + "/.local/share/fnm/node-versions", 1)
        versions("Node.js", "fnm", home + "/.fnm/node-versions", 1)
        versions("Node.js", "Volta", home + "/.volta/tools/image/node", 1)
        versions("Ruby", "rbenv", home + "/.rbenv/versions", 2)
        versions("Python", "pyenv", home + "/.pyenv/versions", 2)
        for (installs, manager) in [(home + "/.local/share/mise/installs", "mise"), (home + "/.asdf/installs", "asdf")] {
            for tool in Names.glob(installs, "*") where Run.isDirectory(tool) {
                versions(base(tool), manager, tool, base(tool) == "node" ? 1 : 2)
            }
        }
    }

    /// Everything a version pin can be in, in the order bash reads it: only the numbers in it matter, and two files read
    /// one after the other can make one number together.
    static func pinSources(_ run: Run) -> String {
        let home = run.env.home
        func text(_ path: String) -> String { Bash.regularFileContents(path).map { String(decoding: $0, as: UTF8.self) } ?? "" }
        func found(_ arguments: [String]) -> [String] { Bash.lines(find(run, arguments)).filter { !$0.isEmpty } }
        var source = [".rbenv/version", ".pyenv/version", ".tool-versions", ".config/mise/config.toml"].map { text(home + "/" + $0) }.joined() + "\n"
        source += found([home + "/.nvm/alias", "-type", "f"]).map(text).joined()   // default → lts/iron → x.y.z
        // Volta's default Node; fnm's aliases and the version each open shell uses are links to the version folder
        source += text(home + "/.volta/tools/user/platform.json") + "\n"
        for link in [".local/share/fnm/aliases", ".fnm/aliases", ".local/state/fnm_multishells"].flatMap({ Names.glob(home + "/" + $0, "*") }) where Run.isSymlink(link) {
            source += ((try? FileManager.default.destinationOfSymbolicLink(atPath: link)) ?? "") + "\n"
        }
        // pipx, uv tools, poetry, pipenv, virtualenvwrapper, hatch
        source += found([".local/pipx/venvs", ".local/share/uv/tools", "Library/Caches/pypoetry/virtualenvs", ".local/share/virtualenvs", ".virtualenvs",
                         "Library/Application Support/hatch/env/virtual"].map { home + "/" + $0 } + ["-maxdepth", "3", "-name", "pyvenv.cfg"]).map(text).joined()
        let roots = run.safePaths.projectRoots()
        func projectFiles(_ test: [String]) -> [String] {
            Array(roots.flatMap { found([$0, "-maxdepth", "4", "(", "-name", "node_modules", "-o", "-name", ".git", ")", "-prune", "-o", "-type", "f"] + test + ["-print"]) }
                .prefix(2000))
        }
        source += projectFiles(["(", "-name", ".nvmrc", "-o", "-name", ".node-version", "-o", "-name", ".ruby-version", "-o", "-name", ".python-version",
                                "-o", "-name", ".tool-versions", "-o", "-name", "mise.toml", "-o", "-name", ".mise.toml", "-o", "-name", "pyvenv.cfg", ")"]).map(text).joined()
        // package.json: "volta": {"node": "20.5.0"} and "engines": {"node": "20.5.0"}; never its dependency versions
        let nodeKey = try! NSRegularExpression(pattern: "\"node\"[[:space:]]*:")
        for file in projectFiles(["-name", "package.json"]) {
            var lines = Bash.lines(text(file))
            if lines.last == "" { lines.removeLast() }
            source += lines.filter { !matches(nodeKey, in: $0).isEmpty }.map { $0 + "\n" }.joined()
        }
        return source
    }

    /// old_versions: the older patch versions in a manager's folder that nothing pins; series 1 is per major, 2 per major.minor.
    static func olderVersions(_ run: Run, _ folder: String, _ series: Int, pins: String, minorPins: String) -> [String] {
        let lines = Names.glob(folder, "*").filter(Run.isDirectory).map(base).filter { !matches(versionFolder, in: $0).isEmpty }.map { name -> String in
            let version = name.hasPrefix("v") ? String(name.dropFirst()) : name
            let parts = version.components(separatedBy: ".")
            return "\(series == 1 ? parts[0] : parts[0] + "." + parts[1]) \(version) \(name)"
        }
        return olderOfEachLine(run, lines).filter { name in
            if Run.isSymlink(folder + "/" + name) { return false }
            let version = name.hasPrefix("v") ? String(name.dropFirst()) : name
            if pins.contains(" \(version) ") { return false }
            var minor = version
            if let dot = minor.lastIndex(of: ".") { minor = String(minor[..<dot]) }
            if minorPins.contains(" \(minor) ") {
                let pattern = "^" + (minor.range(of: ".").map { minor.replacingCharacters(in: $0, with: "\\.") } ?? minor) + "\\.[0-9]+$"
                let expression = try? NSRegularExpression(pattern: pattern)
                let installed = Names.glob(folder, "*").map { base($0) }.map { $0.hasPrefix("v") ? String($0.dropFirst()) : $0 }
                    .filter { name in expression.map { !matches($0, in: name).isEmpty } ?? false }
                if Bash.lines(Bash.substitution(filter(run, ["sort", "-V"], installed.map { $0 + "\n" }.joined()))).last == version { return false }
            }
            // pyenv virtualenvs live inside
            if hasEntries(folder + "/" + name + "/envs") { return false }
            return true
        }.map { folder + "/" + $0 }
    }

    /// `[ -n "$(ls -A "$1" 2>/dev/null)" ]`: a folder with something in it, or anything else that is there.
    static func hasEntries(_ path: String) -> Bool {
        if Run.isDirectory(path) { return !((try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []).isEmpty }
        return Checks.exists(path)
    }

    /// `sort -k1,1 -k2,2V | awk '{if(p==$1) print last; p=$1; last=$3}'` on "line version name" rows: every name but the
    /// newest of its line. awk compares two numbers as numbers (3.1 and 3.10 are one line) and starts with p unset.
    static func olderOfEachLine(_ run: Run, _ rows: [String]) -> [String] {
        guard !rows.isEmpty else { return [] }
        var previous: String?, last = "", older: [String] = []
        for row in Bash.lines(Bash.substitution(filter(run, ["sort", "-k1,1", "-k2,2V"], rows.map { $0 + "\n" }.joined()))) {
            let first = Awk.field(row, 1)
            let equal: Bool
            if let previous {
                equal = Awk.isNumber(previous) && Awk.isNumber(first) ? Awk.number(previous) == Awk.number(first) : same(previous, first)
            } else {
                equal = Awk.isNumber(first) ? Awk.number(first) == 0 : first.isEmpty
            }
            if equal { older.append(last) }
            previous = first
            last = Awk.field(row, 3)
        }
        return older
    }

    /// Old browser builds left by Playwright and Puppeteer, and Cypress versions (about 600 MB each); the newest of each stays.
    static func playwright(_ run: Run) {
        guard run.taskAllowed("clean.playwright") else { return }
        let caches = run.env.home + "/Library/Caches", cypress = caches + "/Cypress"
        run.candidates.cover(caches + "/ms-playwright")   // browsers in use stay
        run.candidates.cover(caches + "/ms-playwright-go")
        var found = ""
        for folder in [caches + "/ms-playwright"] + Names.glob(run.env.home + "/.cache/puppeteer", "*") where Run.isDirectory(folder) {
            let rows = Names.glob(folder, "*").filter(Run.isDirectory).map(base).compactMap { name -> String? in
                let string = name as NSString
                guard let match = buildFolder.firstMatch(in: name, range: NSRange(location: 0, length: string.length)) else { return nil }
                return "\(string.substring(with: match.range(at: 1))) \(string.substring(with: match.range(at: 2))) \(name)"
            }
            found += prefixed(olderOfEachLine(run, rows), folder).joined(separator: "\n") + "\n"
        }
        run.candidates.cover(cypress)
        if realFolder(cypress) {
            let versions = Names.glob(cypress, "*").filter(realFolder).map(base).filter { !matches(plainVersion, in: $0).isEmpty }
            var sorted = Bash.lines(Bash.substitution(filter(run, ["sort", "-V"], versions.map { $0 + "\n" }.joined())))
            sorted.removeLast()
            found += prefixed(sorted, cypress).joined(separator: "\n") + "\n"
        }
        let builds = Bash.lines(found).filter { !$0.isEmpty }.joined(separator: "\n")
        guard !builds.isEmpty else { return }
        run.register(task: "clean.playwright", level: 2, label: format(run, "Old Playwright, Puppeteer and Cypress builds (%s)", String(Run.count(builds))),
                     kb: run.kbl(builds), kind: .rm, paths: builds, keySource: "browsers")
    }
}

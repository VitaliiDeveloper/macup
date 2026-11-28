import Foundation

/// `macup uninstall` (2.9's commands.sh `uninstall`, `sched_off`): macup, older copies, settings, history, reports, the schedule,
/// the installer's PATH line, leftover temp files.
enum Uninstall {
    static func run(_ context: OneOff.Context, selfPath: String) {
        let env = context.env, i18n = context.i18n, out = context.out, paths = env.paths
        let brewPrefix = SelfPath.brewPrefix(selfPath)
        let target = SelfPath.isBuildOutput(selfPath) ? "" : selfPath
        var programs: [String] = []
        for file in [target, "\(env.home)/.local/bin/macup", "\(env.home)/.npm-global/bin/macup", "/usr/local/bin/macup", "/opt/homebrew/bin/macup"]
        where !file.isEmpty && Files.isRegular(file) && SelfPath.brewPrefix(file).isEmpty && SelfPath.isMacup(file) && !programs.contains(file) {
            programs.append(file)
        }
        let dirs = [env.confDir, env.stateDir, env.cacheDir, env.logDir].filter(Run.isDirectory)
        var pathLines: [(rc: String, line: Data)] = [], kept: [String] = [], binDirs = programs.map(SelfPath.dirname)
        for rc in ["\(env.home)/.zshrc", "\(env.home)/.bash_profile"] {
            guard let line = installerLine(rc) else { continue }
            var dir = String(String(decoding: line, as: UTF8.self).dropFirst(13))
            if dir.hasSuffix(":$PATH\"") { dir = String(dir.dropLast(7)) }
            if let home = dir.range(of: "$HOME") { dir.replaceSubrange(home, with: env.home) }
            binDirs.append(dir)
            // the line also serves whatever else lives in that folder
            let others = neighbours(dir)
            if others.isEmpty { pathLines.append((rc, line)) }
            else { kept.append(i18n.format("Kept: the PATH line in %s, because %s also has %s", paths.tildify(rc), paths.tildify(dir), others)) }
        }
        var temporary = temporaryFiles(env.tmpDir)
        for path in binDirs.flatMap({ ownLeftovers($0) }) where !temporary.contains(path) { temporary.append(path) }
        let schedule = Files.isRegular(env.schedPlist)

        out.write(i18n.translate("macup uninstall removes:") + "\n")
        if !brewPrefix.isEmpty { out.write("  · brew uninstall macup\n") }
        for file in programs { out.write("  · \(paths.tildify(file))\n") }
        for dir in dirs { out.write("  · \(paths.tildify(dir))  \(Size.hum(Size.kb(dir, shell: context.shell)))\n") }
        for entry in pathLines { out.write("  · " + i18n.format("the PATH line in %s", paths.tildify(entry.rc)) + "\n") }
        if !temporary.isEmpty { out.write("  · " + i18n.format("temporary files of interrupted runs: %s", temporary.count) + "\n") }
        if schedule { out.write("  · " + i18n.format("the schedule (%s)", paths.tildify(env.schedPlist)) + "\n") }
        for line in kept { out.write("  \(line)\n") }
        if brewPrefix.isEmpty, programs.isEmpty, dirs.isEmpty, pathLines.isEmpty, temporary.isEmpty, !schedule {
            out.write(i18n.translate("Nothing to remove.") + "\n")
            return
        }
        if !context.arguments.yes, !Terminal.isYes(Terminal.ask(i18n.translate("Remove all of this? [y/N] "))) {
            out.write(i18n.translate("Nothing removed.") + "\n")
            return
        }

        // rm as a tool: it goes on past what it cannot remove and says why, as bash's did
        let remove = { (argv: [String], stderr: Shell.Out) in _ = context.shell.spawn(argv, stderr: stderr).map(Shell.wait) }
        if Files.isRegular(env.schedPlist) {
            Launchctl(env: env, shell: context.shell).unload()
            remove(["rm", "-f", env.schedPlist], .inherit)
        }
        for dir in dirs { remove(["rm", "-rf", dir], .inherit) }
        for entry in pathLines { removeInstallerLine(entry.rc, entry.line) }
        for file in temporary { remove(["rm", Run.isDirectory(file) ? "-rf" : "-f", file], .inherit) }
        for file in programs {
            remove(["rm", "-f", file], .null)
            if access(file, F_OK) == 0 {
                out.write(i18n.format("Couldn't remove %s, remove it yourself: sudo rm %s", paths.tildify(file), file) + "\n")
            }
        }
        if !brewPrefix.isEmpty {
            let brew = brewPrefix + "/bin/brew"
            if context.shell.spawn([brew, "uninstall", "macup"], stdout: .null, stderr: .null).map(Shell.wait) != 0 {
                out.write(i18n.translate("brew uninstall macup failed; run it yourself.") + "\n")
            }
            let owner = env.repo.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
            let tap = owner.lowercased() + "/macup"
            if Bash.lines(context.shell.capture([brew, "tap"]).output).contains(tap) { _ = context.shell.spawn([brew, "untap", tap], stdout: .null, stderr: .null).map(Shell.wait) }
        }
        out.write(i18n.translate("Removed.") + "\n")
    }

    /// The `export PATH="…"` line the installer put right after a "# macup" line; nil when there is none.
    private static func installerLine(_ rc: String) -> Data? {
        guard let data = FileManager.default.contents(atPath: rc) else { return nil }
        var previous = Data()
        for line in Files.records(data) {
            if previous == marker, line.starts(with: Data("export PATH=\"".utf8)) { return line }
            previous = line
        }
        return nil
    }

    private static let marker = Data("# macup".utf8)

    /// Up to three other names in the folder, as `"$dir"/* "$dir"/.[!.]*` lists them, joined with ", ".
    private static func neighbours(_ dir: String) -> String {
        let names = (Names.glob(dir, "*") + Names.glob(dir, ".[!.]*")).map { String($0.dropFirst(dir.count + 1)) }
        return names.filter { $0 != "macup" && ownLeftovers(dir, only: $0).isEmpty }.prefix(3).joined(separator: ",").replacingOccurrences(of: ",", with: ", ")
    }

    /// mktemp's six random letters and digits.
    private static func alnum(_ text: Substring) -> Bool {
        text.unicodeScalars.count == 6 && text.unicodeScalars.allSatisfy { $0.isASCII && ($0.properties.isAlphabetic || ("0"..."9").contains($0)) }
    }

    /// What a self-update or an install that was killed leaves next to the binary: a `.macup-update.XXXXXX` folder, a
    /// `.macup-install.XXXXXX` file and its `.tag`. They are macup's own, and keep no PATH line.
    private static func ownLeftovers(_ dir: String, only name: String? = nil) -> [String] {
        let names = name.map { [$0] } ?? (Names.glob(dir, ".macup-update.*") + Names.glob(dir, ".macup-install.*")).map { String($0.dropFirst(dir.count + 1)) }
        return names.filter { name in
            let path = "\(dir)/\(name)"
            if name.hasPrefix(".macup-update.") { return alnum(name.dropFirst(14)) && Run.isDirectory(path) && !Run.isSymlink(path) }
            guard name.hasPrefix(".macup-install.") else { return false }
            let rest = name.dropFirst(15)
            return (alnum(rest) || (rest.hasSuffix(".tag") && alnum(rest.dropLast(4)))) && Files.isRegular(path, followingLinks: false)
        }.map { "\(dir)/\($0)" }
    }

    private static func temporaryFiles(_ tmpDir: String) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: tmpDir)) ?? []
        return names.filter { name in
            guard name != "macup.sha256" else { return false }
            if name.hasPrefix("macup-lang.") { return name.unicodeScalars.count == 17 }
            guard name.hasPrefix("macup.") else { return false }
            let rest = name.dropFirst(6)
            return alnum(rest) || (rest.count >= 7 && alnum(rest.prefix(6)) && rest.dropFirst(6).hasPrefix("."))
        }.map { "\(tmpDir)/\($0)" }.filter { Files.isRegular($0, followingLinks: false) }
    }

    /// In place, so the file's permissions and a symlink to it stay.
    private static func removeInstallerLine(_ rc: String, _ line: Data) {
        guard let data = FileManager.default.contents(atPath: rc) else { return }
        // awk -v reads escapes in the line it is given
        let pathLine = line.contains(0x5C) ? Data(Awk.unescape(String(decoding: line, as: UTF8.self)).utf8) : line
        let lines = Files.records(data)
        var kept: [Data] = [], index = 0
        while index < lines.count {
            if lines[index] == marker, index + 1 < lines.count, lines[index + 1] == pathLine {
                if kept.last?.isEmpty == true { kept.removeLast() }
                index += 2
                continue
            }
            kept.append(lines[index])
            index += 1
        }
        guard let handle = FileHandle(forWritingAtPath: rc) else { return }
        defer { try? handle.close() }
        try? handle.truncate(atOffset: 0)
        try? handle.write(contentsOf: kept.reduce(Data()) { $0 + $1 + [0x0A] })
    }
}

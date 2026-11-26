import Foundation

/// `macup uninstall` (commands.sh `uninstall`, `sched_off`): macup, older copies, settings, history, reports, the schedule,
/// the installer's PATH line, leftover temp files.
enum Uninstall {
    static func run(_ context: OneOff.Context, selfPath: String) {
        let env = context.env, i18n = context.i18n, out = context.out, paths = env.paths
        let brewPrefix = SelfPath.brewPrefix(selfPath)
        let target = SelfPath.isCheckout(SelfPath.dirname(selfPath)) ? "" : selfPath
        var programs: [String] = []
        for file in [target, "\(env.home)/.local/bin/macup", "\(env.home)/.npm-global/bin/macup", "/usr/local/bin/macup", "/opt/homebrew/bin/macup"]
        where !file.isEmpty && isFile(file) && SelfPath.brewPrefix(file).isEmpty && SelfPath.isMacup(file) && !programs.contains(file) {
            programs.append(file)
        }
        let dirs = [env.confDir, env.stateDir, env.cacheDir, env.logDir].filter(Run.isDirectory)
        var pathLines: [(rc: String, line: Data)] = [], kept: [String] = []
        for rc in ["\(env.home)/.zshrc", "\(env.home)/.bash_profile"] {
            guard let line = installerLine(rc) else { continue }
            var dir = String(String(decoding: line, as: UTF8.self).dropFirst(13))
            if dir.hasSuffix(":$PATH\"") { dir = String(dir.dropLast(7)) }
            if let home = dir.range(of: "$HOME") { dir.replaceSubrange(home, with: env.home) }
            // the line also serves whatever else lives in that folder
            let others = neighbours(dir)
            if others.isEmpty { pathLines.append((rc, line)) }
            else { kept.append(i18n.format("Kept: the PATH line in %s, because %s also has %s", paths.tildify(rc), paths.tildify(dir), others)) }
        }
        let temporary = temporaryFiles(env.tmpDir)
        let schedule = isFile(env.schedPlist)

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

        if isFile(env.schedPlist) {
            let quiet = { (argv: [String]) -> Int32 in context.shell.spawn(argv, stderr: .null).map(Shell.wait) ?? 127 }
            if quiet(["launchctl", "bootout", "gui/\(getuid())/\(Env.schedLabel)"]) != 0 { _ = quiet(["launchctl", "unload", env.schedPlist]) }
            unlink(env.schedPlist)
        }
        for dir in dirs { try? FileManager.default.removeItem(atPath: dir) }
        for entry in pathLines { removeInstallerLine(entry.rc, entry.line) }
        for file in temporary { unlink(file) }
        for file in programs {
            unlink(file)
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

    /// `[ -f ]`: a regular file, through symlinks.
    private static func isFile(_ path: String) -> Bool {
        var info = stat()
        return stat(path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFREG
    }

    /// The `export PATH="…"` line the installer put right after a "# macup" line; nil when there is none.
    private static func installerLine(_ rc: String) -> Data? {
        guard let data = FileManager.default.contents(atPath: rc) else { return nil }
        var previous = Data()
        for line in records(data) {
            if previous == marker, line.starts(with: Data("export PATH=\"".utf8)) { return line }
            previous = line
        }
        return nil
    }

    private static let marker = Data("# macup".utf8)

    /// Up to three other names in the folder, as `"$dir"/* "$dir"/.[!.]*` lists them, joined with ", ".
    private static func neighbours(_ dir: String) -> String {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
        let visible = names.filter { !$0.hasPrefix(".") }, hidden = names.filter { $0.hasPrefix(".") && !$0.hasPrefix("..") && $0.count > 1 }
        return (visible + hidden).filter { $0 != "macup" }.prefix(3).joined(separator: ",").replacingOccurrences(of: ",", with: ", ")
    }

    /// Temp files of interrupted runs: macup.XXXXXX, macup.XXXXXX.*, macup-lang.XXXXXX, regular files only.
    private static func temporaryFiles(_ tmpDir: String) -> [String] {
        func alnum(_ text: Substring) -> Bool { text.count == 6 && text.unicodeScalars.allSatisfy { $0.isASCII && ($0.properties.isAlphabetic || ("0"..."9").contains($0)) } }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: tmpDir)) ?? []
        return names.filter { name in
            guard name != "macup.sha256" else { return false }
            if name.hasPrefix("macup-lang.") { return name.dropFirst(11).count == 6 }
            guard name.hasPrefix("macup.") else { return false }
            let rest = name.dropFirst(6)
            return alnum(rest) || (rest.count >= 7 && alnum(rest.prefix(6)) && rest.dropFirst(6).hasPrefix("."))
        }.map { "\(tmpDir)/\($0)" }.filter { path in
            var info = stat()
            return lstat(path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFREG
        }
    }

    /// Takes out the "# macup" line and the PATH line after it, and the blank line the installer wrote before them.
    /// The file is rewritten in place, so its permissions and a symlink to it stay.
    private static func removeInstallerLine(_ rc: String, _ line: Data) {
        guard let data = FileManager.default.contents(atPath: rc) else { return }
        // awk -v reads escapes in the line it is given
        let pathLine = line.contains(0x5C) ? Data(Awk.unescape(String(decoding: line, as: UTF8.self)).utf8) : line
        let lines = records(data)
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

    /// The lines of a file as awk reads them: a last newline ends a record, it does not start one.
    private static func records(_ data: Data) -> [Data] {
        var lines = data.split(separator: 0x0A, omittingEmptySubsequences: false).map { Data($0) }
        if lines.last?.isEmpty == true { lines.removeLast() }
        return lines
    }
}

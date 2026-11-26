import Foundation

/// macup's reports: one file per run in the log folder (macup_<date>.md; .log files are left by versions before 2.9.0).
/// commands.sh `show_last`, `reports`, `report_mode`, `report_date`.
enum Reports {
    /// `macup last`: the newest report without its command output, which can be thousands of lines of brew.
    static func last(_ context: OneOff.Context) -> Data {
        let mds = markdown(context.env.logDir)
        guard let newest = mds.max(by: { older($0, than: $1) }) else {
            return Data((context.i18n.translate("No reports yet. Run: macup check") + "\n").utf8)
        }
        var lines = (FileManager.default.contents(atPath: newest) ?? Data()).split(separator: 0x0A, omittingEmptySubsequences: false)
        if lines.last?.isEmpty == true { lines.removeLast() }
        var kept = lines.count, cut = false
        for (index, line) in lines.enumerated() where line.starts(with: Data("## ".utf8)) && index + 2 < lines.count && lines[index + 2] == Data("~~~~".utf8) {
            kept = index; cut = true
            break
        }
        var out = Data()
        for line in lines.prefix(kept) { out += line + [0x0A] }
        if cut { out += Data((Awk.unescape(context.i18n.format("The command output is at the end of %s", context.env.paths.tildify(newest))) + "\n").utf8) }
        return out
    }

    /// `macup reports [clean|open]`; returns the exit status.
    static func run(_ context: OneOff.Context) -> Int32 {
        let env = context.env, i18n = context.i18n, out = context.out
        let dir = env.logDir, mds = markdown(dir).sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
        let kb = du(ownFiles(dir), context.shell)
        switch context.arguments.repArg {
        case "": break
        case "open":
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            _ = OneOff.runTool(["open", dir], context.shell)
            return 0
        case "clean":
            guard kb > 0 else { out.write(i18n.translate("Nothing to remove.") + "\n"); return 0 }
            out.write(i18n.format("Reports to remove: %s (%s) in %s", mds.count, Size.hum(kb), env.paths.tildify(dir)) + "\n")
            if !context.arguments.yes {
                let answer = Terminal.available ? Terminal.ask(i18n.translate("Remove them? [y/N] ")) : ""
                guard Terminal.isYes(answer) else { out.write(i18n.translate("Nothing removed.") + "\n"); return 0 }
            }
            for file in ownFiles(dir) { unlink(file) }
            out.write(i18n.translate("Removed.") + "\n")
            return 0
        default:
            out.write("macup reports [clean|open] [--yes] [--json]\n")
            return 2
        }
        if context.arguments.json {
            let reports = mds.map { file -> String in
                let mode = self.mode(file).map { "\"\($0)\"" } ?? "null"
                let size = du([file, String(file.dropLast(3)) + ".log"], context.shell)
                return "{\"file\":\"\(JSON.str(file))\",\"date\":\"\(date(file))\",\"mode\":\(mode),\"kb\":\(size)}"
            }
            out.write("{\"schema\":1,\"folder\":\"\(JSON.str(dir))\",\"count\":\(mds.count),\"kb\":\(kb),\"reports\":[" + reports.joined(separator: ",") + "]}\n")
            return 0
        }
        guard let oldest = mds.first, let newest = mds.last else { out.write(i18n.translate("No reports yet. Run: macup check") + "\n"); return 0 }
        out.write(i18n.format("Reports: %s · %s · %s", mds.count, Size.hum(kb), env.paths.tildify(dir)) + "\n")
        out.write(i18n.format("Oldest: %s · newest: %s", date(oldest), date(newest)) + "\n")
        let days = Config.num(context.config.value("keep_reports_days", "30"), "30"), runs = Config.num(context.config.value("keep_reports", "20"), "20")
        out.write(i18n.format("Kept: %s days, at most %s runs (keep_reports_days, keep_reports in %s)", days, runs, env.paths.tildify(env.conf)) + "\n")
        out.write(i18n.translate("Remove them all: macup reports clean · open the folder: macup reports open") + "\n")
        return 0
    }

    /// What `"$LOGDIR"/macup_*.md` matches, as paths.
    private static func markdown(_ dir: String) -> [String] {
        names(dir).filter { $0.hasPrefix("macup_") && $0.hasSuffix(".md") }.map { "\(dir)/\($0)" }
    }

    /// `find "$LOGDIR" -maxdepth 1 -type f \( -name 'macup_*.md' -o -name 'macup_*.log' \)`.
    private static func ownFiles(_ dir: String) -> [String] {
        names(dir).filter { $0.hasPrefix("macup_") && ($0.hasSuffix(".md") || $0.hasSuffix(".log")) }.map { "\(dir)/\($0)" }.filter { path in
            var info = stat()
            return lstat(path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFREG
        }
    }

    private static func names(_ dir: String) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).filter { !$0.hasPrefix(".") }
    }

    /// `ls -t` order: the newer file first, the same time by name.
    private static func older(_ left: String, than right: String) -> Bool {
        let leftTime = mtime(left), rightTime = mtime(right)
        if leftTime != rightTime { return leftTime < rightTime }
        return right.utf8.lexicographicallyPrecedes(left.utf8)
    }

    private static func mtime(_ path: String) -> Double {
        var info = stat()
        guard stat(path, &info) == 0 || lstat(path, &info) == 0 else { return 0 }
        return Double(info.st_mtimespec.tv_sec) + Double(info.st_mtimespec.tv_nsec) / 1e9
    }

    /// `du -k files… | awk '{s+=$1} END{print s+0}'`: du is the tool that knows the size on disk. Nothing to measure is 0.
    private static func du(_ files: [String], _ shell: Shell) -> Int64 {
        guard !files.isEmpty else { return 0 }
        let sum = Bash.lines(shell.capture(["du", "-k"] + files).output).reduce(0.0) { $0 + Awk.number(Awk.firstField($1)) }
        return Awk.int(sum)
    }

    /// `report_mode`: what line 3 says after "Mode: " (check, all, clean+deep, …), nil when it says nothing sed would match.
    static func mode(_ path: String) -> String? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        let lines = data.split(separator: 0x0A, omittingEmptySubsequences: false)
        guard lines.count > 2, let line = String(data: lines[2], encoding: .utf8), let colon = line.firstIndex(of: ":") else { return nil }
        let rest = line[line.index(after: colon)...]
        guard rest.hasPrefix(" ") else { return nil }
        let mode = rest.dropFirst().prefix { ("a"..."z").contains($0) || $0 == "+" }
        guard rest.dropFirst(1 + mode.count).hasPrefix(" · macup ") else { return nil }
        return String(mode)
    }

    /// `report_date`: macup_2026-11-01_10-00-00.md → 2026-11-01 10:00.
    static func date(_ path: String) -> String {
        var base = path.range(of: "/macup_", options: .backwards).map { String(path[$0.upperBound...]) } ?? path
        if let dot = base.lastIndex(of: ".") { base = String(base[..<dot]) }
        let day = base.firstIndex(of: "_").map { String(base[..<$0]) } ?? base
        let time = Bash.substitution(Bash.echo(base.firstIndex(of: "_").map { String(base[base.index(after: $0)...]) } ?? base))
        func cut(_ number: Int) -> String {
            let fields = time.split(separator: "-", omittingEmptySubsequences: false)
            guard fields.count > 1 else { return time }
            return number <= fields.count ? String(fields[number - 1]) : ""
        }
        return "\(day) \(cut(1)):\(cut(2))"
    }
}

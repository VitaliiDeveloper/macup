import Darwin
import Foundation

/// Only the empty kind and process checks so far: the router keeps runs that need rm, trash, cmd, lsof or the pick on bash.
public enum Cleanup {
    static func run(_ run: Run) {
        guard run.wantsCleanup else { return }
        Cleaners.register(run)
        Leftovers.registerCandidates(run)
        run.settle()
        if run.arguments.dry { markBusy(run) }
        for candidate in run.candidates.list where candidate.visible && !candidate.busy && !candidate.task.hasPrefix("clean.orphan_") {
            let size = candidate.kb ?? 0
            let inClean = candidate.auto && candidate.level <= run.settings.level
            // what goes to the Trash frees nothing until the Trash is emptied
            if inClean, candidate.kind == .trash { run.potTrash += size } else if inClean { run.potAuto += size } else { run.potMore += size }
        }
        run.potMore += Leftovers.total(run)   // counted together: their entries can share a folder
        if run.cleans {
            run.out.beginSection("Cleanup")
            for index in run.candidates.list.indices where run.candidates.list[index].auto && run.candidates.list[index].level <= run.settings.level {
                execute(run, index)
            }
            if !run.didClean { run.out.info("Nothing to clean at level %s", levelWord(run.settings.level, run.out.i18n)) }
        } else {
            run.out.beginSection("What can be cleaned")
            list(run)
        }
    }

    static func registerFolder(_ run: Run, task: String, level: Int, label: String, path: String, busy: String) {
        guard run.taskAllowed(task), Run.isDirectory(path), !Run.isSymlink(path), run.safePaths.allows(path) else { return }
        var size: Int64?   // nil: sized by settle, its du runs meanwhile
        if !run.measure.has(path) {
            size = run.kb(path)
            if size! < 5120 { return }
        }
        run.register(task: task, level: level, label: run.out.i18n.translate(label), kb: size, kind: .empty, paths: path, proc: busyPattern(busy))
    }

    static let xcodeBusy = "/Xcode.app/Contents/MacOS/Xcode|(^|/)xcodebuild( |$)"

    static func busyPattern(_ name: String) -> String {
        switch name {
        case "xcode": xcodeBusy
        case "cargo": "(^|/)(cargo|rustc)( |$)"
        case "poetry": "(^|/)poetry( |$)"
        case "maven": "plexus\\.classworlds|(^|/)mvnd?( |$)"
        case "deno": "(^|/)deno( |$)"
        case "npx": "/\\.npm/_npx/"   // MCP servers and CLIs started with npx run from there
        default: name
        }
    }

    static func running(_ run: Run, _ pattern: String) -> Bool {
        !pattern.isEmpty && run.shell.tl(0, ["pgrep", "-f", pattern], stdout: .null, stderr: .null) == 0
    }

    /// No candidate registers open folders until lsof is ported.
    static func openIn(_ folders: String) -> Bool {
        guard folders.isEmpty else { preconditionFailure("open_in (lsof) is not ported yet") }
        return false
    }

    static func markBusy(_ run: Run) {
        for index in run.candidates.list.indices {
            let candidate = run.candidates.list[index]
            run.candidates.list[index].busy = running(run, candidate.proc) || openIn(candidate.open)
        }
    }

    static func execute(_ run: Run, _ index: Int) {
        let candidate = run.candidates.list[index]
        let size = Size.hum(candidate.kb ?? 0)
        run.measure.forget()
        if running(run, candidate.proc) || openIn(candidate.open) {
            run.out.info("%s: %s — skipped while the app is open", candidate.label, size)
            run.skipped.append("\(candidate.label) (\(size))")
            return
        }
        run.out.step("%s", candidate.label)
        guard candidate.kind == .empty else { preconditionFailure("cleaning a \(candidate.kind) candidate is not ported yet") }
        let before = run.kbl(candidate.paths)
        for folder in Bash.lines(candidate.paths) where Run.isDirectory(folder) && !Run.isSymlink(folder) && run.safePaths.allows(folder) {
            for name in (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? [] { delete(run, "\(folder)/\(name)") }
        }
        let freed = max(0, before - run.kbl(candidate.paths))
        run.didClean = true
        run.freed += freed
        if freed >= 1024 { run.out.ok("%s: freed %s", candidate.label, Size.hum(freed)) } else { run.out.ok("%s: cleaned", candidate.label) }
    }

    /// A symlink is never followed or removed.
    static func delete(_ run: Run, _ path: String) {
        if Run.isSymlink(path) || access(path, F_OK) != 0 { return }
        guard run.safePaths.allows(path) else {
            run.log.append("macup refused to delete: \(path)\n")
            return
        }
        _ = run.shell.tl(0, ["rm", "-rf", path], stderr: .file(run.log.raw))
    }

    static func levelWord(_ level: Int, _ i18n: I18n) -> String {
        i18n.translate(level == 1 ? "safe" : level == 2 ? "standard" : "aggressive")
    }

    static func levelName(_ level: Int) -> String { level == 1 ? "safe" : level == 2 ? "standard" : "aggressive" }

    static func list(_ run: Run) {
        let out = run.out, colors = out.colors
        let leftovers = run.candidates.list.filter { $0.task.hasPrefix("clean.orphan_") && $0.visible }.count
        var number = 0, headed = false
        for candidate in run.candidates.list where candidate.visible {
            if candidate.task.hasPrefix("clean.orphan_"), !headed {
                headed = true
                out.flush()
                out.write("\n")
                let header = out.i18n.format("Leftovers of deleted apps — found %s, total %s", args: [String(leftovers), Size.hum(Leftovers.total(run))])
                out.write("\(colors.cl)  \(colors.bold)\(header)\(colors.reset)\n")
                out.md("")
                out.md("**\(header)**")
            }
            number += 1
            var tag = candidate.auto ? "" : " " + out.i18n.translate("(only if you pick it)")
            if candidate.busy { tag += " " + out.i18n.translate("(in use now — skipped until it is closed)") }
            out.flush()
            let color = candidate.level == 1 ? colors.green : candidate.level == 2 ? colors.yellow : colors.red
            let word = levelWord(candidate.level, out.i18n), size = Size.hum(candidate.kb ?? 0)
            out.write("\(colors.cl)  \(String(repeating: " ", count: max(0, 3 - String(number).count)))\(number)  \(color)\(Text.pad(word, 11))\(colors.reset) "
                      + "\(String(repeating: " ", count: max(0, 9 - size.utf8.count)))\(size)  \(candidate.label)\(colors.dim)\(tag)\(colors.reset)\n")
            out.md("- \(number). [\(word)] \(candidate.label): \(size)\(tag)")
            for line in Bash.lines(candidate.info) where !line.isEmpty {
                if line.hasPrefix("@") { out.md("    - `\(line.dropFirst())`") } else {
                    out.write("\(colors.cl)        \(colors.dim)\(line)\(colors.reset)\n")
                    out.md("    - \(line)")
                }
            }
        }
    }

    static func json(_ run: Run) -> String {
        guard run.arguments.dry else { return "[]" }
        return "[" + run.candidates.list.map { candidate in
            let inClean = candidate.auto && candidate.level <= run.settings.level
            return "{\"key\":\"\(candidate.key)\",\"task\":\"\(candidate.task)\",\"level\":\"\(levelName(candidate.level))\",\"kb\":\(candidate.kb ?? 0),"
                + "\"opt_in\":\(!candidate.auto),\"in_clean\":\(inClean),\"hidden\":\(!candidate.visible),\"busy\":\(candidate.busy),"
                + "\"text\":\"\(JSON.str(candidate.label))\"}"
        }.joined(separator: ",") + "]"
    }
}

extension Run {
    var safePaths: SafePaths { SafePaths(home: env.home, projectDirs: settings.projectDirs) }
}

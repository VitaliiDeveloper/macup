import Darwin
import Foundation

/// cleanup.sh: every cleaner registers a candidate (what, how big, how risky); then the chosen ones run (Execute.swift).
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
        if run.cleans, !run.arguments.pick.isEmpty {
            Pick.keys(run)
        } else if run.cleans {
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

    /// lsof_snap: the n lines (open files) of lsof for this user's processes, after a first line "lsof"; nil when lsof could
    /// not tell. macOS's own watchers (UserEventAgent, Spotlight, fseventsd) keep folders open whether or not their app runs:
    /// their files are left out.
    static func openFiles(_ shell: Shell) -> [String]? {
        let output = shell.capture(["lsof", "-n", "-P", "-Fcn", "-u", String(getuid())], stdin: .inherit).output
        guard !output.isEmpty else { return nil }
        var watcher = false
        return ["lsof"] + Bash.lines(output).filter { line in
            if line.hasPrefix("p") { watcher = false }
            if line.hasPrefix("c") { watcher = watchers.contains(String(line.dropFirst())) }
            return line.hasPrefix("n") && !watcher
        }
    }

    static let watchers: Set<String> = ["UserEventAgent", "mds", "mds_stores", "mdworker", "mdworker_shared", "fseventsd", "revisiond", "backupd", "quicklookd"]

    /// open_in: a process has a file open in one of the folders, or lsof cannot tell (a fresh look unless one is given).
    static func openIn(_ shell: Shell, _ folders: String, snapshot: [String]? = nil) -> Bool {
        guard !folders.isEmpty else { return false }
        guard let files = snapshot ?? openFiles(shell) else { return true }
        return Bash.lines(folders).contains { folder in
            !folder.isEmpty && files.contains { $0.utf8.firstRange(of: "n\(folder)/".utf8) != nil }
        }
    }

    /// What is in use right now is said in the list and left out of the totals; execute asks again before it cleans.
    /// lsof that cannot tell makes the cleanup skip a folder, but the list does not call it in use.
    static func markBusy(_ run: Run) {
        let files = run.candidates.list.contains { !$0.open.isEmpty } ? openFiles(run.shell) : nil
        for index in run.candidates.list.indices {
            let candidate = run.candidates.list[index]
            run.candidates.list[index].busy = running(run, candidate.proc) || files.map { openIn(run.shell, candidate.open, snapshot: $0) } ?? false
        }
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

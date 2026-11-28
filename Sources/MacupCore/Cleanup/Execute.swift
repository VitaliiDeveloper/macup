import Darwin
import Foundation

/// exec_cand: one candidate cleaned, after asking again whether its app is open. Every path is checked again right before
/// it goes: a symlink is never followed or removed, and nothing safe_path refuses is touched.
extension Cleanup {
    static func execute(_ run: Run, _ index: Int) {
        let candidate = run.candidates.list[index], out = run.out
        let size = Size.hum(candidate.kb ?? 0)
        run.measure.forget()
        if running(run, candidate.proc) || openIn(run.shell, candidate.open) {
            out.info("%s: %s — skipped while the app is open", candidate.label, size)
            run.skipped.append("\(candidate.label) (\(size))")
            return
        }
        out.step("%s", candidate.label)
        let paths = Bash.lines(candidate.paths)
        var before: Int64 = 0, after: Int64 = 0
        switch candidate.kind {
        case .empty:
            before = run.kbl(candidate.paths)
            for folder in paths where Run.isDirectory(folder) && !Run.isSymlink(folder) && run.safePaths.allows(folder) {
                // find … | while read -r: a name with a line break in it falls apart into paths that are not there or refused
                let entries = run.shell.capture(["find", folder, "-mindepth", "1", "-maxdepth", "1"]).output
                for entry in Bash.lines(entries) where !entry.isEmpty { _ = delete(run, entry) }
            }
            after = run.kbl(candidate.paths)
        case .rm, .trash:
            before = run.kbl(candidate.paths)
            var refused = false
            for path in paths where !path.isEmpty {
                let done = candidate.kind == .trash ? moveToTrash(run, path) : delete(run, path)
                if !done { refused = true }
            }
            after = run.kbl(candidate.paths)
            // never "cleaned" for something macup would not touch
            if refused, after >= before {
                out.err("%s: nothing removed, the path is outside what macup may delete (see the report)", candidate.label)
                return
            }
            // a removal that macOS refused (a locked file): a failure, never "cleaned"
            if paths.contains(where: { !$0.isEmpty && access($0, F_OK) == 0 && !Run.isSymlink($0) && run.safePaths.allows($0) }) {
                out.err("%s: could not remove all of it (see the report)", candidate.label)
                return
            }
        case .cmd:
            if !candidate.measureDir.isEmpty { before = run.kbl(candidate.measureDir) }
            let result = runKey(run, candidate.paths)
            if result.status == 2 { return }   // skipped; runKey said why
            guard result.status == 0 else {
                out.err("%s: failed (see the report)", candidate.label)
                return
            }
            if !candidate.measureDir.isEmpty { after = run.kbl(candidate.measureDir) }
            if let freed = result.freed { before = freed; after = 0 }
        }
        let freed = max(0, before - after)
        run.didClean = true
        // the Trash still holds it: nothing is freed until it is emptied
        if candidate.kind == .trash {
            out.ok("%s: moved %s to the Trash", candidate.label, Size.hum(freed))
            return
        }
        run.freed += freed
        if freed >= 1024 { out.ok("%s: freed %s", candidate.label, Size.hum(freed)) } else { out.ok("%s: cleaned", candidate.label) }
    }

    /// `del`: false only when safe_path refused the path (the report says so).
    static func delete(_ run: Run, _ path: String) -> Bool {
        if Run.isSymlink(path) || access(path, F_OK) != 0 { return true }
        guard run.safePaths.allows(path) else {
            run.log.append("macup refused to delete: \(path)\n")
            return false
        }
        _ = run.shell.tl(0, ["rm", "-rf", path], stderr: .file(run.log.raw))
        return true
    }

    /// `to_trash_path`: checked like `delete`, then moved into the Trash under a free name.
    static func moveToTrash(_ run: Run, _ path: String) -> Bool {
        if Run.isSymlink(path) || access(path, F_OK) != 0 { return true }
        guard run.safePaths.allows(path) else {
            run.log.append("macup refused to move: \(path)\n")
            return false
        }
        _ = run.shell.tl(0, ["mkdir", "-p", run.env.home + "/.Trash"])
        _ = run.shell.tl(0, ["mv", path, freeTrashName(run, trashName(path))], stderr: .file(run.log.raw))
        return true
    }

    /// `$(basename "$path")`.
    static func trashName(_ path: String) -> String {
        var scalars = Substring(path).unicodeScalars
        while scalars.count > 1, scalars.last == "/" { scalars.removeLast() }
        if let slash = scalars.lastIndex(of: "/"), scalars.count > 1 { scalars = scalars[scalars.index(after: slash)...] }
        return Bash.substitution(String(scalars))
    }

    /// `~/.Trash/<name>`, or `<name> 2`, `<name> 3`… while that is taken (a dangling link takes it too).
    static func freeTrashName(_ run: Run, _ name: String) -> String {
        var target = "\(run.env.home)/.Trash/\(name)", number = 2
        while access(target, F_OK) == 0 || Run.isSymlink(target) {
            target = "\(run.env.home)/.Trash/\(name) \(number)"
            number += 1
        }
        return target
    }
}

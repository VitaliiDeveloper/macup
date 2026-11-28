import Darwin
import Foundation

/// How a picked leftover leaves: into the Trash, never deleted, and only paths the scan found. Each is judged again right
/// before it moves: an app may have come back, or the program may be running.
extension Leftovers {
    /// `to_trash`: false when it was refused or did not move (the report says why).
    static func toTrash(_ run: Run, _ path: String, sudo: Bool = false) -> Bool {
        let home = run.env.home
        if path.isEmpty || Bash.holds(path, "/../") || Bash.ends(path, "/..") || Bash.holds(path, "/./") || Bash.ends(path, "/.") {
            run.log.append("macup refused to move: \(path)\n")
            return false
        }
        if Run.isSymlink(path) {
            run.log.append("macup refused a symlink: \(path)\n")
            return false
        }
        guard access(path, F_OK) == 0 else { return true }
        // grep -xF: each line of the path is a pattern of its own
        let allowed = Bash.lines(state(run).allow)
        guard Bash.lines(path).contains(where: { line in allowed.contains { same($0, line) } }) else {
            run.log.append("macup refused to move: \(path)\n")
            return false
        }
        _ = run.shell.tl(0, ["mkdir", "-p", home + "/.Trash"])
        let target = Cleanup.freeTrashName(run, Cleanup.trashName(path))
        if sudo {
            return run.shell.tl(0, ["sudo", "mv", path, target], stderr: .file(run.log.raw)) == 0
                && run.shell.tl(0, ["sudo", "chown", "-R", String(getuid()), target], stderr: .file(run.log.raw)) == 0
        }
        if run.shell.tl(0, ["mv", path, target], stderr: .file(run.log.raw)) == 0 { return true }
        // macOS keeps a container folder itself; what is inside can go
        guard Bash.starts(path, home + "/Library/Containers/") || Bash.starts(path, home + "/Library/Group Containers/"), Run.isDirectory(path) else { return false }
        if run.shell.tl(0, ["mkdir", "-p", target]) == 0 {
            _ = run.shell.tl(0, ["find", path, "-mindepth", "1", "-maxdepth", "1", "-exec", "mv", "{}", target + "/", ";"], stderr: .file(run.log.raw))
        }
        return isEmptyFolder(path)
    }

    /// A folder macup cannot read counts as not empty: 2.9 took it for empty, so a root-only vendor folder went to the Trash
    /// with other products' data in it.
    static func isEmptyFolder(_ path: String) -> Bool {
        (try? FileManager.default.contentsOfDirectory(atPath: path))?.isEmpty ?? false
    }

    /// `re_esc`: a path as a pgrep pattern that matches only itself.
    static func literalPattern(_ text: String) -> String {
        text.unicodeScalars.map { "[]\\.*^$+?(){}|/".unicodeScalars.contains($0) ? "\\\($0)" : String($0) }.joined()
    }

    /// `orph_still`.
    static func stillOrphaned(_ run: Run, _ orphan: Orphan) -> Bool {
        guard access(orphan.plist, F_OK) == 0 else { return false }
        if !orphan.program.isEmpty, Cleanup.running(run, literalPattern(orphan.program)) { return false }
        let state = state(run)
        switch orphan.reason {
        case .empty: return (plist(orphan.plist) as? [String: Any])?.isEmpty == true
        case .missing: return access(orphan.program, F_OK) != 0
        case .gone:
            if !state.rescanned {
                scanApps(run, state)
                state.rescanned = true
            }
            if teamInstalled(run, state, teamOf(run, orphan.program)) { return false }
            return !(associatedIDs(plist(orphan.plist)) + [orphan.label]).contains { !$0.isEmpty && vendorInstalled(state, vendorOf($0)) }
        case .broken: return false
        }
    }

    /// `run_orph`: the agent stopped, then its file, helper and folder to the Trash; `freed` is the folder's size.
    static func removeAgent(_ run: Run, _ index: Int) -> Cleanup.KeyResult {
        let state = state(run)
        // orph_still finds no file for an index the scan does not have, and names the item as bash names an empty one
        guard state.orphans.indices.contains(index) else {
            run.out.info("%s: still in use, skipped", " · " + run.out.i18n.translate("background program"))
            return (2, nil)
        }
        let orphan = state.orphans[index]
        guard stillOrphaned(run, orphan) else {
            run.out.info("%s: still in use, skipped", "\(orphan.name) · \(kind(run, orphan))")
            return (2, nil)
        }
        let target = "\(domain(orphan))/\(orphan.label)"
        if orphan.reason != .empty, Bash.lines(orphan.label).contains(where: isLabel),
           run.shell.tl(0, ["launchctl", "print", target], stdout: .null, stderr: .null) == 0 {
            _ = run.shell.tl(0, (orphan.system ? ["sudo"] : []) + ["launchctl", "bootout", target], stderr: .file(run.log.raw))
        }
        let folder = orphan.folder
        let size = folder.isEmpty ? 0 : run.kb(folder)
        guard toTrash(run, orphan.plist, sudo: orphan.system) else { return (1, nil) }
        let helperPath = helper(run, orphan)
        for path in [helperPath, folder] where !path.isEmpty {
            guard toTrash(run, path, sudo: orphan.system) else { return (1, nil) }
        }
        let parent = Measure.parent(folder)
        if !folder.isEmpty, Run.isDirectory(parent), isEmptyFolder(parent) { _ = toTrash(run, parent, sudo: orphan.system) }
        return (0, size)
    }

    private static func isLabel(_ line: String) -> Bool {
        !line.isEmpty && line.unicodeScalars.allSatisfy { ("A"..."Z").contains($0) || ("a"..."z").contains($0) || ("0"..."9").contains($0) || "._-".unicodeScalars.contains($0) }
    }

    /// `run_odata`: a vendor's data to the Trash, unless an app of the vendor is back or a file in it is open.
    static func removeData(_ run: Run, _ index: Int) -> Cleanup.KeyResult {
        let state = state(run)
        guard state.data.indices.contains(index) else { return (0, nil) }
        let data = state.data[index], label = "\(data.name) · \(run.out.i18n.translate("data of a deleted app"))"
        scanApps(run, state)
        if vendorInstalled(state, data.vendor) || Cleanup.openIn(run.shell, data.paths) {
            run.out.info("%s: still in use, skipped", label)
            return (2, nil)
        }
        let before = run.kbl(outer(data.paths))
        var moved = true
        for path in Bash.lines(data.paths) where !path.isEmpty {
            if !toTrash(run, path) { moved = false }
        }
        let freed = before - run.kbl(outer(data.paths))
        if !moved { run.out.warn("%s: some files could not be moved (see the report)", label) }
        return (0, freed)
    }

    /// `run_devc`: what is inside goes to ~/.Trash/<bundle id>, while it is still a dev container, no app has its id and
    /// nothing in it is open.
    static func removeContainer(_ run: Run, _ container: String) -> Cleanup.KeyResult {
        let name = basename(container)
        guard devContainer(run, container), Run.isDirectory(container), !Run.isSymlink(container) else {
            run.log.append("macup refused container: \(container)\n")
            return (1, nil)
        }
        if appFor(run, name) || Cleanup.openIn(run.shell, container) {
            run.out.info("%s: still in use, skipped", name)
            return (2, nil)
        }
        let size = run.kb(container), target = Cleanup.freeTrashName(run, name)
        guard run.shell.tl(0, ["mkdir", "-p", target]) == 0 else { return (1, nil) }
        var status: Int32 = 0
        for entry in ["*", ".[!.]*", "..?*"].flatMap({ Names.glob(container, $0) }) where basename(entry) != containerMarker {
            if run.shell.tl(0, ["mv", entry, target + "/"], stderr: .file(run.log.raw)) != 0 { status = 1 }
        }
        return (status, size - run.kb(container))
    }

    /// What macOS keeps in a container it made; an emptied container still has it.
    static let containerMarker = ".com.apple.containermanagerd.metadata.plist"
}

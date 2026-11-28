import Darwin
import Foundation

/// What is registered here is cleaned only when a person picks it, and then goes to the Trash (Moves.swift).
public enum Leftovers {
    static func registerCandidates(_ run: Run) {
        guard run.taskAllowed("clean.orphan_agents") || run.taskAllowed("clean.orphan_data") else { return }
        let state = state(run)
        scan(run, state)
        if run.taskAllowed("clean.orphan_agents") {
            for index in state.orphans.indices { registerAgent(run, state, index) }
        }
        if run.taskAllowed("clean.orphan_data") { registerData(run, state) }
    }

    private static func registerAgent(_ run: Run, _ state: State, _ index: Int) {
        let orphan = state.orphans[index]
        if orphan.system, !(state.interactive && systemOK(run, orphan)) { return }
        guard orphan.reason != .broken else { return }
        let folder = orphan.reason == .gone ? ownFolder(run, orphan.program) : ""   // a missing program proves nothing about its folder
        state.orphans[index].folder = folder
        state.allow += "\(orphan.plist)\n\(helper(run, orphan))\n"
        var size: Int64 = 0
        if !folder.isEmpty {
            state.allow += "\(folder)\n\(Measure.parent(folder))\n"
            size = run.kb(folder)
        }
        let paths = run.env.paths
        var info = about(run, state.orphans[index]) + ["@" + paths.tildify(orphan.plist)]
        if !folder.isEmpty { info.append("@" + paths.tildify(folder)) }
        run.register(task: "clean.orphan_agents", level: 3, label: "\(orphan.name) · \(kind(run, orphan))\(orphan.system ? " 🔑" : "")", kb: size,
                     kind: .cmd, paths: "orph:\(index)", info: info.joined(separator: "\n"), manual: true)
        let last = run.candidates.list.count - 1
        run.candidates.list[last].sudo = orphan.system
        run.candidates.list[last].leftoverPaths = orphan.plist + (folder.isEmpty ? "" : "\n" + folder)
    }

    static func total(_ run: Run) -> Int64 {
        let paths = run.candidates.list.filter { $0.task.hasPrefix("clean.orphan_") }.map { $0.leftoverPaths + "\n" }.joined()
        return run.kbl(outer(paths))
    }

    static func outer(_ paths: String) -> String {
        let sorted = Set(Bash.lines(paths).filter { !$0.isEmpty }).sorted { Array($0.utf8).lexicographicallyPrecedes(Array($1.utf8)) }
        var kept = Set<String>(), out: [String] = []
        for path in sorted {
            let fields = path.split(separator: "/", omittingEmptySubsequences: false)
            var ancestor = "", inside = false
            for field in fields.dropFirst().dropLast() {
                ancestor += "/\(field)"
                if kept.contains(ancestor) { inside = true; break }
            }
            if !inside { kept.insert(path); out.append(path) }
        }
        return out.joined(separator: "\n")
    }

    static func kind(_ run: Run, _ orphan: Orphan) -> String { run.out.i18n.translate(kindKey(orphan)) }

    private static func kindKey(_ orphan: Orphan) -> String {
        if orphan.reason == .empty { return "empty startup file" }
        if orphan.system { return "system service" }
        let text = lc("\(orphan.label) \(orphan.program)")
        return text.contains("update") || text.contains("keystone") ? "update program" : "background program"
    }

    static func about(_ run: Run, _ orphan: Orphan) -> [String] {
        let i18n = run.out.i18n
        var lines: [String] = []
        if orphan.reason == .empty { lines.append(i18n.translate("What: a startup file with nothing in it.")) }
        else if orphan.system { lines.append(i18n.translate("What: a service that starts for every user of this Mac.")) }
        else if kindKey(orphan) == "update program" {
            lines.append(i18n.translate(raw(plist(orphan.plist), "StartInterval") == "3600" ? "What: a background program that checked for updates every hour."
                                                                                              : "What: a background program that checks for updates."))
        } else { lines.append(i18n.translate("What: a background program that starts with your Mac.")) }
        switch orphan.reason {
        case .gone: lines.append(i18n.format("Why: no app from %s is installed anymore.", args: [orphan.name]))
        case .missing: lines.append(i18n.translate("Why: its program was deleted."))
        case .empty: lines.append(i18n.translate("Why: the file is empty and does nothing."))
        case .broken: break
        }
        lines.append(i18n.translate("Safe: yes, it goes to the Trash."))
        if orphan.system { lines.append(i18n.translate("Needs your Mac password (asked once for all such items).")) }
        return lines
    }

    static func ownFolder(_ run: Run, _ program: String) -> String {
        let home = run.env.home
        for base in ["\(home)/Library/Application Support", "\(run.env.sysLib)/Application Support", "\(home)/Library"] where Bash.starts(program, base + "/") {
            let parts = program.utf8.dropFirst(base.utf8.count + 1).split(separator: UInt8(ascii: "/"), maxSplits: 2, omittingEmptySubsequences: false)
            // right in the vendor folder: that folder may hold other data; "", "." and ".." would name another folder than the vendor's
            guard parts.count == 3, !parts.prefix(2).contains(where: { ["", ".", ".."].map { Array($0.utf8) }.contains(Array($0)) }) else { return "" }
            let vendorFolder = "\(base)/\(String(decoding: parts[0], as: UTF8.self))", folder = "\(vendorFolder)/\(String(decoding: parts[1], as: UTF8.self))"
            return Run.isDirectory(folder) && !Run.isSymlink(folder) && !Run.isSymlink(vendorFolder) ? folder : ""
        }
        return ""
    }

    static func domain(_ orphan: Orphan) -> String {
        Bash.holds(orphan.plist, "/LaunchDaemons/") ? "system" : "gui/\(getuid())"
    }

    static func helper(_ run: Run, _ orphan: Orphan) -> String {
        let path = "\(run.env.sysLib)/PrivilegedHelperTools/\(orphan.label)"
        return orphan.system && !orphan.label.isEmpty && isFile(path) && !Run.isSymlink(path) ? path : ""
    }

    static func sudoCommands(_ run: Run, _ orphan: Orphan) -> [String] {
        var lines: [String] = []
        if !orphan.label.isEmpty { lines.append("sudo launchctl bootout \(domain(orphan))/\(orphan.label)") }
        lines.append("sudo mv \"\(run.env.paths.tildify(orphan.plist))\" ~/.Trash/")
        for path in [helper(run, orphan), orphan.folder] where !path.isEmpty { lines.append("sudo mv \"\(path)\" ~/.Trash/") }
        return lines
    }

    /// `lo_sys_ok`: a system item is offered only on strong evidence: the program is gone, or its signing team owns no installed app.
    static func systemOK(_ run: Run, _ orphan: Orphan) -> Bool {
        orphan.reason == .missing || (orphan.reason == .gone && !teamOf(run, orphan.program).isEmpty)
    }

    static func startup(_ run: Run) {
        guard run.task("check.startup") else { return }
        let out = run.out
        out.beginSection("Startup items")
        let state = state(run)
        scan(run, state)
        let services = startupFiles(run).filter(isFile).map(plistName).filter { !$0.hasPrefix("com.apple.") }
        out.info("Third-party background services: %s (full list in the report)", String(services.filter { !$0.isEmpty }.count))
        for service in services where !service.isEmpty { out.mdonly(service) }
        var found = ""
        for orphan in state.orphans {
            let why: String
            switch orphan.reason {
            case .broken:
                out.info("%s cannot be read (not a valid plist)", run.env.paths.tildify(orphan.plist))
                continue
            case .gone: why = "app is not installed"
            case .missing: why = "its program is gone"
            case .empty: why = "empty file"
            }
            found += "\(orphan.name) · \(orphan.label.isEmpty ? plistName(orphan.plist) : orphan.label) — \(out.i18n.translate(why))\n"
            if orphan.system, !state.interactive || !systemOK(run, orphan) {
                found += sudoCommands(run, orphan).map { "    " + $0 }.joined(separator: "\n") + "\n"
            }
        }
        if !found.isEmpty {
            out.warn("Leftovers of deleted apps: %s (macup check lets you pick them)", String(Run.count(found)))
            run.lines(found)
        }
        out.info("Login items: System Settings → General → Login Items & Extensions")
    }
}

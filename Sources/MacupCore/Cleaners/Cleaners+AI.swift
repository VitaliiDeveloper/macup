import Darwin
import Foundation

/// AI tools: only leftovers and caches. Chat history, sessions, settings and databases are never touched.
extension Cleaners {
    /// Codex runs as the CLI and inside ChatGPT.app; Claude Code as the CLI and inside Claude.app.
    static let codexBusy = "(^|/)codex(\\.js)?( |$)|/(ChatGPT|Codex)\\.app/Contents/"
    static let claudeBusy = "(^|/)claude( |$)|/\\.local/share/claude/versions/|/Claude\\.app/Contents/"
    static let grokBusy = "(^|/)(grok|agent)( |$)|/\\.grok/downloads/"

    static func aiTools(_ run: Run) {
        guard run.taskAllowed("clean.ai_tools") else { return }
        let home = run.env.home, codex = home + "/.codex"
        func add(_ key: String, _ level: Int, _ label: String, _ found: String, _ kind: Candidate.Kind, _ busy: String = "") {
            guard !found.isEmpty else { return }
            run.register(task: "clean.ai_tools", level: level, label: label, kb: run.kbl(found), kind: kind, paths: found, proc: busy, keySource: key)
        }
        // each is a few KB, so they are worth it by number, not by size
        let clones = find(run, [codex + "/.tmp", "-mindepth", "1", "-maxdepth", "1", "-type", "d", "-name", "git-*", "-mtime", "+7"])
        if !clones.isEmpty, Run.count(clones) >= 50 || run.kbl(clones) >= 1024 {
            add("codex_tmp", 1, format(run, "Codex temporary git clones (%s, older than 7 days)", String(Run.count(clones))), clones, .rm, codexBusy)
        }
        add("codex_rt", 1, translate(run, "Unfinished Codex runtime downloads"),
            find(run, [home + "/.cache/codex-runtimes", "-mindepth", "1", "-maxdepth", "1", "-type", "d", "-name", "codex-runtime-install-*", "-mtime", "+1"]), .rm, codexBusy)
        // the old plugin set is kept aside while a new one moves in, and stays only after a crash or a failed rollback
        if Run.isDirectory(codex + "/.tmp/plugins") {
            add("codex_pbak", 1, translate(run, "Codex plugin backups left by an interrupted update"),
                find(run, [codex + "/.tmp", "-mindepth", "1", "-maxdepth", "1", "-type", "d", "-name", "plugins-backup-*", "-mtime", "+7"]), .trash, codexBusy)
        }
        // ChatGPT.app writes its state to a temporary file and renames it; one a week old was never renamed
        add("codex_gs", 1, translate(run, "Unfinished Codex state writes"),
            find(run, [codex, "-mindepth", "1", "-maxdepth", "1", "-type", "f", "-name", "..codex-global-state.json*.tmp-*", "-mtime", "+7"]), .trash, codexBusy)
        // the catalog is fetched again after 3 hours: one untouched for 30 days is for an account no longer used
        add("codex_cat", 2, translate(run, "Codex plugin catalogs of accounts unused for 30 days"),
            find(run, [codex + "/cache/remote_plugin_catalog", "-mindepth", "1", "-maxdepth", "1", "-type", "f", "-name", "*.json", "-mtime", "+30"]), .rm, codexBusy)
        // agy update keeps the replaced binary next to the new one
        add("agy_old", 1, translate(run, "Old Antigravity CLI versions left by its updates"),
            find(run, [home + "/.local/bin", "-maxdepth", "1", "-type", "f", "-name", "agy.*.old"]), .rm)
        // grok update downloads each version next to the last one and points ~/.grok/bin at the new one; an hour-old file is no download in progress
        let downloads = home + "/.grok/downloads"
        if realFolder(downloads), !Run.isSymlink(home + "/.grok") {
            let inUse = Names.glob(home + "/.grok/bin", "*").filter(Run.isSymlink)
                .map { base((try? FileManager.default.destinationOfSymbolicLink(atPath: $0)) ?? "") }.filter { !$0.isEmpty }.joined(separator: "\n")
            if !inUse.isEmpty {
                let files = Bash.lines(find(run, [downloads, "-mindepth", "1", "-maxdepth", "1", "-type", "f", "-name", "grok-*", "-mmin", "+60"])).filter { !$0.isEmpty }
                add("grok_old", 1, translate(run, "Old Grok CLI versions left by its updates"),
                    files.filter { !listed(base($0), in: inUse) }.joined(separator: "\n"), .rm, grokBusy)
            }
        }
        // rewind needs the session's transcript; without it in ~/.claude/projects the edit backups have no use. No transcripts at all: nothing goes.
        let claude = home + "/.claude", history = claude + "/file-history", projects = claude + "/projects"
        guard realFolder(claude), realFolder(history), realFolder(projects) else { return }
        let sessions = Bash.lines(find(run, [projects, "-mindepth", "2", "-maxdepth", "2", "-type", "f", "-name", "*.jsonl"])).map { line -> String in
            let name = base(line)
            return name.hasSuffix(".jsonl") ? String(String.UnicodeScalarView(name.unicodeScalars.dropLast(6))) : name
        }.joined(separator: "\n")
        guard !sessions.isEmpty else { return }
        let backups = Bash.lines(find(run, [history, "-mindepth", "1", "-maxdepth", "1", "-type", "d", "-mtime", "+7"])).filter { !$0.isEmpty }
            .filter { !listed(base($0), in: sessions) }.joined(separator: "\n")
        guard !backups.isEmpty else { return }
        add("claude_fh", 1, format(run, "Claude Code edit backups of deleted sessions (%s)", String(Run.count(backups))), backups, .trash, claudeBusy)
    }

    /// What VS Code, Cursor and the like keep for a workspace whose folder is gone, AI chats of that project included.
    /// Only folders in the home folder count: an unmounted disk looks the same as a deleted folder. Only on a pick, to the Trash.
    static func editorWorkspaces(_ run: Run) {
        guard run.taskAllowed("clean.editor_workspaces") else { return }
        for (folder, name) in CacheTables.electronApps {
            let support = run.env.home + "/Library/Application Support/" + folder, storage = support + "/User/workspaceStorage"
            guard realFolder(storage), !Run.isSymlink(support), !Run.isSymlink(support + "/User") else { continue }
            let gone = goneWorkspaces(storage, home: run.env.home).joined(separator: "\n")
            guard !gone.isEmpty else { continue }
            run.register(task: "clean.editor_workspaces", level: 3, label: format(run, "%s: data of workspaces whose folder is gone (%s)", name, String(Run.count(gone))),
                         kb: run.kbl(gone), kind: .trash, paths: gone, proc: "/\(name).app/Contents/|user-data-dir=\(support)( --|/|$)", keySource: "ws|\(folder)",
                         manual: true)
        }
    }

    /// macup_helpers.py editor_workspaces: the workspace folders whose workspace.json names a project folder that is gone.
    /// Python stops at a workspace.json that is no object, after the folders before it.
    static func goneWorkspaces(_ storage: String, home: String) -> [String] {
        var gone: [String] = []
        for name in sortedNames(storage) ?? [] {
            let folder = storage + "/" + name
            guard !Run.isSymlink(folder), Run.isDirectory(folder), let json = JSONValue.parse(file: folder + "/workspace.json") else { continue }
            guard case .object = json else { return gone }
            let named = [json["folder"], json["workspace"]].compactMap { $0 }.first { $0.isTruthy } ?? .string("")
            guard let isGone = workspaceGone(named, home: home) else { return gone }
            if isGone { gone.append(folder) }
        }
        return gone
    }

    /// workspace_gone: a file:// URI of a folder in the home folder that is no longer there. iCloud Drive and cloud providers
    /// hide folders while signed out, and under Library nothing is a project; a symlink on the way may lead to an unmounted
    /// disk, so the deepest folder still there must be a real one on the home folder's disk.
    /// nil where urlparse raises (a bracket of an IPv6 address without its pair), which ends Python's whole listing.
    static func workspaceGone(_ uri: JSONValue, home: String) -> Bool? {
        guard case .string(let text) = uri, text.hasPrefix("file://") else { return false }
        // urlsplit drops tabs and line breaks anywhere in the URL first
        var rest = Substring(String(text.unicodeScalars.dropFirst(7).filter { !["\t", "\r", "\n"].contains($0) }))
        let hostEnd = rest.firstIndex { $0 == "/" || $0 == "?" || $0 == "#" } ?? rest.endIndex
        let host = String(rest[..<hostEnd])
        if host.contains("[") != host.contains("]") { return nil }
        guard ["", "localhost"].contains(host) else { return false }
        rest = rest[hostEnd...]
        if let end = rest.firstIndex(where: { $0 == "?" || $0 == "#" }) { rest = rest[..<end] }
        let path = percentDecoded(String(rest))
        guard Bash.starts(path, home + "/"), !path.contains("/../"), !Checks.exists(path), !Bash.starts(path, home + "/Library/") else { return false }
        var current = home
        for part in after(home + "/", path).components(separatedBy: "/") {
            let next = current.hasSuffix("/") ? current + part : current + "/" + part
            if Run.isSymlink(next) { return false }
            if !Run.isDirectory(next) { break }
            current = next
        }
        var deepest = stat(), homeInfo = stat()
        return stat(current, &deepest) == 0 && stat(home, &homeInfo) == 0 && deepest.st_dev == homeInfo.st_dev
    }

    /// urllib.parse.unquote: %XX as bytes, read as UTF-8 with a replacement character for what is not.
    static func percentDecoded(_ text: String) -> String {
        guard text.contains("%") else { return text }
        let bytes = Array(text.utf8)
        var out: [UInt8] = [], index = 0
        func hex(_ byte: UInt8) -> UInt8? {
            switch byte {
            case 0x30...0x39: byte - 0x30
            case 0x41...0x46: byte - 0x37
            case 0x61...0x66: byte - 0x57
            default: nil
            }
        }
        while index < bytes.count {
            if bytes[index] == 0x25, index + 2 < bytes.count, let high = hex(bytes[index + 1]), let low = hex(bytes[index + 2]) {
                out.append(high << 4 | low)
                index += 3
            } else {
                out.append(bytes[index])
                index += 1
            }
        }
        return String(decoding: out, as: UTF8.self)
    }
}

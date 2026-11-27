import Darwin
import Foundation

/// check.commands: scripts in the bin folders that cannot start, dead links, PATH folders that are gone.
extension Tools {
    static func commands(_ run: Run) {
        let out = run.out, home = run.env.home, paths = run.env.paths
        out.step("Checking commands")
        // a script whose interpreter is gone stays on PATH and only fails when run ("env: node: No such file or directory"):
        // an unlinked keg-only node@24, a pipx venv whose Python was removed by brew, a link to a deleted file
        let scan = Bash.lines(commandScan([home + "/.local/bin", home + "/.npm-global/bin", "/opt/homebrew/bin", "/usr/local/bin"], home: home, shell: run.shell))
        if scan.count == 1 {
            out.ok("Commands: all %s scripts in your bin folders can start", scan[0])
        }
        for line in scan.dropFirst() {
            let fields = readTabs(line, 4), name = fields[0], names = fields[2], from = fields[3]
            var hint = fields[1]
            if name == "-" {
                var fix = "find \(paths.tildify(hint)) -maxdepth 1 -type l ! -exec test -e {} \\; -print -delete"
                if access(hint, W_OK) != 0 { fix = "sudo " + fix }
                out.warn("Dead links in %s, leftovers of removed %s: %s — safe to remove, run in Terminal: %s", paths.tildify(hint), from, names, fix)
                continue
            }
            if hint == "-" { hint = Updates.linkFix(run, name) }
            if hint.isEmpty {
                out.warn("Commands that cannot start, %s is missing: %s", name, names)
            } else {
                out.warn("Commands that cannot start, %s is missing: %s — run: %s", name, names, hint)
            }
        }
        // folders of yours in PATH that do not exist: a line in ~/.zshrc for a tool that was removed (macOS itself lists system folders that may not exist)
        let gone = missingPathFolders(run.env)
        if !gone.isEmpty { out.info("PATH names folders that do not exist: %s — the lines that add them (~/.zshrc, ~/.zprofile) can go", gone) }
    }

    /// `printf '%s' "$USER_PATH" | tr ':' '\n' | awk 'NF && !seen[$0]++' | while …; do [[ $d == "$HOME"/* ]] && [ ! -d "$d" ] && tildify "$d"; done
    /// | paste -sd, - | sed 's/,/, /g'`
    static func missingPathFolders(_ env: Env) -> String {
        var seen = Set<[Unicode.Scalar]>(), gone: [String] = []
        for entry in env.userPath.unicodeScalars.split(whereSeparator: { $0 == ":" || $0 == "\n" }) {
            let folder = String(String.UnicodeScalarView(entry))
            guard entry.contains(where: { $0 != " " && $0 != "\t" }), seen.insert(Array(entry)).inserted else { continue }
            if starts(folder, env.home + "/"), !Run.isDirectory(folder) { gone.append(env.paths.tildify(folder)) }
        }
        return gone.joined(separator: ",").replacingOccurrences(of: ",", with: ", ", options: .literal)
    }

    /// `IFS=$'\t' read -r first … last`: tab is white space to read, so a run of tabs is one separator and the ends are trimmed.
    static func readTabs(_ line: String, _ count: Int) -> [String] {
        var rest = Substring(line).unicodeScalars.drop(while: { $0 == "\t" })
        var fields: [String] = []
        while fields.count < count - 1 {
            let word = rest.prefix(while: { $0 != "\t" })
            fields.append(String(String.UnicodeScalarView(word)))
            rest = rest.dropFirst(word.count).drop(while: { $0 == "\t" })
        }
        while rest.last == "\t" { rest = rest.dropLast() }
        return fields + [String(String.UnicodeScalarView(rest))]
    }

    /// macup_helpers.py `commands`: bin folders → the number of scripts, then a line per interpreter that is gone or folder of
    /// dead links: name, fix ("-" for none) or folder, the scripts, what the links pointed into; tab-separated.
    static func commandScan(_ folders: [String], home givenHome: String, shell: Shell) -> String {
        typealias Scalars = [Unicode.Scalar]
        func text(_ scalars: Scalars) -> String { String(String.UnicodeScalarView(scalars)) }
        func before(_ left: Scalars, _ right: Scalars) -> Bool { left.lexicographicallyPrecedes(right) }
        let home = PythonPath.normpath(givenHome)
        var scripts = 0, real: [Scalars] = [], given: [String] = []
        var groups: [[Scalars]: Set<Scalars>] = [:], gone: [Scalars: Set<Scalars>] = [:]
        for folder in folders where Run.isDirectory(folder) {
            let resolved = Array(PythonPath.realpath(folder).unicodeScalars)
            if !real.contains(resolved) { real.append(resolved); given.append(folder) }
        }
        for folder in given {
            guard let entries = try? FileManager.default.contentsOfDirectory(atPath: folder) else { continue }
            for name in entries {
                let path = PythonPath.join(folder, name), resolved = PythonPath.realpath(path)
                // files Homebrew installed are brew doctor's job (libevent ships an `env python` script nobody runs)
                if resolved.range(of: "/Cellar/", options: .literal) != nil { continue }
                var info = stat()
                guard stat(path, &info) == 0 else {
                    guard Run.isSymlink(path) else { continue }
                    groups[[Array("-".unicodeScalars), Array(folder.unicodeScalars)], default: []].insert(Array(name.unicodeScalars))
                    // what was removed, so people know whose leftovers these are: Python.framework, Foo.app, node_modules/quicktype
                    let target = PythonPath.normpath(PythonPath.join(folder, PythonPath.readlink(path)))
                    let range = NSRange(location: 0, length: (target as NSString).length)
                    let owner = removedOwner.firstMatch(in: target, range: range).map { (target as NSString).substring(with: $0.range) } ?? PythonPath.dirname(target)
                    let shown = starts(owner, home + "/") ? "~" + String(String.UnicodeScalarView(owner.unicodeScalars.dropFirst(home.unicodeScalars.count))) : owner
                    gone[Array(folder.unicodeScalars), default: []].insert(Array(shown.unicodeScalars))
                    continue
                }
                guard info.st_mode & S_IFMT == S_IFREG, access(path, X_OK) == 0, let head = shebang(path) else { continue }
                scripts += 1
                guard let first = head.first else { continue }
                let interpreter: String
                if PythonPath.basename(first) == "env" {
                    let rest = head.dropFirst().filter { !starts($0, "-") && !$0.unicodeScalars.contains("=") }
                    guard let wanted = rest.first, !PythonPath.which(wanted, path: shell.vars["PATH"]) else { continue }
                    interpreter = wanted
                } else if access(first, X_OK) == 0 {
                    continue
                } else {
                    interpreter = PythonPath.basename(first)
                }
                let both = resolved + " " + first
                let uv = uvTool.firstMatch(in: both, range: NSRange(location: 0, length: (both as NSString).length)).map { (both as NSString).substring(with: $0.range(at: 1)) }
                let hint = resolved.range(of: "/pipx/venvs/", options: .literal) != nil ? "pipx reinstall-all" : uv.map { "uv tool install --reinstall \($0)" } ?? "-"
                groups[[Array(interpreter.unicodeScalars), Array(hint.unicodeScalars)], default: []].insert(Array(name.unicodeScalars))
            }
        }
        var lines = [String(scripts)]
        for key in groups.keys.sorted(by: { before($0[0], $1[0]) || ($0[0] == $1[0] && before($0[1], $1[1])) }) {
            let names = groups[key, default: []].sorted(by: before).map(text)
            let shown = names.prefix(10).joined(separator: ", ") + (names.count > 10 ? " +\(names.count - 10)" : "")
            let from = gone[key[1], default: []].sorted(by: before).map(text).joined(separator: ", ")
            lines.append([text(key[0]), text(key[1]), shown, from].joined(separator: "\t"))
        }
        return lines.joined(separator: "\n")
    }

    private static let removedOwner = try! NSRegularExpression(pattern: "[^/]+\\.(?:framework|app)|node_modules/(?:@[^/]+/)?[^/]+")
    private static let uvTool = try! NSRegularExpression(pattern: "/uv/tools/([^/]+)/")

    /// The words of a script's `#!` line as Python splits them (`readline(256)`, UTF-8 with replacements, `str.split()`);
    /// nil when it cannot be read or does not start with `#!`.
    static func shebang(_ path: String) -> [String]? {
        let descriptor = open(path, O_RDONLY)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        var buffer = [UInt8](repeating: 0, count: 256)
        let count = read(descriptor, &buffer, buffer.count)
        guard count >= 2, buffer[0] == 0x23, buffer[1] == 0x21 else { return nil }
        let rest = buffer[2..<count], line = rest.firstIndex(of: 0x0A).map { rest[...$0] } ?? rest
        let words = String(decoding: line, as: UTF8.self).unicodeScalars.split(whereSeparator: PythonPath.isSpace)
        return words.map { String(String.UnicodeScalarView($0)) }
    }
}

/// os.path as Python 3.9 has it on macOS, for the parts that macup_helpers.py's answers depend on.
enum PythonPath {
    /// `str.isspace()`.
    static func isSpace(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isWhitespace || (0x1C...0x1F).contains(scalar.value)
    }

    static func join(_ base: String, _ name: String) -> String {
        if Tools.starts(name, "/") || base.isEmpty { return name }
        return base.unicodeScalars.last == "/" ? base + name : base + "/" + name
    }

    static func basename(_ path: String) -> String {
        guard let slash = path.unicodeScalars.lastIndex(of: "/") else { return path }
        return String(path.unicodeScalars[path.unicodeScalars.index(after: slash)...])
    }

    /// `os.path.dirname`, the head of `os.path.split`: up to the last slash, trailing slashes gone unless it is all slashes.
    static func dirname(_ path: String) -> String {
        guard let slash = path.unicodeScalars.lastIndex(of: "/") else { return "" }
        let head = path.unicodeScalars[...slash]
        if head.allSatisfy({ $0 == "/" }) { return String(head) }
        return String(String.UnicodeScalarView(head.reversed().drop(while: { $0 == "/" }).reversed()))
    }

    static func normpath(_ path: String) -> String {
        guard !path.isEmpty else { return "." }
        let scalars = path.unicodeScalars
        var slashes = scalars.first == "/" ? 1 : 0
        if Tools.starts(path, "//"), !Tools.starts(path, "///") { slashes = 2 }
        var parts: [Substring.UnicodeScalarView] = []
        for part in Substring(path).unicodeScalars.split(separator: "/", omittingEmptySubsequences: false) where !part.isEmpty && !part.elementsEqual(".".unicodeScalars) {
            let up = part.elementsEqual("..".unicodeScalars)
            if !up || (slashes == 0 && parts.isEmpty) || (parts.last?.elementsEqual("..".unicodeScalars) ?? false) {
                parts.append(part)
            } else if !parts.isEmpty {
                parts.removeLast()
            }
        }
        let joined = parts.map { String(String.UnicodeScalarView($0)) }.joined(separator: "/")
        let result = String(repeating: "/", count: slashes) + joined
        return result.isEmpty ? "." : result
    }

    /// `shutil.which(name) is not None`: an executable that is not a folder, looked up in PATH unless the name has a slash;
    /// an empty PATH finds nothing, an empty entry is the current folder.
    static func which(_ name: String, path: String?) -> Bool {
        func runnable(_ file: String) -> Bool {
            var info = stat()
            return stat(file, &info) == 0 && access(file, X_OK) == 0 && info.st_mode & S_IFMT != S_IFDIR
        }
        if name.unicodeScalars.contains("/") { return runnable(name) }
        guard let path, !path.isEmpty else { return false }
        return path.unicodeScalars.split(separator: ":", omittingEmptySubsequences: false).contains { runnable(join(String(String.UnicodeScalarView($0)), name)) }
    }

    static func readlink(_ path: String) -> String {
        // a [UInt8] buffer for char * made Swift 6.1 pass the array variable's own address
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX) + 1)
        let count = Darwin.readlink(path, &buffer, buffer.count)
        return count > 0 ? String(decoding: buffer[..<count].map { UInt8(bitPattern: $0) }, as: UTF8.self) : ""
    }

    /// `os.path.realpath`: links resolved as far as the path goes, whatever is not there kept as it is written.
    static func realpath(_ path: String) -> String {
        var seen: [String: String?] = [:]
        func resolve(_ start: String, _ rest: String) -> (path: String, ok: Bool) {
            var resolved = start
            var parts = Array(Substring(rest).unicodeScalars.split(separator: "/", omittingEmptySubsequences: false).map { String(String.UnicodeScalarView($0)) })
            if Tools.starts(rest, "/") { parts.removeFirst(); resolved = "/" }
            while !parts.isEmpty {
                let name = parts.removeFirst()
                if name.isEmpty || name == "." { continue }
                if name == ".." {
                    if resolved.isEmpty { resolved = ".." } else {
                        let tail = basename(resolved)
                        resolved = dirname(resolved)
                        if tail == ".." { resolved = join(join(resolved, ".."), "..") }
                    }
                    continue
                }
                let next = join(resolved, name)
                guard Run.isSymlink(next) else { resolved = next; continue }
                if let known = seen[next] {
                    if let known { resolved = known; continue }
                    return (join(next, parts.joined(separator: "/")), false)   // a loop: the rest as it is
                }
                seen[next] = .some(nil)
                let target = resolve(resolved, readlink(next))
                if !target.ok { return (join(target.path, parts.joined(separator: "/")), false) }
                seen[next] = .some(target.path)
                resolved = target.path
            }
            return (resolved, true)
        }
        return normpath(resolve("", path).path)
    }
}

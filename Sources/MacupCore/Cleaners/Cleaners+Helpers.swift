import Darwin
import Foundation

/// The small shell pieces cleaners.sh leans on, and its registering helpers clean_old and measure_cmd (cleanup.sh).
extension Cleaners {
    static func translate(_ run: Run, _ text: String) -> String { run.out.i18n.translate(text) }

    static func format(_ run: Run, _ fmt: String, _ args: String...) -> String { run.out.i18n.format(fmt, args: args) }

    /// `[ -d "$1" ] && [ ! -L "$1" ]`.
    static func realFolder(_ path: String) -> Bool { Run.isDirectory(path) && !Run.isSymlink(path) }

    /// `[ -e "$1" ]`, which follows a link.
    static func exists(_ path: String) -> Bool { access(path, F_OK) == 0 }

    /// `$(find …  2>/dev/null)`.
    static func find(_ run: Run, _ arguments: [String]) -> String { Checks.output(run, ["find"] + arguments) }

    /// `$(printf '%s' "$text" | tool…)`, the tool's output as it is.
    static func filter(_ run: Run, _ argv: [String], _ text: String) -> String {
        var ends: [Int32] = [0, 0]
        guard pipe(&ends) == 0 else { return "" }
        _ = fcntl(ends[1], F_SETNOSIGPIPE, 1)
        let writer = FileHandle(fileDescriptor: ends[1], closeOnDealloc: true)
        // from another thread: a tool that reads everything before it writes would fill both pipes
        Thread { try? writer.write(contentsOf: Data(text.utf8)); try? writer.close() }.start()
        let output = run.shell.capture(argv, stdin: .fd(ends[0])).output
        close(ends[0])
        return output
    }

    /// `$(tool 2>&1)`: both streams on one pipe; 127 when the tool is not there.
    static func outputAndErrors(_ run: Run, _ argv: [String]) -> (status: Int32, output: Data) {
        var ends: [Int32] = [0, 0]
        guard pipe(&ends) == 0 else { return (127, Data()) }
        guard let pid = run.shell.spawn(argv, stdin: .inherit, stdout: .fd(ends[1]), stderr: .stdout) else {
            close(ends[0]); close(ends[1]); return (127, Data())
        }
        close(ends[1])
        let data = FileHandle(fileDescriptor: ends[0], closeOnDealloc: true).readDataToEndOfFile()
        return (Shell.wait(pid), data)
    }

    /// `IFS=<separator> read -r first … last`: a blank separator (a tab) also drops runs of itself at the ends and between
    /// fields; any other ends every field, and a single one left at the end of the last field goes.
    static func read(_ line: String, _ separator: Unicode.Scalar, _ count: Int) -> [String] {
        var rest = Substring(line).unicodeScalars
        let blank = separator == " " || separator == "\t"
        var fields: [String] = []
        if blank { rest = rest.drop { $0 == separator } }
        while fields.count < count - 1, let end = rest.firstIndex(of: separator) {
            fields.append(String(String.UnicodeScalarView(rest[..<end])))
            rest = rest[rest.index(after: end)...]
            if blank { rest = rest.drop { $0 == separator } }
        }
        if blank {
            while rest.last == separator { rest = rest.dropLast() }
        } else if rest.last == separator, !rest.dropLast().contains(separator) {
            rest = rest.dropLast()
        }
        fields.append(String(String.UnicodeScalarView(rest)))
        return fields + Array(repeating: "", count: count - fields.count)
    }

    /// `paste -sd, - | sed 's/,/, /g'`.
    static func commaList(_ lines: [String]) -> String {
        lines.joined(separator: ",").replacingOccurrences(of: ",", with: ", ")
    }

    /// `sed "s|^|$prefix/|"` on every line.
    static func prefixed(_ lines: [String], _ folder: String) -> [String] {
        lines.map { Paths.sedReplacement(folder + "/", match: "") + $0 }
    }

    /// `[ "$1" = "$2" ]`: the same bytes, where Swift's == would also take a composed and a decomposed é as one.
    static func same(_ left: String, _ right: String) -> Bool { left.unicodeScalars.elementsEqual(right.unicodeScalars) }


    /// The text after a prefix it starts with, as `${text#"$prefix"}`.
    static func after(_ prefix: String, _ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.dropFirst(prefix.unicodeScalars.count)))
    }

    /// `printf '%s\n' "$list" | grep -qxF -- "$name"`.
    static func listed(_ name: String, in list: String) -> Bool {
        Bash.lines(list).contains { same($0, name) }
    }

    /// The last path component, as `${path##*/}`.
    static func base(_ path: String) -> String {
        path.unicodeScalars.lastIndex(of: "/").map { String(path.unicodeScalars[path.unicodeScalars.index(after: $0)...]) } ?? path
    }

    /// clean_old: the entries in a folder older than `days`, as one rm candidate.
    static func cleanOld(_ run: Run, _ task: String, _ label: String, _ folder: String, _ days: Int, type: String = "d", level: Int = 1) {
        guard run.taskAllowed(task), realFolder(folder), run.safePaths.allows(folder) else { return }
        let old = find(run, [folder, "-mindepth", "1", "-maxdepth", "1", "-type", type, "-mtime", "+\(days)"])
        guard !old.isEmpty else { return }
        let size = run.kbl(old)
        guard size >= 1024 else { return }
        run.register(task: task, level: level, label: format(run, "%s (%s items, older than %s days)", translate(run, label), String(Run.count(old)), String(days)),
                     kb: size, kind: .rm, paths: old, keySource: "old|\(folder)")
    }

    /// measure_cmd: a tool's own clean command; its folder is measured before and after.
    static func measureCommand(_ run: Run, _ task: String, level: Int, _ label: String, _ folder: String, _ key: String) {
        guard run.taskAllowed(task), exists(folder) else { return }
        let size: Int64? = run.measure.has(folder) ? nil : run.kb(folder)
        run.register(task: task, level: level, label: translate(run, label), kb: size, kind: .cmd, paths: key, measureDir: folder)
    }

    /// `grep -oE`: every match of each line, left to right.
    static func matches(_ expression: NSRegularExpression, in text: String) -> [String] {
        Bash.lines(text).flatMap { line -> [String] in
            let string = line as NSString
            return expression.matches(in: line, range: NSRange(location: 0, length: string.length)).map { string.substring(with: $0.range) }
        }
    }
}

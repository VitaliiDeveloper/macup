import Darwin
import Foundation

/// A run's files (arguments.sh): the report `macup_<date>.md` in the log folder, and while the run lasts a temporary
/// body `$TMPDIR/macup.XXXXXX` with `.raw` (what the commands print) next to it. The names are the bash build's, so either
/// version tidies what a killed run of the other left behind.
public struct Report {
    public let path: String
    public let body: String
    public var raw: String { body + ".raw" }

    /// `macup_<YYYY-mm-dd_HH-MM-SS>.md`, with `_<pid>` when a run in the same second already has that name.
    public static func path(logDir: String, date: Date = Date(), pid: pid_t = getpid()) -> String {
        let stamp = Report.stamp(date)
        let candidate = "\(logDir)/macup_\(stamp).md"
        return FileManager.default.fileExists(atPath: candidate) ? "\(logDir)/macup_\(stamp)_\(pid).md" : candidate
    }

    static func stamp(_ date: Date) -> String {
        var seconds = time_t(date.timeIntervalSince1970)
        var tm = tm()
        localtime_r(&seconds, &tm)
        var buf = [CChar](repeating: 0, count: 32)
        strftime(&buf, buf.count, "%Y-%m-%d_%H-%M-%S", &tm)
        return String(cString: buf)
    }

    /// Creates the temporary body (`mktemp "${TMPDIR:-/tmp}/macup.XXXXXX"`).
    public static func create(env: Env, date: Date = Date()) -> Report? {
        var template = Array("\(env.tmpDir)/macup.XXXXXX".utf8CString)
        let fd = mkstemp(&template)
        guard fd >= 0 else { return nil }
        close(fd)
        return Report(path: path(logDir: env.logDir, date: date), body: String(cString: template))
    }
}

/// macup tidies up after itself on every run, a check too (`tidy_own`): its reports are its own files, not the Mac's.
/// Reports older than keep_reports_days go, never more than keep_reports runs stay; the history keeps its last 500 lines,
/// the schedule's log its last 200; temporary files a killed run left behind go after a day.
/// File ages come from `find -mtime`, run as a tool.
public enum Tidy {
    public static func run(env: Env, settings: Settings, shell: Shell) {
        // only an explicit skip: --only check.disk still tidies up
        if settings.skip.contains(",clean.reports,") { return }
        let log = env.logDir
        // .log: the command output that versions before 2.9.0 kept next to each report
        _ = shell.tl(0, ["find", log, "-maxdepth", "1", "-type", "f", "(", "-name", "macup_*.md", "-o", "-name", "macup_*.log", ")",
                         "-mtime", "+\(settings.keepReportsDays)", "-delete"], stdin: .inherit, stdout: .inherit, stderr: .null)
        // this run's report is not written yet: it makes keep_reports
        let reports = ((try? FileManager.default.contentsOfDirectory(atPath: log)) ?? [])
            .filter { $0.hasPrefix("macup_") && $0.hasSuffix(".md") && $0.utf8.count >= 9 }
            .sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
            .reversed()
        for name in reports.dropFirst(max(0, settings.keepReports - 1)) {
            unlink("\(log)/\(name)")
            unlink("\(log)/\(name.dropLast(3)).log")
        }
        trim(env.history, keep: 500)
        trim("\(log)/schedule.log", keep: 200)
        let six = String(repeating: "[A-Za-z0-9]", count: 6)
        _ = shell.tl(0, ["find", env.tmpDir + "/", "-maxdepth", "1", "-type", "f", "-user", String(getuid()),
                         "(", "-name", "macup.\(six)", "-o", "-name", "macup.\(six).*", "-o", "-name", "macup-lang.??????", "-o", "-name", "macup-rc.??????", ")",
                         "!", "-name", "macup.sha256", "-mtime", "+1", "-delete"], stdin: .inherit, stdout: .inherit, stderr: .null)
    }

    /// Keeps the last `keep` lines of a file that has more than twice as many; the file stays the same file.
    static func trim(_ path: String, keep: Int) {
        defer { unlink(path + ".tmp") }
        guard let contents = Bash.regularFileContents(path), Bash.lineCount(contents) > keep * 2 else { return }
        let tail = lastLines(contents, keep)
        guard let handle = FileHandle(forWritingAtPath: path) else { return }
        try? handle.truncate(atOffset: 0)
        try? handle.write(contentsOf: tail)
        try? handle.close()
    }

    /// `tail -n keep`: a last line without a newline counts as a line.
    static func lastLines(_ data: Data, _ keep: Int) -> Data {
        let bytes = [UInt8](data)
        var end = bytes.count
        if end > 0, bytes[end - 1] == 0x0A { end -= 1 }
        var count = 0, index = end
        while index > 0 {
            if bytes[index - 1] == 0x0A { count += 1; if count == keep { break } }
            index -= 1
        }
        return Data(bytes[index...])
    }
}

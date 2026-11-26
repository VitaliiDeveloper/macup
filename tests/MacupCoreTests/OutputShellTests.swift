@testable import MacupCore
import XCTest

final class OutputShellTests: XCTestCase {
    var dir = ""

    override func setUpWithError() throws {
        dir = NSTemporaryDirectory() + "macup-out-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(atPath: dir) }

    func env(_ extra: [String: String] = [:]) throws -> Env {
        var v = ["HOME": dir, "PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "MACUP_PATH": "keep", "TMPDIR": dir]
        for (k, x) in extra { v[k] = x }
        return try Env(v)
    }

    /// The same calls through core.sh's output functions and through Output: terminal lines, report and --json items.
    func testLinesReportAndItemsAgainstBash() throws {
        let script: [(String, [String])] = [
            ("section", ["System"]), ("ok", ["Disk: %s free of %s (%s%%)", "10 GB", "100 GB", "10"]), ("sub", ["a line under it"]),
            ("section", ["Empty section"]), ("section", ["Updates"]), ("warn", ["%s: stopped after %s minutes", "brew", "60"]),
            ("mdonly", ["only in the report"]), ("info", ["plain %s\n\n", "text"]), ("err", ["failed %d", "3"]), ("fail", ["no args"]),
        ]
        for colors in [Colors.off, Colors.on] {
            let body = dir + "/body", outFile = dir + "/out"
            FileManager.default.createFile(atPath: body, contents: nil)
            FileManager.default.createFile(atPath: outFile, contents: nil)
            let fd = open(outFile, O_WRONLY | O_APPEND)
            let o = Output(i18n: I18n(lang: .en, translations: [:]), colors: colors, fd: fd)
            o.body = FileHandle(forWritingAtPath: body)
            o.json = true
            for (f, a) in script {
                switch f {
                case "section": o.beginSection(a[0])
                case "ok": o.ok(a[0], args: Array(a.dropFirst()))
                case "info": o.info(a[0], args: Array(a.dropFirst()))
                case "warn": o.warn(a[0], args: Array(a.dropFirst()))
                case "fail": o.fail(a[0], args: Array(a.dropFirst()))
                case "err": o.err(a[0], args: Array(a.dropFirst()))
                case "sub": o.sub(a[0])
                default: o.mdonly(a[0])
                }
            }
            close(fd)
            let swiftOut = try String(contentsOfFile: outFile, encoding: .utf8), swiftBody = try String(contentsOfFile: body, encoding: .utf8)
            let items = o.items.enumerated().map { "\($0.element.section)|\($0.element.kind)|\($0.element.text)|\($0.element.details.joined(separator: "^"))" }

            let c = colors == .on ? "B=$'\\033[1m'; G=$'\\033[32m'; Y=$'\\033[33m'; R=$'\\033[31m'; C=$'\\033[36m'; D=$'\\033[2m'; N=$'\\033[0m'; CL=$'\\r\\033[K'" : "B=; G=; Y=; R=; C=; D=; N=; CL="
            let calls = script.map { f, a in "\(f)" + a.map { " " + BashOracle.q($0) }.joined() }.joined(separator: "; ")
            let prelude = "\(c); JSON=1; BODY=\(BashOracle.q(dir + "/bbody")); : >\"$BODY\"; rm -f \"$BODY.det\""
            let dump = "for ((i=0; i<IT_N; i++)); do printf '%s|%s|%s|%s\\n' \"${IT_SEC[i]}\" \"${IT_KIND[i]}\" \"${IT_MSG[i]}\" \"$(awk -F'\\t' -v n=$i '$1==n{print $2}' \"$BODY.det\" 2>/dev/null | paste -sd^ -)\"; done; printf '%s|%s' \"${#WARN[@]}\" \"$ERRS\""
            let got = try BashOracle.run(["{ \(calls); } 2>&1; printf x", "cat \"$BODY\"; printf x", dump], prelude: prelude)
            // the first call's $(…) runs in a subshell: run the lines again for the state
            let state = try BashOracle.run([dump], prelude: prelude + "; { \(calls); } >/dev/null")
            XCTAssertEqual(swiftOut + "x", got[0], "terminal lines, colours \(colors == .on)")
            XCTAssertEqual(swiftBody + "x", got[1], "report")
            XCTAssertEqual(items.joined(separator: "\n") + "\n\(o.warnings.count)|\(o.errors)", state[0], "--json items, warnings, errors")
        }
    }

    func testStepOnlyOnATerminal() throws {
        let p = dir + "/o"
        FileManager.default.createFile(atPath: p, contents: nil)
        let fd = open(p, O_WRONLY)
        let o = Output(i18n: I18n(lang: .en, translations: [:]), colors: .on, fd: fd)
        o.step("Updating %s", "brew")
        close(fd)
        XCTAssertEqual(try String(contentsOfFile: p, encoding: .utf8), "", "a file is not a terminal")
    }

    func testWhichAndHaveFollowPath() throws {
        let bin = dir + "/bin"
        try FileManager.default.createDirectory(atPath: bin, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: bin + "/brew", contents: Data("#!/bin/sh\necho fake\n".utf8), attributes: [.posixPermissions: 0o755])
        FileManager.default.createFile(atPath: bin + "/notexec", contents: Data(), attributes: [.posixPermissions: 0o644])
        let sh = Shell(env: try env(["PATH": "\(bin):/usr/bin:/bin"]))
        XCTAssertEqual(sh.which("brew"), bin + "/brew", "the fake comes first")
        XCTAssertNil(sh.which("notexec"))
        XCTAssertTrue(sh.have("ls"))
        XCTAssertFalse(sh.have("macup-no-such-tool"))
        XCTAssertEqual(sh.capture(["brew"]).output, "fake\n")
        XCTAssertEqual(Shell(env: try env(["PATH": "/usr/bin:/bin", "MACUP_PATH": ""])).vars["PATH"]?.hasPrefix("/opt/homebrew/bin:"), true)
    }

    /// tl: a command past its time is stopped with what it started, and the status is 124.
    func testTlStopsTheCommandAndItsChildren() throws {
        let sh = Shell(env: try env())
        let pidFile = dir + "/child.pid"
        let t0 = Date()
        let rc = sh.tl(1, ["/bin/sh", "-c", "sleep 300 & echo $! >\(pidFile); wait"], stdin: .null, stdout: .null, stderr: .null)
        XCTAssertEqual(rc, 124)
        XCTAssertLessThan(Date().timeIntervalSince(t0), 8)
        usleep(300_000)
        let child = pid_t(try String(contentsOfFile: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines))!
        XCTAssertNotEqual(kill(child, 0), 0, "the child of a stopped step is gone")
        XCTAssertEqual(sh.tl(5, ["/bin/sh", "-c", "exit 3"]), 3)
        XCTAssertEqual(sh.tl(0, ["/bin/sh", "-c", "exit 4"]), 4)
        XCTAssertEqual(sh.tl(5, ["macup-no-such-tool"], stderr: .null), 127)
    }

    /// A command that ignores SIGTERM gets SIGKILL 5 seconds later.
    func testTlKillsWhatIgnoresTerm() throws {
        let sh = Shell(env: try env())
        let t0 = Date()
        let rc = sh.tl(1, ["/bin/sh", "-c", "trap '' TERM; while :; do sleep 1; done"], stdin: .null, stdout: .null, stderr: .null)
        XCTAssertEqual(rc, 124)
        XCTAssertGreaterThan(Date().timeIntervalSince(t0), 5)
        XCTAssertLessThan(Date().timeIntervalSince(t0), 12)
    }

    func testRunWritesTheCommandAndItsOutput() throws {
        let sh = Shell(env: try env())
        let log = RunLog(raw: dir + "/raw", stepSeconds: 60)
        let o = Output(i18n: I18n(lang: .en, translations: [:]), colors: .off, fd: open("/dev/null", O_WRONLY))
        XCTAssertEqual(sh.run(["/bin/sh", "-c", "echo out; echo err >&2; exit 2"], log: log, output: o), 2)
        XCTAssertEqual(try String(contentsOfFile: dir + "/raw", encoding: .utf8), "$ /bin/sh -c echo out; echo err >&2; exit 2\nout\nerr\n")
        let short = RunLog(raw: dir + "/raw2", stepSeconds: 1)
        XCTAssertEqual(sh.run(["/bin/sleep", "30"], log: short, output: o), 124)
        XCTAssertEqual(try String(contentsOfFile: dir + "/raw2", encoding: .utf8), "$ /bin/sleep 30\nmacup: stopped after 0 minutes: /bin/sleep 30\n")
        XCTAssertEqual(o.warnings, ["/bin/sleep: stopped after 0 minutes without finishing (step_timeout_minutes in ~/.config/macup/config)"])
    }

    func testLock() throws {
        let state = dir + "/state"
        try FileManager.default.createDirectory(atPath: state, withIntermediateDirectories: true)
        guard case .acquired(let lock) = RunLock.acquire(stateDir: state) else { return XCTFail("free lock") }
        XCTAssertTrue(lock.held)
        XCTAssertEqual(try String(contentsOfFile: state + "/lock/pid", encoding: .utf8), "\(getpid())\n")
        guard case .busy(let pid) = RunLock.acquire(stateDir: state) else { return XCTFail("held lock") }
        XCTAssertEqual(pid, "\(getpid())")
        lock.release()
        XCTAssertFalse(FileManager.default.fileExists(atPath: state + "/lock"))
        // a lock left by a run that was killed
        try FileManager.default.createDirectory(atPath: state + "/lock", withIntermediateDirectories: true)
        try "999999\n".write(toFile: state + "/lock/pid", atomically: true, encoding: .utf8)
        guard case .acquired(let again) = RunLock.acquire(stateDir: state, pid: 4242) else { return XCTFail("stale lock") }
        XCTAssertEqual(try String(contentsOfFile: state + "/lock/pid", encoding: .utf8), "4242\n")
        again.release()
    }

    func testReportNamesAndTidy() throws {
        let e = try env()
        let log = e.logDir
        try FileManager.default.createDirectory(atPath: log, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: e.stateDir, withIntermediateDirectories: true)
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let p = Report.path(logDir: log, date: date, pid: 77)
        XCTAssertTrue(p.hasPrefix(log + "/macup_20") && p.hasSuffix(".md"))
        FileManager.default.createFile(atPath: p, contents: nil)
        XCTAssertEqual(Report.path(logDir: log, date: date, pid: 77), String(p.dropLast(3)) + "_77.md", "two runs in one second")
        unlink(p)
        let r = try XCTUnwrap(Report.create(env: e))
        XCTAssertTrue(r.body.hasPrefix(dir + "/macup.") && FileManager.default.fileExists(atPath: r.body))
        XCTAssertEqual(r.raw, r.body + ".raw")

        for i in 10...40 { FileManager.default.createFile(atPath: "\(log)/macup_2026-01-01_00-00-\(i).md", contents: nil) }
        FileManager.default.createFile(atPath: "\(log)/macup_2026-01-01_00-00-10.log", contents: nil)
        try (1...1100).map(String.init).joined(separator: "\n").write(toFile: e.history, atomically: true, encoding: .utf8)
        try (1...450).map { "\($0)\n" }.joined().write(toFile: log + "/schedule.log", atomically: true, encoding: .utf8)
        let s = Settings(config: Config(path: e.conf), env: e, cliSkip: "", cliOnly: "", cliEnable: "", cliLevel: nil)
        Tidy.run(env: e, settings: s, shell: Shell(env: e))
        let left = try FileManager.default.contentsOfDirectory(atPath: log).filter { $0.hasPrefix("macup_") }.sorted()
        XCTAssertEqual(left.count, 19, "keep_reports 20: this run's report makes the 20th")
        XCTAssertEqual(left.last, "macup_2026-01-01_00-00-40.md")
        XCTAssertFalse(left.contains("macup_2026-01-01_00-00-10.log"), "a removed report takes its old .log along")
        XCTAssertEqual(try String(contentsOfFile: e.history, encoding: .utf8), (601...1100).map(String.init).joined(separator: "\n"))
        XCTAssertEqual(try String(contentsOfFile: log + "/schedule.log", encoding: .utf8), (251...450).map { "\($0)\n" }.joined())
        XCTAssertEqual(Tidy.lastLines(Data("a\nb\nc".utf8), 2), Data("b\nc".utf8))
        XCTAssertEqual(Tidy.lastLines(Data("a\nb\n".utf8), 5), Data("a\nb\n".utf8))
    }
}

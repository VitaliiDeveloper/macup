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
        var vars = ["HOME": dir, "PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "MACUP_PATH": "keep", "TMPDIR": dir]
        for (key, value) in extra { vars[key] = value }
        return try Env(vars)
    }

    /// Calls through Output give the terminal lines, report and --json items core.sh's output functions of 2.9 gave.
    /// The escapes 2.9's core.sh used: the expected texts below are built from Colors.on, so its bytes are pinned here.
    func testColorEscapes() {
        let on = Colors.on
        XCTAssertEqual([on.bold, on.green, on.yellow, on.red, on.cyan, on.dim, on.reset, on.cl],
                       ["\u{1B}[1m", "\u{1B}[32m", "\u{1B}[33m", "\u{1B}[31m", "\u{1B}[36m", "\u{1B}[2m", "\u{1B}[0m", "\r\u{1B}[K"])
        let off = Colors.off
        XCTAssertEqual([off.bold, off.green, off.yellow, off.red, off.cyan, off.dim, off.reset, off.cl], ["", "", "", "", "", "", "", ""])
    }

    func testLinesReportAndItems() throws {
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
            let output = Output(i18n: I18n(lang: .en, translations: [:]), colors: colors, fd: fd)
            output.body = FileHandle(forWritingAtPath: body)
            output.json = true
            for (call, arguments) in script {
                switch call {
                case "section": output.beginSection(arguments[0])
                case "ok": output.ok(arguments[0], args: Array(arguments.dropFirst()))
                case "info": output.info(arguments[0], args: Array(arguments.dropFirst()))
                case "warn": output.warn(arguments[0], args: Array(arguments.dropFirst()))
                case "fail": output.fail(arguments[0], args: Array(arguments.dropFirst()))
                case "err": output.err(arguments[0], args: Array(arguments.dropFirst()))
                case "sub": output.sub(arguments[0])
                default: output.mdonly(arguments[0])
                }
            }
            close(fd)
            let swiftOut = try String(contentsOfFile: outFile, encoding: .utf8), swiftBody = try String(contentsOfFile: body, encoding: .utf8)
            let items = output.items.enumerated().map { "\($0.element.section)|\($0.element.kind)|\($0.element.text)|\($0.element.details.joined(separator: "^"))" }

            let (bold, green, yellow, red, cyan, dim, reset, cl) = (colors.bold, colors.green, colors.yellow, colors.red, colors.cyan, colors.dim, colors.reset, colors.cl)
            let terminal = """
                \(cl)
                \(bold)\(cyan)▸ System\(reset)
                \(cl)  \(green)✓\(reset) Disk: 10 GB free of 100 GB (10%)
                      \(dim)a line under it\(reset)
                \(cl)
                \(bold)\(cyan)▸ Updates\(reset)
                \(cl)  \(yellow)!\(reset) brew: stopped after 60 minutes
                \(cl)  \(dim)·\(reset) plain text
                \(cl)  \(red)✗\(reset) failed 3
                \(cl)  \(red)✗\(reset) no args

                """
            let report = """

                ## System

                - ✅ Disk: 10 GB free of 100 GB (10%)
                    - a line under it

                ## Updates

                - ⚠️ brew: stopped after 60 minutes
                    - only in the report
                - plain text
                - ❌ failed 3
                - ❌ no args

                """
            let state = """
                System|ok|Disk: 10 GB free of 100 GB (10%)|a line under it
                Updates|warn|brew: stopped after 60 minutes|only in the report
                Updates|info|plain text|
                Updates|fail|failed 3|
                Updates|fail|no args|
                3|1
                """
            XCTAssertEqual(swiftOut, terminal, "terminal lines, colours \(colors == .on)")
            XCTAssertEqual(swiftBody, report, "report")
            XCTAssertEqual(items.joined(separator: "\n") + "\n\(output.warnings.count)|\(output.errors)", state, "--json items, warnings, errors")
        }
    }

    func testStepOnlyOnATerminal() throws {
        let path = dir + "/o"
        FileManager.default.createFile(atPath: path, contents: nil)
        let fd = open(path, O_WRONLY)
        let output = Output(i18n: I18n(lang: .en, translations: [:]), colors: .on, fd: fd)
        output.step("Updating %s", "brew")
        close(fd)
        XCTAssertEqual(try String(contentsOfFile: path, encoding: .utf8), "", "a file is not a terminal")
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

    /// A tool gets only stdin, stdout and stderr: a helper it leaves running does not hold macup's pipe open.
    func testToolsGetNoOtherDescriptors() throws {
        let sh = Shell(env: try env())
        let t0 = Date()
        XCTAssertEqual(sh.capture(["/bin/sh", "-c", "sleep 4 >/dev/null 2>&1 </dev/null & echo hi"]).output, "hi\n")
        XCTAssertLessThan(Date().timeIntervalSince(t0), 2)
        let fds = sh.capture(["/bin/sh", "-c", "ls /dev/fd"]).output.split(separator: "\n").compactMap { Int($0.filter(\.isNumber)) }
        XCTAssertEqual(fds.filter { $0 > 4 }, [], "0–2, and what ls itself opens to list /dev/fd")
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
        let output = Output(i18n: I18n(lang: .en, translations: [:]), colors: .off, fd: open("/dev/null", O_WRONLY))
        XCTAssertEqual(sh.run(["/bin/sh", "-c", "echo out; echo err >&2; exit 2"], log: log, output: output), 2)
        XCTAssertEqual(try String(contentsOfFile: dir + "/raw", encoding: .utf8), "$ /bin/sh -c echo out; echo err >&2; exit 2\nout\nerr\n")
        let short = RunLog(raw: dir + "/raw2", stepSeconds: 1)
        XCTAssertEqual(sh.run(["/bin/sleep", "30"], log: short, output: output), 124)
        XCTAssertEqual(try String(contentsOfFile: dir + "/raw2", encoding: .utf8), "$ /bin/sleep 30\nTerminated: 15\nmacup: stopped after 0 minutes: /bin/sleep 30\n",
                       "bash, waiting for the stopped step, says how it ended")
        XCTAssertEqual(output.warnings, ["/bin/sleep: stopped after 0 minutes without finishing (step_timeout_minutes in ~/.config/macup/config)"])
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
        let environment = try env()
        let log = environment.logDir
        try FileManager.default.createDirectory(atPath: log, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: environment.stateDir, withIntermediateDirectories: true)
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let path = Report.path(logDir: log, date: date, pid: 77)
        XCTAssertTrue(path.hasPrefix(log + "/macup_20") && path.hasSuffix(".md"))
        FileManager.default.createFile(atPath: path, contents: nil)
        XCTAssertEqual(Report.path(logDir: log, date: date, pid: 77), String(path.dropLast(3)) + "_77.md", "two runs in one second")
        unlink(path)
        let report = try XCTUnwrap(Report.create(env: environment))
        XCTAssertTrue(report.body.hasPrefix(dir + "/macup.") && FileManager.default.fileExists(atPath: report.body))
        XCTAssertEqual(report.raw, report.body + ".raw")

        for index in 10...40 { FileManager.default.createFile(atPath: "\(log)/macup_2026-01-01_00-00-\(index).md", contents: nil) }
        FileManager.default.createFile(atPath: "\(log)/macup_2026-01-01_00-00-10.log", contents: nil)
        try (1...1100).map(String.init).joined(separator: "\n").write(toFile: environment.history, atomically: true, encoding: .utf8)
        try (1...450).map { "\($0)\n" }.joined().write(toFile: log + "/schedule.log", atomically: true, encoding: .utf8)
        let settings = Settings(config: Config(path: environment.conf), env: environment, cliSkip: "", cliOnly: "", cliEnable: "", cliLevel: nil)
        Tidy.run(env: environment, settings: settings, shell: Shell(env: environment))
        let left = try FileManager.default.contentsOfDirectory(atPath: log).filter { $0.hasPrefix("macup_") }.sorted()
        XCTAssertEqual(left.count, 19, "keep_reports 20: this run's report makes the 20th")
        XCTAssertEqual(left.last, "macup_2026-01-01_00-00-40.md")
        XCTAssertFalse(left.contains("macup_2026-01-01_00-00-10.log"), "a removed report takes its old .log along")
        XCTAssertEqual(try String(contentsOfFile: environment.history, encoding: .utf8), (601...1100).map(String.init).joined(separator: "\n"))
        XCTAssertEqual(try String(contentsOfFile: log + "/schedule.log", encoding: .utf8), (251...450).map { "\($0)\n" }.joined())
        XCTAssertEqual(Tidy.lastLines(Data("a\nb\nc".utf8), 2), Data("b\nc".utf8))
        XCTAssertEqual(Tidy.lastLines(Data("a\nb\n".utf8), 5), Data("a\nb\n".utf8))
    }
}

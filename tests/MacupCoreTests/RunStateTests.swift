@testable import MacupCore
import XCTest

final class RunStateTests: XCTestCase {
    var home = ""

    override func setUpWithError() throws {
        home = (NSTemporaryDirectory() as NSString).resolvingSymlinksInPath + "/macup-run-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: home + "/bin", withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(atPath: home) }

    func makeRun(_ argv: [String], fakes: [String: String] = [:], output: Int32? = nil) throws -> Run {
        for (name, script) in fakes {
            try "#!/bin/bash\n\(script)\n".write(toFile: "\(home)/bin/\(name)", atomically: true, encoding: .utf8)
            chmod("\(home)/bin/\(name)", 0o755)
        }
        let env = try Env(["HOME": home, "PATH": "\(home)/bin:/usr/bin:/bin", "MACUP_PATH": "keep"])
        let arguments = try Arguments.parse(argv)
        let settings = Settings(config: Config(env: env), env: env, cliSkip: arguments.cliSkip, cliOnly: arguments.cliOnly, cliEnable: arguments.cliEnable, cliLevel: arguments.level)
        let shell = Shell(env: env)
        let out = Output(i18n: I18n(lang: .en, translations: [:]), colors: .off, fd: output ?? open("/dev/null", O_WRONLY))
        return Run(env: env, arguments: arguments, settings: settings, shell: shell, out: out, report: Report(path: home + "/report.md", body: home + "/body"),
                   lock: RunLock(dir: home + "/lock", held: false), started: Date(), previous: "")
    }

    func blob(_ path: String, kilobytes: Int) throws {
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: path + "/blob", contents: Data(count: kilobytes * 1024))
    }

    func testBackgroundMeasuringGivesWhatDuGives() throws {
        let run = try makeRun(["check"])
        try blob("\(home)/caches/one", kilobytes: 300)
        try blob("\(home)/caches/two", kilobytes: 700)
        run.measure.start("\(home)/caches", eachFolder: true)
        XCTAssertTrue(run.measure.has("\(home)/caches/one"), "a walk of the parent covers each folder in it")
        XCTAssertFalse(run.measure.has("\(home)/caches/one/deeper"))
        for path in ["\(home)/caches/one", "\(home)/caches/two", "\(home)/caches"] { XCTAssertEqual(run.measure.get(path), run.kb(path), path) }
        run.measure.forget()
        XCTAssertFalse(run.measure.has("\(home)/caches"), "the cleanup measures anew")
        XCTAssertEqual(run.measure.get("\(home)/nothing"), 0)
    }

    func testSettleSizesAndDropsSmallFolders() throws {
        let run = try makeRun(["check", "--only", "clean.derived_data,clean.spm"])
        try blob("\(home)/big", kilobytes: 6000)
        try blob("\(home)/small", kilobytes: 100)
        run.measure.start("\(home)/big")
        run.measure.start("\(home)/small")
        run.register(task: "clean.derived_data", level: 1, label: "Big", kb: nil, kind: .empty, paths: "\(home)/big")
        run.register(task: "clean.spm", level: 1, label: "Small", kb: nil, kind: .empty, paths: "\(home)/small")
        run.register(task: "clean.trash", level: 3, label: "Not allowed", kb: 1, kind: .rm, paths: "\(home)/x")
        XCTAssertFalse(run.registerMore(label: "Big", level: 1, kb: 1, paths: "\(home)/more", open: ""), "only a candidate whose size is known takes more")
        run.settle()
        XCTAssertEqual(run.candidates.list.map(\.label), ["Big"])
        XCTAssertEqual(run.candidates.list[0].kb, run.kb("\(home)/big"))
        XCTAssertTrue(run.registerMore(label: "Big", level: 1, kb: 10, paths: "\(home)/more", open: "\(home)/open"))
        XCTAssertEqual(run.candidates.list[0].paths, "\(home)/big\n\(home)/more")
        XCTAssertEqual(run.candidates.covered, "\(home)/big\n\(home)/small\n\(home)/more\n")
    }

    func testSudoIsForgottenOnlyWhenMacupAskedForIt() throws {
        let run = try makeRun(["update"], fakes: ["sudo": "echo \"$*\" >>\"$HOME/sudo.log\""])
        run.sudo.stop()
        XCTAssertNil(FileManager.default.contents(atPath: home + "/sudo.log"))
        run.sudo.keepAlive()
        run.sudo.asked = true
        run.sudo.stop()
        XCTAssertEqual(String(decoding: FileManager.default.contents(atPath: home + "/sudo.log") ?? Data(), as: UTF8.self), "-k\n")
        XCTAssertFalse(run.sudo.asked)
    }

    /// No `date` is asked, so its answer cannot move the age; bash's came a second late now and then, and the age a day short.
    func testBackupAgeAsksNoDate() throws {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let latest = formatter.string(from: try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -10, to: Date())))
        let output = open(home + "/out", O_WRONLY | O_CREAT, 0o644)
        let before = Checks.backupAge(latest, now: time(nil))
        Checks.timeMachine(try makeRun(["check"], fakes: ["tmutil": "[ \"$1\" = latestbackup ] && echo /Volumes/Disk/\(latest)-101010.backup || echo 'Name : Disk'",
                                                         "date": "echo $(( $(/bin/date +%s) + 86400 ))"], output: output))
        close(output)
        let printed = try String(contentsOfFile: home + "/out", encoding: .utf8)
        XCTAssertGreaterThanOrEqual(before, 9)
        XCTAssertTrue([before, Checks.backupAge(latest, now: time(nil))].contains { printed.contains("last backup \(latest) (\($0) days ago)") }, printed)
    }
}

@testable import MacupCore
import XCTest

final class ConfigTasksTests: XCTestCase {
    var dir = ""

    override func setUpWithError() throws {
        dir = NSTemporaryDirectory() + "macup-conf-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir + "/.config/macup", withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(atPath: dir) }

    var confPath: String { dir + "/.config/macup/config" }

    let configs = [
        "language = uk\nskip = check.docker, clean.*\nenable=clean.trash # opt in\n",
        "  skip=update.brew\nskip = update.mas  # later wins\nkeep_reports = 15\nsimulator_days = 0\nstep_timeout_minutes = x\n",
        "skip = a\nskip = # emptied\nlanguage\t=\tru\t\r\nclean_level = aggressive\nproject_dirs = ~/A, ~/B\n",
        "skipper = no\nlanguage = -n\nenable = clean.trash,clean.sim_erase\nonly = check.disk\n",
        "skip = clean.brew\u{A0}\nenable = clean.trash\u{3000} # ideographic space\nlanguage\u{2003}= uk\nproject_dirs = a\u{85}\nstep_timeout_minutes = 010\n",
        "step_timeout_minutes = 09\n",
        "",
    ]
    let keys = ["language", "skip", "enable", "keep_reports", "simulator_days", "step_timeout_minutes", "clean_level", "project_dirs", "skipper", "only", "absent"]

    func testConfAgainstBash() throws {
        for text in configs {
            try text.write(toFile: confPath, atomically: true, encoding: .utf8)
            let config = Config(path: confPath)
            let got = try BashOracle.run(keys.map { "conf \($0) dflt" }, home: dir)
            for (index, key) in keys.enumerated() { XCTAssertEqual(config.value(key, "dflt"), got[index], "conf \(key) in \(text.debugDescription)") }
        }
        XCTAssertEqual(Config(path: dir + "/none").value("skip", "x"), "x")
        XCTAssertEqual(Config(path: dir).value("skip", "x"), "x", "a folder is not a config file")
    }

    /// sed stops at the first line that is not UTF-8: keys after it are not read, and conf_set leaves such a file alone.
    func testInvalidUTF8StopsLikeSed() throws {
        let bytes = Data("language = ru\n# caf".utf8) + Data([0xE9]) + Data("\nskip = clean.*\n".utf8)
        try bytes.write(to: URL(fileURLWithPath: confPath))
        var config = Config(path: confPath)
        config.reportsErrors = false
        let got = try BashOracle.run(["conf language x", "conf skip none"], home: dir)
        XCTAssertTrue(config.sedFails)
        XCTAssertEqual([config.value("language", "x"), config.value("skip", "none")], got)
        var latin = Config(path: confPath, utf8: false)
        latin.reportsErrors = false
        XCTAssertEqual(latin.value("skip", "none"), "clean.*", "LC_ALL=C: sed reads every byte")
        try Config.set("language", "uk", path: confPath) { "" }
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: confPath)), bytes)
    }

    func testNumAndLevel() {
        XCTAssertEqual(Config.num("", "90"), "90")
        XCTAssertEqual(Config.num("0", "90"), "90")
        XCTAssertEqual(Config.num("12a", "90"), "90")
        XCTAssertEqual(Config.num("007", "90"), "007")
        XCTAssertEqual(Config.num("45", 90), 45)
        XCTAssertEqual(Config.level("standard"), 2)
        XCTAssertEqual(Config.level("3"), 3)
        XCTAssertNil(Config.level("huge"))
    }

    func testConfSetAgainstBash() throws {
        for (key, value) in [("language", "ru"), ("skip", "a&b"), ("newkey", "v")] {
            for text in configs + [nil] {
                // bash
                try? FileManager.default.removeItem(atPath: confPath)
                if let text { try text.write(toFile: confPath, atomically: true, encoding: .utf8) }
                let prelude = "write_default_conf(){ mkdir -p \"$CONF_DIR\"; printf 'language = en\\n' >\"$CONF\"; }"
                _ = try BashOracle.run(["conf_set \(key) \(BashOracle.quoted(value))"], home: dir, prelude: prelude)
                let want = try String(contentsOfFile: confPath, encoding: .utf8)
                // swift
                try? FileManager.default.removeItem(atPath: confPath)
                if let text { try text.write(toFile: confPath, atomically: true, encoding: .utf8) }
                try Config.set(key, value, path: confPath) { "language = en\n" }
                XCTAssertEqual(try String(contentsOfFile: confPath, encoding: .utf8), want, "conf_set \(key) in \(text.debugDescription)")
            }
        }
    }

    func testDefaultConfigIsTheBashTemplate() throws {
        _ = try BashOracle.run(["write_default_conf"], home: dir, prelude: "MSG_LANG=uk\n" + BashOracle.function("write_default_conf", in: "src/commands.sh"))
        XCTAssertEqual(Config.defaultText(lang: .uk), try String(contentsOfFile: confPath, encoding: .utf8))
    }

    func testTaskTableIsCoreSh() {
        let core = BashOracle.read("src/core.sh")
        let start = core.range(of: "TASKS='")!.upperBound
        let table = core[start..<core[start...].firstIndex(of: "'")!]
        let rows = table.split(separator: "\n").map { $0.split(separator: "|", maxSplits: 2).map(String.init) }
        XCTAssertEqual(rows.count, Tasks.all.count)
        for (row, task) in zip(rows, Tasks.all) { XCTAssertEqual(row, [task.id, task.on ? "on" : "off", task.text]) }
    }

    func testSelectionAgainstBash() throws {
        let clis: [(skip: String, only: String, enable: String)] = [
            ("", "", ""), (",update.*", "", ""), ("", ",check.*", ""), ("", ",check.disk, clean.trash", ",clean.trash"),
            (",clean.trash", ",clean.*", ",clean.trash,clean.sim_erase"), ("", "clean.*", ""), (", check.disk ,", "", ",update.gem"),
        ]
        let env = try Env(["HOME": dir])
        for text in configs {
            try text.write(toFile: confPath, atomically: true, encoding: .utf8)
            for cli in clis {
                let settings = Settings(config: Config(path: confPath), env: env, cliSkip: cli.skip, cliOnly: cli.only, cliEnable: cli.enable, cliLevel: nil)
                let sel = Selection(settings)
                let prelude = "CLI_SKIP=\(BashOracle.quoted(cli.skip)); CLI_ONLY=\(BashOracle.quoted(cli.only)); CLI_ENABLE=\(BashOracle.quoted(cli.enable)); load_conf"
                let calls = Tasks.all.map { "if task \($0.id); then echo 1; else echo 0; fi" } + ["printf %s \"$SKIP|$ENABLE|$CLI_ONLY|$LEVEL|$KEEP_RUNS|$STEP_SECS|$SIM_DAYS\""]
                let got = try BashOracle.run(calls, home: dir, prelude: prelude)
                for (index, task) in Tasks.all.enumerated() { XCTAssertEqual(sel.runs(task.id) ? "1" : "0", got[index], "task \(task.id) with \(cli) in \(text.debugDescription)") }
                // leading zeros are decimal (intended difference): bash read 010 as octal 8 minutes and gave up on 09 halfway through load_conf
                if text.contains("step_timeout_minutes = 0") { XCTAssertEqual(settings.stepSeconds, text.contains("= 09") ? 540 : 600, text); continue }
                XCTAssertEqual("\(settings.skip)|\(settings.enable)|\(settings.only)|\(settings.level)|\(settings.keepReports)|\(settings.stepSeconds)|\(settings.simulatorDays)", got.last, "load_conf")
            }
        }
    }

    func testUnknownTasksAgainstBash() throws {
        let lists = [",chek.disk", ",check.*,clean.nope, update.brew ", ",,,", "a,b,c", ",clean.*,update.*", ",check.disk,check.tyme_machine",
                     ",check\\.disk,check\\.d\\isk", "x\\", "a\nb,check.*"]
        let prelude = BashOracle.function("unknown_tasks", in: "src/arguments.sh")
        let got = try BashOracle.run(lists.map { "unknown_tasks \(BashOracle.quoted($0))" }, prelude: prelude)
        for (index, list) in lists.enumerated() { XCTAssertEqual(Tasks.unknown(list), got[index], "unknown_tasks \(list)") }
    }
}

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

    /// What `conf key dflt` gives for each of `configs`, as 2.9's bash did; a key not listed gives "dflt".
    func testConf() throws {
        let expected: [[String: String]] = [
            ["language": "uk", "skip": "check.docker, clean.*", "enable": "clean.trash"],
            ["skip": "update.mas", "keep_reports": "15", "simulator_days": "0", "step_timeout_minutes": "x"],
            ["language": "ru", "clean_level": "aggressive", "project_dirs": "~/A, ~/B"],
            ["language": "", "enable": "clean.trash,clean.sim_erase", "skipper": "no", "only": "check.disk"],
            ["language": "uk", "skip": "clean.brew", "enable": "clean.trash", "step_timeout_minutes": "010", "project_dirs": "a\u{85}"],
            ["step_timeout_minutes": "09"],
            [:],
        ]
        for (text, values) in zip(configs, expected) {
            try text.write(toFile: confPath, atomically: true, encoding: .utf8)
            let config = Config(path: confPath)
            for key in keys { XCTAssertEqual(config.value(key, "dflt"), values[key] ?? "dflt", "conf \(key) in \(text.debugDescription)") }
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
        XCTAssertTrue(config.sedFails)
        XCTAssertEqual([config.value("language", "x"), config.value("skip", "none")], ["ru", "none"])
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

    /// The file conf_set leaves, as 2.9's bash (sed) did: every line of the key replaced, & as sed's whole match,
    /// a missing key appended, a missing file made from the default first.
    func testConfSet() throws {
        let cases: [(key: String, value: String, config: String?, want: String)] = [
            ("language", "ru", configs[0], "language = ru\nskip = check.docker, clean.*\nenable=clean.trash # opt in\n"),
            ("language", "ru", configs[1], "  skip=update.brew\nskip = update.mas  # later wins\nkeep_reports = 15\nsimulator_days = 0\nstep_timeout_minutes = x\nlanguage = ru\n"),
            ("language", "ru", configs[2], "skip = a\nskip = # emptied\nlanguage = ru\nclean_level = aggressive\nproject_dirs = ~/A, ~/B\n"),
            ("language", "ru", configs[4], "skip = clean.brew\u{A0}\nenable = clean.trash\u{3000} # ideographic space\nlanguage = ru\nproject_dirs = a\u{85}\nstep_timeout_minutes = 010\n"),
            ("language", "ru", configs[6], "language = ru\n"),
            ("language", "ru", nil, "language = ru\n"),
            ("skip", "a&b", configs[0], "language = uk\nskip = askip = check.docker, clean.*b\nenable=clean.trash # opt in\n"),
            ("skip", "a&b", configs[1], "skip = a  skip=update.brewb\nskip = askip = update.mas  # later winsb\nkeep_reports = 15\nsimulator_days = 0\nstep_timeout_minutes = x\n"),
            ("skip", "a&b", configs[2], "skip = askip = ab\nskip = askip = # emptiedb\nlanguage\t=\tru\t\r\nclean_level = aggressive\nproject_dirs = ~/A, ~/B\n"),
            ("skip", "a&b", configs[3], "skipper = no\nlanguage = -n\nenable = clean.trash,clean.sim_erase\nonly = check.disk\nskip = a&b\n"),
            ("skip", "a&b", nil, "language = en\nskip = a&b\n"),
            ("newkey", "v", configs[2], "skip = a\nskip = # emptied\nlanguage\t=\tru\t\r\nclean_level = aggressive\nproject_dirs = ~/A, ~/B\nnewkey = v\n"),
            ("newkey", "v", nil, "language = en\nnewkey = v\n"),
        ]
        for example in cases {
            try? FileManager.default.removeItem(atPath: confPath)
            if let text = example.config { try text.write(toFile: confPath, atomically: true, encoding: .utf8) }
            try Config.set(example.key, example.value, path: confPath) { "language = en\n" }
            XCTAssertEqual(try String(contentsOfFile: confPath, encoding: .utf8), example.want, "conf_set \(example.key) in \(example.config.debugDescription)")
        }
    }

    /// The config write_default_conf of 2.9 wrote for MSG_LANG=uk.
    func testDefaultConfigIsTheBashTemplate() {
        XCTAssertEqual(Config.defaultText(lang: .uk), Checkout.fixture("ConfigTasksTests-default-config-uk.txt"))
    }

    /// The TASKS table of 2.9's core.sh: id|on or off|text.
    func testTaskTableIsCoreSh() {
        let rows = Checkout.fixture("ConfigTasksTests-tasks.txt").split(separator: "\n").map { $0.split(separator: "|", maxSplits: 2).map(String.init) }
        XCTAssertEqual(rows.count, Tasks.all.count)
        for (row, task) in zip(rows, Tasks.all) { XCTAssertEqual(row, [task.id, task.on ? "on" : "off", task.text]) }
    }

    /// Which tasks of each group run: "none", "default" (as Tasks.all has them on), the default with ids added (+)
    /// and removed (-), or the ids that run, whichever is shorter.
    func runs(_ selection: Selection) -> String {
        ["check", "update", "clean"].map { group in
            let tasks = Tasks.all.filter { $0.id.hasPrefix(group + ".") }
            let name = { (id: String) in String(id.dropFirst(group.count + 1)) }
            let running = tasks.filter { selection.runs($0.id) }.map { name($0.id) }
            let changes = tasks.filter { selection.runs($0.id) != $0.on }.map { (selection.runs($0.id) ? "+" : "-") + name($0.id) }
            let text = running.isEmpty ? "none" : changes.isEmpty ? "default"
                : changes.count < running.count ? "default " + changes.joined(separator: " ") : running.joined(separator: ", ")
            return "\(group): \(text)"
        }.joined(separator: "; ")
    }

    /// The tasks that run and load_conf's settings (skip|enable|only|level|keep|step seconds|simulator days), as 2.9's bash had them.
    func testSelection() throws {
        let cases: [(config: String, skip: String, only: String, enable: String, runs: String, settings: String)] = [
            (configs[0], "", "", "", "check: default -docker; update: default; clean: none", ",check.docker,clean.*,,|,clean.trash,,||1|20|3600|30"),
            (configs[0], ", check.disk ,", "", ",update.gem", "check: default -disk -docker; update: default +gem; clean: none", ",check.docker,clean.*,,check.disk,,|,clean.trash,,update.gem,||1|20|3600|30"),
            (configs[1], "", "", "", "check: default; update: default -mas; clean: default", ",update.mas,,|,,,||1|15|3600|30"),
            (configs[1], "", ",check.disk, clean.trash", ",clean.trash", "check: disk; update: none; clean: trash", ",update.mas,,|,,,clean.trash,|,check.disk,clean.trash|1|15|3600|30"),
            (configs[2], "", "", "", "check: default; update: default; clean: default", ",,,|,,,||3|20|3600|30"),
            (configs[2], "", ",check.*", "", "check: default; update: none; clean: none", ",,,|,,,|,check.*|3|20|3600|30"),
            (configs[3], "", "", "", "check: default; update: default; clean: default +sim_erase +trash", ",,,|,clean.trash,clean.sim_erase,,||1|20|3600|30"),
            (configs[3], ",clean.trash", ",clean.*", ",clean.trash,clean.sim_erase", "check: none; update: none; clean: default +sim_erase",
             ",,,clean.trash,|,clean.trash,clean.sim_erase,,clean.trash,clean.sim_erase,|,clean.*|1|20|3600|30"),
            // leading zeros are decimal (intended difference): bash read 010 as octal 8 minutes and gave up on 09 halfway through load_conf
            (configs[4], "", "", "", "check: default; update: default; clean: default -brew +trash", ",clean.brew,,|,clean.trash,,||1|20|600|30"),
            (configs[5], "", "", "", "check: default; update: default; clean: default", ",,,|,,,||1|20|540|30"),
            (configs[5], "", "clean.*", "", "check: none; update: none; clean: default", ",,,|,,,|clean.*|1|20|540|30"),
            (configs[6], "", "", "", "check: default; update: default; clean: default", ",,,|,,,||1|20|3600|30"),
            (configs[6], ",update.*", "", "", "check: default; update: none; clean: default", ",,,update.*,|,,,||1|20|3600|30"),
            (configs[6], ", check.disk ,", "", ",update.gem", "check: default -disk; update: default +gem; clean: default", ",,,check.disk,,|,,,update.gem,||1|20|3600|30"),
        ]
        let env = try Env(["HOME": dir])
        for example in cases {
            try example.config.write(toFile: confPath, atomically: true, encoding: .utf8)
            let settings = Settings(config: Config(path: confPath), env: env, cliSkip: example.skip, cliOnly: example.only, cliEnable: example.enable, cliLevel: nil)
            let context = "skip \(example.skip.debugDescription) only \(example.only.debugDescription) in \(example.config.debugDescription)"
            XCTAssertEqual(runs(Selection(settings)), example.runs, context)
            XCTAssertEqual("\(settings.skip)|\(settings.enable)|\(settings.only)|\(settings.level)|\(settings.keepReports)|\(settings.stepSeconds)|\(settings.simulatorDays)",
                           example.settings, context)
        }
    }

    func testUnknownTasks() {
        let cases = [(",chek.disk", "chek.disk"), (",check.*,clean.nope, update.brew ", "clean.nope,  update.brew "), (",,,", ""), ("a,b,c", "a, b, c"),
                     (",clean.*,update.*", ""), (",check.disk,check.tyme_machine", "check.tyme_machine"), (",check\\.disk,check\\.d\\isk", ""),
                     ("x\\", "x\\"), ("a\nb,check.*", "a, b")]
        for (list, unknown) in cases { XCTAssertEqual(Tasks.unknown(list), unknown, "unknown_tasks \(list)") }
    }
}

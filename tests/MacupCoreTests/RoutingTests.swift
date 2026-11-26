@testable import MacupCore
@testable import macup
import XCTest

final class RoutingTests: XCTestCase {
    func env(_ extra: [String: String] = [:]) throws -> Env {
        var vars = ["HOME": NSTemporaryDirectory() + "macup-none-\(UUID().uuidString)", "PATH": "/usr/bin:/bin"]
        for (key, value) in extra { vars[key] = value }
        return try Env(vars)
    }

    func testParseMirrorsArgumentsSh() throws {
        var arguments = try Arguments.parse(["check", "--skip", "a", "--skip=b", "--only", "c", "--lang", "ua", "--no-color", "tasks"])
        XCTAssertEqual(arguments.command, .tasks)
        XCTAssertEqual(arguments.action, "check")
        XCTAssertTrue(arguments.dry)
        XCTAssertEqual(arguments.cliSkip, ",a,b")
        XCTAssertEqual(arguments.cliOnly, ",c")
        XCTAssertEqual(arguments.lang, .uk)
        XCTAssertTrue(arguments.noColor)

        arguments = try Arguments.parse(["schedule", "weekly", "lang", "--json", "reports", "clean", "help", "version"])
        XCTAssertEqual(arguments.command, .version, "the last command word wins")
        XCTAssertEqual(arguments.schedArg, "weekly")
        XCTAssertEqual(arguments.langArg, "", "lang takes no option as its word")
        XCTAssertEqual(arguments.repArg, "clean")
        XCTAssertTrue(arguments.json && arguments.quiet)

        arguments = try Arguments.parse(["--skip"])
        XCTAssertEqual(arguments.cliSkip, ",", "an option at the end takes an empty value")

        arguments = try Arguments.parse(["tasks", "--pick", "k1, k2"])
        XCTAssertEqual(arguments.pick, ",,k1,k2,")
        XCTAssertEqual(arguments.cliOnly, "clean.*")
        XCTAssertEqual(arguments.action, "clean")
        XCTAssertFalse(arguments.dry || arguments.doUpdate)

        XCTAssertThrowsError(try Arguments.parse(["--level", "huge", "help"]))
        XCTAssertThrowsError(try Arguments.parse(["--lang"]))
        XCTAssertThrowsError(try Arguments.parse(["help", "bogus"])) { XCTAssertEqual($0 as? Arguments.Failure, .unknownCommand("bogus")) }
        XCTAssertEqual(try Arguments.parse(["--level=aggressive"]).level, 3)
        XCTAssertTrue(try Arguments.parse(["--deep"]).dry)
        XCTAssertFalse(try Arguments.parse(["update", "--deep"]).dry)
    }

    func testRoutes() throws {
        let environment = try env()
        func route(_ line: String) -> String {
            switch Router.route(line.split(separator: " ").map(String.init), env: environment) {
            case .bash: return "bash"
            case .swift(let arguments): return arguments.command?.rawValue ?? "run"
            }
        }
        XCTAssertEqual(route("help"), "help")
        XCTAssertEqual(route("help --lang ru --no-color"), "help")
        XCTAssertEqual(route("version"), "version")
        XCTAssertEqual(route("-v"), "version")
        XCTAssertEqual(route("tasks --json"), "tasks")
        XCTAssertEqual(route("check tasks"), "tasks", "a one-off command runs before the check")
        XCTAssertEqual(route("self-update"), "self_update")
        XCTAssertEqual(route("schedule weekly"), "schedule")
        XCTAssertEqual(route("check --only check.disk"), "run")
        XCTAssertEqual(route("check --only check.self_update"), "run")
        for command in ["last", "history --json", "reports", "config", "lang uk", "uninstall --yes"] {
            XCTAssertEqual(route(command), String(command.split(separator: " ")[0]), "'\(command)' runs in Swift")
        }
        XCTAssertEqual(route(""), "run", "the menu, or the help without a terminal")
        XCTAssertEqual(route("all --only check.disk,update.brew,clean.derived_data --json"), "run")
        for line in ["check", "all --only clean.trash", "--deep", "clean --deep --only clean.trash", "clean --pick clean.derived_data:1",
                  "help bogus", "--lang xx help", "--level huge tasks", "bogus"] {
            XCTAssertEqual(route(line), "bash", "'\(line)' goes to the bash build")
        }
    }

    func testConfigBashCannotComputeGoesToBash() throws {
        let environment = try env()
        try FileManager.default.createDirectory(atPath: environment.confDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: environment.home) }
        try "step_timeout_minutes = 09\n".write(toFile: environment.conf, atomically: true, encoding: .utf8)
        XCTAssertEqual(Router.route(["tasks"], env: environment), .bash)
        XCTAssertNotEqual(Router.route(["help"], env: environment), .bash)
        try "step_timeout_minutes = 010\n".write(toFile: environment.conf, atomically: true, encoding: .utf8)
        XCTAssertNotEqual(Router.route(["tasks"], env: environment), .bash)
    }

    func testRunsRouteOnlyWhenEveryTaskIsPorted() throws {
        let environment = try env()
        let ported: Set<String> = ["run", "help"]
        func route(_ argv: [String], _ tasks: Set<String>) -> Bool {
            if case .swift = Router.route(argv, env: environment, ported: ported, portedTasks: tasks) { return true }
            return false
        }
        XCTAssertTrue(route(["check", "--only", "check.disk"], ["check.disk"]))
        XCTAssertFalse(route(["check", "--only", "check.disk,check.memory"], ["check.disk"]))
        XCTAssertFalse(route(["check", "--only", "chek.disk"], ["check.disk"]), "an unknown id goes to bash, which says so")
        XCTAssertFalse(route(["check"], ["check.disk"]))
        XCTAssertFalse(route(["check"], Set(Tasks.all.filter(\.on).map(\.id))), "opt-in tasks register what they find too")
        XCTAssertTrue(route(["check"], Set(Tasks.all.map(\.id))), "a full check once every task is ported")
        XCTAssertFalse(route([], Set(Tasks.all.map(\.id))), "no command: the menu or the help, still bash")
    }

    func testRunsThatReachUnportedCodeGoToBash() throws {
        let environment = try env()
        let ported: Set<String> = ["run"], tasks: Set<String> = ["check.disk", "clean.derived_data"]
        func swift(_ line: String, terminal: Bool = false, commands: Set<String> = ported, dryTasks: Set<String> = []) -> Bool {
            let route = Router.route(line.split(separator: " ").map(String.init), env: environment, ported: commands, portedTasks: tasks,
                                     dryTasks: dryTasks, terminal: terminal)
            if case .swift = route { return true }
            return false
        }
        XCTAssertFalse(swift("check --only clean.derived_data,clean.trash"), "an opt-in task off by default still registers what it finds")
        XCTAssertTrue(swift("check --only clean.derived_data"))
        XCTAssertFalse(swift("check --only clean.derived_data", terminal: true), "the pick at the end of a check")
        XCTAssertTrue(swift("check --only clean.derived_data --quiet", terminal: true))
        XCTAssertTrue(swift("check --only check.disk", terminal: true), "no cleanup, no pick")
        XCTAssertTrue(swift("clean --only clean.derived_data", terminal: true))
        XCTAssertTrue(swift("check --only clean.derived_data", terminal: true, commands: ["run", "pick"]))
        XCTAssertFalse(swift("--deep --only check.disk"))
        XCTAssertTrue(swift("--deep --only check.disk", commands: ["run", "deep"]))
        XCTAssertFalse(swift("clean --pick clean.derived_data:1 --only clean.derived_data"))
        XCTAssertTrue(swift("check --only clean.spm", dryTasks: ["clean.spm"]), "registered in Swift, listed by a check")
        XCTAssertFalse(swift("clean --only clean.spm", dryTasks: ["clean.spm"]), "but not cleaned by it yet")
    }

    func testEnvironment() throws {
        XCTAssertThrowsError(try Env(["HOME": ""]))
        XCTAssertThrowsError(try Env(["HOME": "/"]))
        XCTAssertThrowsError(try Env(["HOME": "relative"]))
        var environment = try Env(["HOME": "/h", "PATH": "/usr/bin"])
        XCTAssertEqual(environment.path, "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/h/.local/bin:/h/.npm-global/bin:/h/.cargo/bin:/usr/bin")
        XCTAssertEqual(environment.userPath, "/usr/bin")
        XCTAssertEqual(environment.conf, "/h/.config/macup/config")
        XCTAssertEqual(environment.lcCtype, "en_US.UTF-8")
        XCTAssertEqual(environment.apps, "/Applications:/h/Applications")
        XCTAssertEqual(environment.raw, "https://raw.githubusercontent.com/VitaliiDeveloper/macup")
        environment = try Env(["HOME": "/h", "PATH": "/x", "MACUP_PATH": "keep", "XDG_CONFIG_HOME": "/xdg", "LANG": "uk_UA.UTF-8", "MACUP_REPO": "me/fork",
                     "NO_COLOR": "", "MACUP_LANG": "", "TMPDIR": "/t/"])
        XCTAssertEqual(environment.path, "/x")
        XCTAssertEqual(environment.conf, "/xdg/macup/config")
        XCTAssertNil(environment.lcCtype)
        XCTAssertEqual(environment.repo, "me/fork")
        XCTAssertFalse(environment.noColor, "an empty NO_COLOR is no NO_COLOR")
        XCTAssertNil(environment.langHook)
        XCTAssertEqual(environment.tmpDir, "/t/")
    }

    func testHelpIsUsage() throws {
        for lang in Lang.allCases {
            for (colors, colorPrelude) in [(Colors.off, "B=; N="), (Colors.on, "B=$'\\033[1m'; N=$'\\033[0m'")] {
                let prelude = "MACUP_VERSION=\(Env.version); MSG_LANG=\(lang.rawValue); \(colorPrelude)\n" + BashOracle.read("src/help.sh")
                let got = try BashOracle.run(["usage; printf x"], home: "/Users/h.x", prelude: prelude)
                XCTAssertEqual(Help.text(lang: lang, colors: colors, conf: "~/.config/macup/config") + "x", got[0], "help \(lang)")
            }
        }
    }

    func testVersionIsCoreSh() {
        XCTAssertTrue(BashOracle.read("src/core.sh").contains("\nMACUP_VERSION=\"\(Env.version)\"\n"))
    }

    /// The binary carries exactly the bash build next to it and the translations.
    func testGeneratedSourcesAreCurrent() {
        XCTAssertEqual(LegacyScript.text, BashOracle.read("macup"), "run ./build.sh")
        XCTAssertEqual(Translations.json, BashOracle.read("src/i18n/translations.json"), "run ./build.sh")
    }
}

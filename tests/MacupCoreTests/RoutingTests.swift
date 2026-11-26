@testable import MacupCore
@testable import macup
import XCTest

final class RoutingTests: XCTestCase {
    func env(_ extra: [String: String] = [:]) throws -> Env {
        var v = ["HOME": NSTemporaryDirectory() + "macup-none-\(UUID().uuidString)", "PATH": "/usr/bin:/bin"]
        for (k, x) in extra { v[k] = x }
        return try Env(v)
    }

    func testParseMirrorsArgumentsSh() throws {
        var a = try Arguments.parse(["check", "--skip", "a", "--skip=b", "--only", "c", "--lang", "ua", "--no-color", "tasks"])
        XCTAssertEqual(a.command, .tasks)
        XCTAssertEqual(a.action, "check")
        XCTAssertTrue(a.dry)
        XCTAssertEqual(a.cliSkip, ",a,b")
        XCTAssertEqual(a.cliOnly, ",c")
        XCTAssertEqual(a.lang, .uk)
        XCTAssertTrue(a.noColor)

        a = try Arguments.parse(["schedule", "weekly", "lang", "--json", "reports", "clean", "help", "version"])
        XCTAssertEqual(a.command, .version, "the last command word wins")
        XCTAssertEqual(a.schedArg, "weekly")
        XCTAssertEqual(a.langArg, "", "lang takes no option as its word")
        XCTAssertEqual(a.repArg, "clean")
        XCTAssertTrue(a.json && a.quiet)

        a = try Arguments.parse(["--skip"])
        XCTAssertEqual(a.cliSkip, ",", "an option at the end takes an empty value")

        a = try Arguments.parse(["tasks", "--pick", "k1, k2"])
        XCTAssertEqual(a.pick, ",,k1,k2,")
        XCTAssertEqual(a.cliOnly, "clean.*")
        XCTAssertEqual(a.action, "clean")
        XCTAssertFalse(a.dry || a.doUpdate)

        XCTAssertThrowsError(try Arguments.parse(["--level", "huge", "help"]))
        XCTAssertThrowsError(try Arguments.parse(["--lang"]))
        XCTAssertThrowsError(try Arguments.parse(["help", "bogus"])) { XCTAssertEqual($0 as? Arguments.Failure, .unknownCommand("bogus")) }
        XCTAssertEqual(try Arguments.parse(["--level=aggressive"]).level, 3)
    }

    func testRoutes() throws {
        let e = try env()
        func route(_ a: String) -> String {
            switch Router.route(a.split(separator: " ").map(String.init), env: e) {
            case .bash: return "bash"
            case .swift(let x): return x.command?.rawValue ?? "run"
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
        for a in ["", "check", "all --only check.disk", "--deep", "last", "history --json", "reports", "config", "lang uk", "uninstall --yes",
                  "help bogus", "--lang xx help", "--level huge tasks", "bogus"] {
            XCTAssertEqual(route(a), "bash", "'\(a)' goes to the bash build")
        }
    }

    func testConfigBashCannotComputeGoesToBash() throws {
        let e = try env()
        try FileManager.default.createDirectory(atPath: e.confDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: e.home) }
        try "step_timeout_minutes = 09\n".write(toFile: e.conf, atomically: true, encoding: .utf8)
        XCTAssertEqual(Router.route(["tasks"], env: e), .bash)
        XCTAssertNotEqual(Router.route(["help"], env: e), .bash)
        try "step_timeout_minutes = 010\n".write(toFile: e.conf, atomically: true, encoding: .utf8)
        XCTAssertNotEqual(Router.route(["tasks"], env: e), .bash)
    }

    func testRunsRouteOnlyWhenEveryTaskIsPorted() throws {
        let e = try env()
        let ported: Set<String> = ["run", "help"]
        func route(_ a: [String], _ tasks: Set<String>) -> Bool {
            if case .swift = Router.route(a, env: e, ported: ported, portedTasks: tasks) { return true }
            return false
        }
        XCTAssertTrue(route(["check", "--only", "check.disk"], ["check.disk"]))
        XCTAssertFalse(route(["check", "--only", "check.disk,check.memory"], ["check.disk"]))
        XCTAssertFalse(route(["check", "--only", "chek.disk"], ["check.disk"]), "an unknown id goes to bash, which says so")
        XCTAssertFalse(route(["check"], ["check.disk"]))
        XCTAssertTrue(route(["check"], Set(Tasks.all.filter(\.on).map(\.id))), "a full check once every default task is ported")
        XCTAssertFalse(route([], Set(Tasks.all.map(\.id))), "no command: the menu or the help, still bash")
    }

    func testEnvironment() throws {
        XCTAssertThrowsError(try Env(["HOME": ""]))
        XCTAssertThrowsError(try Env(["HOME": "/"]))
        XCTAssertThrowsError(try Env(["HOME": "relative"]))
        var e = try Env(["HOME": "/h", "PATH": "/usr/bin"])
        XCTAssertEqual(e.path, "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/h/.local/bin:/h/.npm-global/bin:/h/.cargo/bin:/usr/bin")
        XCTAssertEqual(e.userPath, "/usr/bin")
        XCTAssertEqual(e.conf, "/h/.config/macup/config")
        XCTAssertEqual(e.lcCtype, "en_US.UTF-8")
        XCTAssertEqual(e.apps, "/Applications:/h/Applications")
        XCTAssertEqual(e.raw, "https://raw.githubusercontent.com/VitaliiDeveloper/macup")
        e = try Env(["HOME": "/h", "PATH": "/x", "MACUP_PATH": "keep", "XDG_CONFIG_HOME": "/xdg", "LANG": "uk_UA.UTF-8", "MACUP_REPO": "me/fork",
                     "NO_COLOR": "", "MACUP_LANG": "", "TMPDIR": "/t/"])
        XCTAssertEqual(e.path, "/x")
        XCTAssertEqual(e.conf, "/xdg/macup/config")
        XCTAssertNil(e.lcCtype)
        XCTAssertEqual(e.repo, "me/fork")
        XCTAssertFalse(e.noColor, "an empty NO_COLOR is no NO_COLOR")
        XCTAssertNil(e.langHook)
        XCTAssertEqual(e.tmpDir, "/t/")
    }

    func testHelpIsUsage() throws {
        for lang in Lang.allCases {
            for (colors, c) in [(Colors.off, "B=; N="), (Colors.on, "B=$'\\033[1m'; N=$'\\033[0m'")] {
                let prelude = "MACUP_VERSION=\(Env.version); MSG_LANG=\(lang.rawValue); \(c)\n" + BashOracle.read("src/help.sh")
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

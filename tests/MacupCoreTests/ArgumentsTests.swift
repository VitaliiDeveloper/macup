@testable import MacupCore
@testable import macup
import XCTest

final class ArgumentsTests: XCTestCase {
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
        XCTAssertThrowsError(try Arguments.parse(["help", "bogus"])) { XCTAssertEqual($0 as? Arguments.Failure, .unknownCommand("bogus", lang: nil)) }
        XCTAssertThrowsError(try Arguments.parse(["--lang", "uk", "bogus", "--lang", "ru"])) { XCTAssertEqual($0 as? Arguments.Failure, .unknownCommand("bogus", lang: .uk)) }
        XCTAssertEqual(try Arguments.parse(["--level=aggressive"]).level, 3)
        XCTAssertTrue(try Arguments.parse(["--deep"]).dry)
        XCTAssertFalse(try Arguments.parse(["update", "--deep"]).dry)
    }

    /// What each command line asks for: a one-off command, a run, or arguments.sh's rejection.
    func testCommandLines() throws {
        func asked(_ line: String) -> String {
            do {
                let arguments = try Arguments.parse(line.split(separator: " ").map(String.init))
                return arguments.command?.rawValue ?? (arguments.action ?? (arguments.deep ? "deep" : "menu"))
            } catch { return "rejected" }
        }
        XCTAssertEqual(asked("help --lang ru --no-color"), "help")
        XCTAssertEqual(asked("-v"), "version")
        XCTAssertEqual(asked("tasks --json"), "tasks")
        XCTAssertEqual(asked("check tasks"), "tasks", "a one-off command runs before the check")
        XCTAssertEqual(asked("self-update"), "self_update")
        XCTAssertEqual(asked("schedule weekly"), "schedule")
        for command in ["last", "history --json", "reports", "config", "lang uk", "uninstall --yes"] {
            XCTAssertEqual(asked(command), String(command.split(separator: " ")[0]))
        }
        XCTAssertEqual(asked(""), "menu", "the menu, or the help without a terminal")
        XCTAssertEqual(asked("all --only check.disk,update.brew,clean.derived_data --json"), "all")
        XCTAssertEqual(asked("--deep"), "deep")
        XCTAssertEqual(asked("clean --pick clean.derived_data:1"), "clean")
        XCTAssertEqual(asked("check --pick clean.derived_data:1"), "clean", "--pick cleans and checks nothing")
        for line in ["help bogus", "--lang xx help", "--level huge tasks", "bogus"] { XCTAssertEqual(asked(line), "rejected", line) }
        XCTAssertEqual(asked("check --only chek.disk"), "check", "an unknown id: the run says so")
    }

    /// step_timeout_minutes with leading zeros is decimal: bash read 010 as octal 8 and gave up on 09 (intended difference).
    func testLeadingZerosAreDecimal() throws {
        let environment = try env()
        try FileManager.default.createDirectory(atPath: environment.confDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: environment.home) }
        for (text, seconds) in [("09", 540), ("010", 600), ("0008", 480), ("10", 600), ("0", 3600), ("x9", 3600)] {
            try "step_timeout_minutes = \(text)\n".write(toFile: environment.conf, atomically: true, encoding: .utf8)
            let settings = Settings(config: Config(env: environment), env: environment, cliSkip: "", cliOnly: "", cliEnable: "", cliLevel: nil)
            XCTAssertEqual(settings.stepSeconds, seconds, text)
        }
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

    /// The binary carries the translations; it carries no bash build.
    func testGeneratedSourcesAreCurrent() {
        XCTAssertEqual(Translations.json, BashOracle.read("src/i18n/translations.json"), "run ./build.sh")
    }
}

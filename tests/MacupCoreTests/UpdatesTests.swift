@testable import MacupCore
import XCTest

/// The updaters' parsing against what the bash build runs today: macup_helpers.py for the JSON, bash and sed for the rest.
final class UpdatesTests: XCTestCase {
    var home = ""

    override func setUpWithError() throws {
        home = (NSTemporaryDirectory() as NSString).resolvingSymlinksInPath + "/macup-updates-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: home + "/bin", withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(atPath: home) }

    /// macup_helpers.py `command args…` with this input: what it prints (as `$(…)` keeps it) and whether it ended well.
    func python(_ command: String, _ arguments: [String], input: String = "") throws -> (output: String, ok: Bool) {
        try BashOracle.python(command, arguments, input: input, home: home)
    }

    func write(_ text: String, _ name: String) throws -> String {
        let path = "\(home)/\(name)"
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try text.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    func testPluginsAsPythonReadsThem() throws {
        let cases = [
            #"{"version":2,"plugins":{"zeta@m":[{"scope":"project","version":"1.0.0"},{"scope":"user","version":"1.2.0"}],"alpha@m":[{"gitCommitSha":"abcdef1234567"}],"Beta@m":{"version":"0.9"},"local@m":[{"scope":"local","version":"3"}]}}"#,
            #"{"b":{"version":2},"a":{"version":1.50},"c":{"version":true},"d":{"version":"","gitCommitSha":""},"e":[{"scope":null}]}"#,
            #"{"plugins":{"a":{"version":"1"},"b":{"gitCommitSha":12345678},"c":{"version":"3"}}}"#,
            #"{"plugins":{"é":{"version":"1"},"e\u0301":{"version":"2"},"z":{"version":"3"},"Z":{"version":"4"},"😀":{"version":"5"}}}"#,
            #"{"plugins":{"dup":{"version":"1"},"other":{"version":"2"},"dup":{"version":"3"}}}"#,
            #"{"plugins":[]}"#, #"[]"#, #"{"plugins":{"a":{"version":"1"}}"#, "not json",
        ]
        for json in cases {
            let path = try write(json, "installed_plugins.json")
            XCTAssertEqual(Updates.plugins(path), try python("plugins", [path]).output, json)
        }
    }

    func testSkillsAsPythonReadsThem() throws {
        let cases = [
            #"{"version":3,"skills":{"web":{"skillFolderHash":"aaaaaaa111"},"Pdf":{"skillFolderHash":"bb"},"none":{}}}"#,
            #"{"skills":{"a":{"skillFolderHash":"1234567890"},"b":{"skillFolderHash":null},"c":{"skillFolderHash":"x"}}}"#,
            #"{"skills":{"a":{"skillFolderHash":"x"},"b":[]}}"#, #"{}"#, #"[]"#, "{",
        ]
        for json in cases {
            let path = try write(json, ".skill-lock.json")
            XCTAssertEqual(Updates.skillHashes(path), try python("skills", [path]).output, json)
        }
    }

    func testNpmOutdatedAsPythonReadsIt() throws {
        let root = home + "/root"
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: root + "/linked", withDestinationPath: home)
        let cases = [
            #"{"zlib":{"current":"1.0.0","latest":"1.1.0"},"aaa":{"current":"2.0.0","latest":"3.0.0-beta.1"},"linked":{"current":"1.0.0","latest":"2.0.0"},"git":{"current":"git","latest":"1.0.0"},"same":{"current":"1.0.0","latest":"1.0.0"},"num":{"current":1.5,"latest":"2.0.0"},"@scope/pkg":{"current":"10.20.30x","latest":"10.20.31"}}"#,
            #"{"a":{"current":"1.0.0","latest":"2.0.0"},"b":"oops","c":{"current":"1.0.0","latest":"2.0.0"}}"#,
            #"{"a":{"latest":"2.0.0"},"b":{"current":null,"latest":"2.0.0"}}"#,
            #"  {"a" : {"current" : "1.0.0" , "latest" : "1.0.1"} }  "#,
            "{}", "[]", "", "npm ERR! offline", #"{"a":{"current":"1.0.0","latest":"2.0.0"}} trailing"#,
        ]
        for json in cases {
            XCTAssertEqual(Updates.npmOutdated(json, root: root), try python("npm-outdated", [root], input: json).output, json)
        }
        XCTAssertEqual(Updates.npmOutdated(cases[0], root: ""), try python("npm-outdated", [""], input: cases[0]).output)
    }

    func testAppsBehindAsPythonFindsThem() throws {
        try "#!/bin/bash\n[ \"$1 $2\" = 'list --cask' ] && echo 'macup-brewed other'\n".write(toFile: home + "/bin/brew", atomically: true, encoding: .utf8)
        chmod(home + "/bin/brew", 0o755)
        func app(_ name: String, _ plist: String) throws {
            _ = try write(plist, "Applications/\(name).app/Contents/Info.plist")
        }
        func version(_ key: String, _ value: String) -> String {
            "<?xml version=\"1.0\"?><plist version=\"1.0\"><dict><key>\(key)</key>\(value)</dict></plist>"
        }
        try app("MacupOld", version("CFBundleShortVersionString", "<string>1.0</string>"))
        try app("MacupNew", version("CFBundleShortVersionString", "<string>2.0</string>"))
        try app("MacupMas", version("CFBundleShortVersionString", "<string>1.0</string>"))
        try FileManager.default.createDirectory(atPath: home + "/Applications/MacupMas.app/Contents/_MASReceipt", withIntermediateDirectories: true)
        try app("MacupTwin", version("CFBundleShortVersionString", "<string>1.0</string>"))
        try app("Macup Café", version("CFBundleVersion", "<string>1.9 (7)</string>"))
        try app("MacupNumber", version("CFBundleVersion", "<integer>3</integer>"))
        try app("MacupBrewed", version("CFBundleShortVersionString", "<string>1.0</string>"))
        try app("MacupLong", version("CFBundleShortVersionString", "<string>99999999999999999999.1</string>"))
        try app("MacupLatest", version("CFBundleShortVersionString", "<string>1.0</string>"))
        try app("MacupBroken", "not a plist")
        try app("MacupBool", version("CFBundleShortVersionString", "<true/>"))
        try app("MacupReal", version("CFBundleShortVersionString", "<real>2.0</real>"))
        func cask(_ token: String, _ version: String, _ app: String) -> String {
            #"{"token":"\#(token)","version":\#(version),"artifacts":[{"zap":["x"]},{"app":\#(app)}]}"#
        }
        let catalog = try write("[" + [
            cask("macup-old", #""2.0,abc""#, #"["MacupOld.app"]"#), cask("macup-old@beta", #""3.0""#, #"["MacupOld.app"]"#),
            cask("macup-new", #""2.0""#, #"["MacupNew.app"]"#), cask("macup-mas", #""2.0""#, #"["MacupMas.app"]"#),
            cask("macup-twin", #""2.0""#, #"["MacupTwin.app"]"#), cask("macup-twin-two", #""7.0""#, #"["MacupTwin.app"]"#),
            cask("macup-cafe", #""1.10""#, #"["Macup Café.app"]"#), cask("macup-number", "4", #"["MacupNumber.app"]"#),
            cask("macup-brewed", #""9.0""#, #"["MacupBrewed.app"]"#), cask("macup-long", #""100000000000000000000.0""#, #"["MacupLong.app"]"#),
            cask("macup-latest", #""latest""#, #"["MacupLatest.app"]"#), cask("macup-broken", #""2.0""#, #"["MacupBroken.app"]"#),
            cask("macup-string", #""2.0""#, #""Xylophone.app""#), cask("macup-none", "null", "null"),
            cask("macup-bool", #""True.1""#, #"["MacupBool.app"]"#), cask("macup-real", #""2.0.1""#, #"["MacupReal.app"]"#),
        ].joined(separator: ",") + "]", "cask.json")
        let run = try makeRun()
        let expected = try python("apps-behind", [catalog, home + "/Applications"])
        let found = try XCTUnwrap(Updates.appsBehind(run, catalog))
        XCTAssertTrue(expected.ok)
        XCTAssertEqual(([String(found.checked)] + found.behind).joined(separator: "\n"), expected.output)
        XCTAssertTrue(found.behind.contains("MacupOld 1.0 → 2.0"), "the case the suite relies on is there")

        for broken in [#"{"a":1}"#, #"[{"version":"1"}]"#, #"[{"token":"x","artifacts":[["app"]]}]"#, #"[{"token":"x","artifacts":[{"app":{"a":1}}]}]"#, "["] {
            let path = try write(broken, "broken.json")
            XCTAssertNil(Updates.appsBehind(run, path), broken)
            XCTAssertFalse(try python("apps-behind", [path, home + "/Applications"]).ok, broken)
        }
        for empty in ["{}", "\"\""] {
            let path = try write(empty, "empty.json")
            let found = try XCTUnwrap(Updates.appsBehind(run, path), empty)
            XCTAssertEqual(([String(found.checked)] + found.behind).joined(separator: "\n"), try python("apps-behind", [path, home + "/Applications"]).output, empty)
        }
    }

    func makeRun() throws -> Run {
        let env = try Env(["HOME": home, "PATH": "\(home)/bin:/usr/bin:/bin", "MACUP_PATH": "keep"])
        let arguments = try Arguments.parse(["check"])
        let settings = Settings(config: Config(env: env), env: env, cliSkip: arguments.cliSkip, cliOnly: arguments.cliOnly, cliEnable: arguments.cliEnable, cliLevel: arguments.level)
        let out = Output(i18n: I18n(lang: .en, translations: [:]), colors: .off, fd: open("/dev/null", O_WRONLY))
        return Run(env: env, arguments: arguments, settings: settings, shell: Shell(env: env), out: out, report: Report(path: home + "/report.md", body: home + "/body"),
                   lock: RunLock(dir: home + "/lock", held: false), started: Date(), previous: "")
    }

    func testGrokFieldsAsSedReadsThem() throws {
        let answers = [
            #"{"currentVersion":"1.0.70","latestVersion":"1.0.77","installer":"internal","error":null}"#,
            #"{"currentVersion": "1.0.70", "latestVersion":null}"#,
            "{\"latestVersion\":\"1\"}\n{\"latestVersion\":\"2\",\"x\":{\"latestVersion\":\"3\"}}\n{\"latestVersion\":\"4",
            #"{"latestVersion":"","installer":"brew"}"#, "", "plain text",
        ]
        let keys = ["currentVersion", "latestVersion", "installer"]
        var calls: [String] = []
        for answer in answers {
            for key in keys { calls.append("printf '%s' \(BashOracle.quoted(answer)) | sed -n \"s/.*\\\"\(key)\\\":\\\"\\([^\\\"]*\\)\\\".*/\\1/p\"") }
        }
        let bash = try BashOracle.run(calls)
        var index = 0
        for answer in answers {
            for key in keys {
                XCTAssertEqual(Updates.jsonText(answer, key), bash[index], "\(key) in \(answer)")
                index += 1
            }
        }
    }

    func testReadSplitsAsBashReadDoes() throws {
        let lines = ["a b c", "  a   b  c d  ", "a", "", "a\tb\t c ", "pkg 1.0.0 2.0.0", "name ", "Bar Baz Pro (2.10.3 → 3.0)", "a\\b c"]
        let calls = lines.flatMap { line in
            ["read -r one two <<< \(BashOracle.quoted(line)); printf '%s|%s' \"$one\" \"$two\"",
             "read -r one two three <<< \(BashOracle.quoted(line)); printf '%s|%s|%s' \"$one\" \"$two\" \"$three\""]
        }
        let bash = try BashOracle.run(calls)
        for (index, line) in lines.enumerated() {
            XCTAssertEqual(Updates.read(line, 2).joined(separator: "|"), bash[index * 2], line)
            XCTAssertEqual(Updates.read(line, 3).joined(separator: "|"), bash[index * 2 + 1], line)
        }
    }

    func testMasLinesAsSedCleansThem() throws {
        let lines = ["        1  Foo          (1.0    -> 1.1)", "123456789  Bar Baz Pro  (2.10.3 -> 3.0)", "1 A -> B -> C", "\t2  tab", "   ", "x"]
        let bash = try BashOracle.run(lines.map { "printf '%s\\n' \(BashOracle.quoted($0)) | sed -E 's/^ +//; s/ +/ /g; s/ -> / → /'" })
        for (line, expected) in zip(lines, bash) { XCTAssertEqual(Updates.masLine(line), expected, line) }
    }

    func testSecondFieldAsAwkFindsIt() throws {
        let cases = [("007 old\n7 seven\nweb aaa", "7"), ("1e1 ten\n10 other", "10"), ("web aaa\npdf bbb\nweb ccc", "web"), ("a\\tb x", "a\\tb"), ("x 1", "y"), ("", "a")]
        let bash = try BashOracle.run(cases.map { "printf '%s\\n' \(BashOracle.quoted($0.0)) | awk -v n=\(BashOracle.quoted($0.1)) '$1==n{print $2}'" })
        for (item, expected) in zip(cases, bash) { XCTAssertEqual(Updates.secondField(of: item.1, in: item.0), expected, "\(item)") }
    }

    func testNewestVersionedFormulaAsSortFindsIt() throws {
        let lists = [["node@9", "node@18", "node@24", "node@22"], ["python@3.9", "python@3.12", "python@3.10"], ["node@20"], ["a@1.2.10", "a@1.2.9", "a@1.10"]]
        let bash = try BashOracle.run(lists.map { "printf '%s\\n' \($0.joined(separator: " ")) | sort -t@ -k2 -V | tail -1" })
        for (list, expected) in zip(lists, bash) { XCTAssertEqual(list.max(by: Updates.versionOrder), expected, "\(list)") }
    }

    func testMacOSTitlesAsAwkShortensThem() throws {
        let titles = ["Command Line Tools for Xcode, Version: 16.0, Size: 746159KiB, Recommended: YES, ", "macOS Sequoia 15.1, Version: 15.1, Size: 1",
                      "Safari, Version: 18.1", "BridgeOS", "Blank, Version: , Size: 1", "", ", Version: 2", "A, Version: 1, Version: 2",
                      "Café, Version: é", "X, Version: 1.0,2", "Tools 16.0.1, Version: 16.0"]
        let bash = try BashOracle.run(titles.map { "printf '%s\\n' \(BashOracle.quoted($0)) | awk -F', Version: ' '{v=$2; sub(/,.*/, \"\", v); print (v == \"\" || index($1, v)) ? $1 : $1 \" \" v}'" })
        for (title, expected) in zip(titles, bash) { XCTAssertEqual(Updates.title(title), expected, title) }
    }

    func testMacOSOfflineAsGrepFindsIt() throws {
        let texts = ["No new software available.", "Software Update Tool: could not reach the server", "ERROR", "Not Connected", "no\ninternet",
                     "No Internet connection", "unable  to", "OffLine", "terror", "", "Unable to"]
        let bash = try BashOracle.run(texts.map { "printf '%s\\n' \(BashOracle.quoted($0)) | grep -qiE 'error|could not|unable to|not connected|no internet|offline' && echo yes || echo no" })
        for (text, expected) in zip(texts, bash) { XCTAssertEqual(Updates.saysOffline(text) ? "yes" : "no", expected, text) }
    }

    func testMacOSUpdatesRouteToSwift() throws {
        let environment = try Env(["HOME": home, "PATH": "/usr/bin:/bin"])
        for line in ["check --only check.macos_updates", "update --only check.macos_updates", "check --only update.agy,check.macos_updates --json"] {
            XCTAssertNotEqual(Router.route(line.split(separator: " ").map(String.init), env: environment, terminal: false), .bash, line)
        }
    }

    func testTimedOutputWithErrorsKeepsWhatCameBeforeTheStop() throws {
        let listed = Updates.timedOutput(try makeRun(), 1, ["/bin/sh", "-c", "echo out; echo err >&2; sleep 30"], errors: true)
        XCTAssertEqual(listed.status, 124)
        XCTAssertEqual(listed.text, "out\nerr")
        XCTAssertEqual(Updates.timedOutput(try makeRun(), 5, ["/usr/bin/printf", "* Lab\\0el: X\\n\\n"]).text, "* Label: X")
    }

    func testJSONReaderRefusesWhatPythonRefuses() {
        let deep = String(repeating: "[", count: 5000) + String(repeating: "]", count: 5000)
        for bad in ["", "{", "[1,]", "{\"a\":1,}", "01", "1.", ".5", "\"tab\there\"", "{\"a\" 1}", "[1] [2]", "tru", "\"\\x\"", "\"\\u+abc\"", "\u{FEFF}{}", deep] {
            XCTAssertNil(JSONValue.parse(Data(bad.utf8)), bad)
        }
        for good in ["0", "-0.5e+3", "\"\\ud83d\\ude00\"", " [ ] ", "{\"a\":[1,{\"b\":null}]}", "NaN", "-Infinity", "\"\\u00e9\""] {
            XCTAssertNotNil(JSONValue.parse(Data(good.utf8)), good)
        }
        XCTAssertEqual(JSONValue.parse(Data("\"\\ud83d\\ude00\"".utf8))?.string, "😀")
    }
}

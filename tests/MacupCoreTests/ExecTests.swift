@testable import MacupCore
import XCTest

/// What decides whether a path may be deleted or moved: safe_path, artifact_ok (2.9's cleanup.sh) and the leftovers' to_trash,
/// each with the answer it must give.
final class ExecTests: XCTestCase {
    var home = ""

    override func setUpWithError() throws {
        home = (NSTemporaryDirectory() as NSString).resolvingSymlinksInPath + "/macup-exec-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: home, withIntermediateDirectories: true)
    }

    override func tearDown() {
        _ = shell("chmod -R u+rwx '\(home)'")
        try? FileManager.default.removeItem(atPath: home)
    }

    @discardableResult func shell(_ script: String) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", script]
        process.environment = ["PATH": "/usr/bin:/bin", "HOME": home]
        try? process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    /// Every protected path tests/fixture.sh and the suite know, and the places a cleaner takes from, with safe_path's answer.
    /// A "yes" is not "deleted": the cleaners choose inside what safe_path allows (Archives, ~/.zshrc and Messages are never
    /// registered); a "no" holds whatever a cleaner asks.
    static let safePathTable: [(String, Bool)] = [
        ("Library/Developer/Xcode/DerivedData/App-abc", true), ("Library/Caches/org.swift.swiftpm/repos", true), ("Library/Logs/SomeApp/old.log", true),
        (".Trash/thing", true), ("Code/old/node_modules", true), ("Code/rs/target", true), ("Code/plain/target", false), ("Code/new/package.json", false),
        ("Code/proj/.venv", false), ("Code", false), ("", false), ("Library/Developer/Xcode/Archives/App.xcarchive", true), ("Downloads/movie", false),
        ("Documents/doc", false), (".codex/sessions", false), (".codex/sessions/s.jsonl", false), (".codex/archived_sessions", false),
        (".codex/thread_history_1.sqlite", false), (".gradle/gradle.properties", false), (".m2/settings.xml", false), (".android/avd/Pixel.avd", false),
        (".android/debug.keystore", false), (".android/adbkey", false), ("Library/Application Support/Code/User", false),
        ("Library/Application Support/Code/User/settings.json", false), ("Library/Application Support/Cursor/Backups/file", false),
        ("Library/Application Support/Claude/Backups", false), ("Library/Application Support/Google/Chrome/Default/Login Data", false),
        ("Library/Application Support/Google/Chrome/Local State", false), ("Library/Application Support/Google/Chrome/Default/History", false),
        ("Library/Application Support/Google/Chrome/Default/Cookies", false), ("Library/Application Support/Google/Chrome/Default/Code Cache/js", true),
        ("Library/Application Support/SomeApp/Preferences", false), ("Library/Application Support/SomeApp/Cache", true),
        ("Library/Application Support/QtApp/Cache/q", true), ("Library/Application Support/Codex/Default/Partitions/browser/Local Storage/leveldb", false),
        ("Library/Application Support/Codex/Default/Partitions/browser/Code Cache/js", true), ("Library/Application Support/MobileSync/Backup/x", false),
        ("Library/Caches/deno/location_data", false), ("Library/Caches/deno/location_data/abc/kv.sqlite3", false), ("Library/Caches/deno/deps", true),
        ("Library/Caches/Arc/org.sparkle-project.Sparkle/Installation/z", false),
        ("Library/Caches/com.foo.ShipIt/update.x/Foo.app/Contents/Resources/Cache/r", false),
        ("Library/Caches/com.bar/org.sparkle-project.Sparkle/Installation/y/Bar.app/Contents/GPUCache/g", false),
        ("Library/Caches/zen/Profiles/abc.default/cache2/entries", true), ("Library/Caches/pypoetry/virtualenvs/proj-Ab12-py3.12", true),
        ("Library/Keychains/login.keychain-db", false), ("Library/Messages/chat.db", true), ("Library/Caches/../Documents", false),
        ("Library/Caches/./x", true), ("Library/Caches/x.sqlite", false), (".ssh/id_rsa", false), (".ssh", false), (".gnupg/pubring.kbx", false),
        (".aws/credentials", false), (".aws", false), (".kube/config", false), (".netrc", false), (".config/macup/config", false), (".config", false),
        (".claude", false), (".claude/settings.json", false), (".claude/projects/-Users-me-app/aaaa-1111.jsonl", false),
        (".claude/file-history/bbbb-2222", true), (".claude/file-history/bbbb-2222/x", false), (".claude/file-history/a_b", false),
        (".claude/plugins/cache/mkt/plug/0.8.0", false), ("Library/Application Support/Code/User/workspaceStorage/abc123", true),
        ("Library/Application Support/Code/User/workspaceStorage/.abc", false), ("Library/Application Support/Code/User/workspaceStorage/a/b", false),
        (".zshrc", true), (".nvm/alias/default", true), (".nvm/versions/node/v18.1.0", true), (".npm/_npx/abc", true),
        (".cargo/registry/index/keep", true), (".local/bin/agy.notes", true),
        // a name that starts with a combining mark: bash compares bytes, so the slash before it is still a slash
        ("Library/Application Support/\u{301}X/data", false), ("Library/Application Support/\u{301}X/Cache/c", true),
        ("Library/Application Support/Code/User/workspaceStorage/\u{301}abc", false), (".claude/file-history/\u{301}abc", false),
        ("Code/old/\u{301}node_modules", false), ("Code/\u{301}x/node_modules", true), ("Library/Caches/\u{301}x/../y", false),
        ("Library/Caches/\u{301}Arc/org.sparkle-project.Sparkle", false), ("\u{301}Library/Caches/x", false),
    ]

    func testSafePathTable() throws {
        XCTAssertEqual(shell("'\(Checkout.root)/tests/fixture.sh' '\(home)'"), 0)
        let paths = Self.safePathTable.map { $0.0.isEmpty ? home : "\(home)/\($0.0)" } + ["/tmp/node_modules", "/Users/other/Library/Caches/x", "/"]
        let expected = Self.safePathTable.map(\.1) + [false, false, false]
        let safe = SafePaths(home: home, projectDirs: "~/Code")
        for (path, answer) in zip(paths, expected) { XCTAssertEqual(safe.allows(path), answer, path) }
    }

    func testArtifactTable() throws {
        let made = ["pods/Podfile", "spm/Package.swift", "dart/pubspec.yaml", "next/package.json", "rust/Cargo.toml", "maven/pom.xml",
                    "gradle/build.gradle", "kts/build.gradle.kts"]
        for file in made {
            try FileManager.default.createDirectory(atPath: "\(home)/\((file as NSString).deletingLastPathComponent)", withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: "\(home)/\(file)", contents: nil)
        }
        let table: [(String, Bool)] = [
            ("any/node_modules", true), ("pods/Pods", true), ("spm/Pods", false), ("spm/.build", true), ("pods/.build", false), ("dart/.dart_tool", true),
            ("next/.dart_tool", false), ("next/.next", true), ("rust/.next", false), ("rust/target", true), ("maven/target", true), ("next/target", false),
            ("gradle/build", true), ("kts/build", true), ("rust/build", false), ("next/dist", false), ("rust/Target", false), ("gradle/Build", false),
            ("node_modules", true), ("next/node_modules/", false),
        ]
        for (path, answer) in table { XCTAssertEqual(SafePaths.artifactOK("\(home)/\(path)"), answer, path) }
    }

    /// The calls through to_trash: what each answers, what the report's raw log says, and what is left where, as 2.9's bash did.
    func testToTrashIsBash() throws {
        let calls = ["", "data/../data/a", "data/..", "link", "missing", "data/other", "data/a", "data/b", "data/c", "data/s|sudo",
                     "Library/Containers/X", "Library/Group Containers/G", "other/locked/d"]
        let allowed = ["data/a", "data/b", "data/c", "data/s", "link", "missing", "Library/Containers/X", "Library/Group Containers/G", "other/locked/d"]
        func prepare(_ root: String) {
            XCTAssertEqual(shell("""
                set -e; cd '\(root)'; mkdir -p data/b .Trash bin "Library/Containers/X" "Library/Group Containers/G" other/locked/d
                echo a >data/a; echo b >data/b/f; echo c >data/c; echo s >data/s; echo o >data/other; ln -s data/a link
                echo old >.Trash/c; ln -s nowhere ".Trash/c 2"; echo x >Library/Containers/X/f; echo g >"Library/Group Containers/G/f"; echo d >other/locked/d/f
                printf '#!/bin/bash\\nexec "$@"\\n' >bin/sudo; chmod +x bin/sudo
                chmod 555 Library/Containers "Library/Group Containers" other/locked
                """), 0)
        }
        func outcome(_ root: String) -> [String] {
            let raw = (try? String(contentsOfFile: root + "/raw", encoding: .utf8)) ?? ""
            let listing = Process(), pipe = Pipe()
            listing.executableURL = URL(fileURLWithPath: "/usr/bin/find")
            listing.arguments = [".", "-not", "-name", "raw", "-not", "-path", "./bin*"]
            listing.currentDirectoryURL = URL(fileURLWithPath: root)
            listing.standardOutput = pipe
            try? listing.run()
            let found = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            listing.waitUntilExit()
            return [raw.replacingOccurrences(of: root, with: "H")] + Bash.lines(found).sorted()
        }
        let root = home + "/swift"
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        prepare(root)
        let env = try Env(["HOME": root, "PATH": "\(root)/bin:/usr/bin:/bin:/usr/sbin", "MACUP_PATH": "keep"])
        let arguments = try Arguments.parse(["check"])
        let settings = Settings(config: Config(env: env), env: env, cliSkip: "", cliOnly: "", cliEnable: "", cliLevel: nil)
        let out = Output(i18n: I18n(lang: .en, translations: [:]), colors: .off, fd: open("/dev/null", O_WRONLY))
        let run = Run(env: env, arguments: arguments, settings: settings, shell: Shell(env: env), out: out,
                      report: Report(path: root + "/report.md", body: root + "/body"), lock: RunLock(dir: root + "/lock", held: false),
                      started: Date(), previous: "")
        Leftovers.state(run).allow = allowed.map { "\(root)/\($0)" }.joined(separator: "\n") + "\n"
        let swift = calls.map { call -> String in
            let parts = call.split(separator: "|").map(String.init)
            return Leftovers.toTrash(run, call.isEmpty ? "" : "\(root)/\(parts[0])", sudo: parts.count > 1) ? "0" : "1"
        }
        try? FileManager.default.moveItem(atPath: run.log.raw, toPath: root + "/raw")
        let raw = ["macup refused to move: ", "macup refused to move: H/data/../data/a", "macup refused to move: H/data/..", "macup refused a symlink: H/link",
                   "macup refused to move: H/data/other", "mv: rename H/Library/Containers/X to H/.Trash/X: Permission denied",
                   "mv: rename H/Library/Group Containers/G to H/.Trash/G: Permission denied", "mv: rename H/other/locked/d to H/.Trash/d: Permission denied", ""]
        let left = ["", ".", "./.Trash", "./.Trash/G", "./.Trash/G/f", "./.Trash/X", "./.Trash/X/f", "./.Trash/a", "./.Trash/b", "./.Trash/b/f", "./.Trash/c",
                    "./.Trash/c 2", "./.Trash/c 3", "./.Trash/s", "./Library", "./Library/Containers", "./Library/Containers/X", "./Library/Group Containers",
                    "./Library/Group Containers/G", "./data", "./data/other", "./link", "./other", "./other/locked", "./other/locked/d", "./other/locked/d/f"]
        XCTAssertEqual(outcome(root), [raw.joined(separator: "\n")] + left)
        XCTAssertEqual(swift, ["1", "1", "1", "1", "0", "1", "0", "0", "0", "0", "0", "0", "1"])
    }

    func testLiteralPatternAndTrashNameAreBash() throws {
        let texts = ["/Applications/Foo (1).app/Contents/MacOS/Foo", "a.b*c?d[e]f{g}h|i^j$k+l\\m/n", "", "кеш é", "/a/b/", "/", "name", "/x/y.z"]
        let patterns = ["\\/Applications\\/Foo \\(1\\)\\.app\\/Contents\\/MacOS\\/Foo", "a\\.b\\*c\\?d\\[e\\]f\\{g\\}h\\|i\\^j\\$k\\+l\\\\m\\/n", "",
                        "кеш é", "\\/a\\/b\\/", "\\/", "name", "\\/x\\/y\\.z"]
        XCTAssertEqual(texts.map(Leftovers.literalPattern), patterns)
        XCTAssertEqual(texts.filter { !$0.isEmpty }.map(Cleanup.trashName), ["Foo", "n", "кеш é", "b", "/", "name", "y.z"])
    }
}

@testable import MacupCore
import XCTest

final class CleanupTests: XCTestCase {
    /// cleanup.sh from the build folder table to dev_prefixes (artifact_ok, ai_path, safe_path, in_cache_dir, project_roots),
    /// in_projects, and the Electron cache names safe_path reads.
    static var safePathFunctions: String {
        let cleanup = BashOracle.read("src/cleanup.sh"), cleaners = BashOracle.read("src/cleaners.sh")
        func slice(_ text: String, from start: String, upTo end: String) -> String {
            let lower = text.range(of: start)!.lowerBound
            return String(text[lower..<text.range(of: end, range: lower..<text.endIndex)!.lowerBound]) + "\n"
        }
        return slice(cleanup, from: "ARTIFACT_NAMES=", upTo: "\ndev_prefixes(){") + slice(cleanup, from: "in_projects(){", upTo: "\nkbl(){")
            + slice(cleaners, from: "ELECTRON_CACHES=", upTo: "\n")
    }

    func testSafePathIsBash() throws {
        let home = (NSTemporaryDirectory() as NSString).resolvingSymlinksInPath + "/macup-safe-\(UUID().uuidString)"
        let fm = FileManager.default
        for folder in ["Code/proj", "Code/pods", "Code/rs", "Code/gradle", "Code/swift"] { try fm.createDirectory(atPath: "\(home)/\(folder)", withIntermediateDirectories: true) }
        for file in ["Code/pods/Podfile", "Code/rs/Cargo.toml", "Code/gradle/build.gradle.kts", "Code/swift/Package.swift"] { fm.createFile(atPath: "\(home)/\(file)", contents: nil) }
        defer { try? fm.removeItem(atPath: home) }
        let support = "\(home)/Library/Application Support"
        let paths = [
            "\(home)/Library/Caches/foo", "\(home)/Library/Caches/foo/../bar", "\(home)/Library/Caches/x.sqlite", "\(home)/Library/Caches/com.foo.ShipIt/u",
            "\(home)/Library/Caches/Arc/org.sparkle-project.Sparkle/Installation", "\(home)/Library/Caches/deno/location_data", "\(home)/Library/Caches/deno/deps",
            "\(home)/Library/Keychains/login.keychain-db", "\(home)/Library/Developer/Xcode/DerivedData", "\(home)/Library/Developer/Xcode/DerivedData/App-abc",
            "\(home)/.npm/_npx", "\(home)/.ssh/id", "\(home)/.config/macup", "\(home)/.aws", "\(home)/.android/cache", "\(home)/.android/debug.keystore",
            "\(home)/.android/avd/Pixel.avd", "\(home)/.gradle/gradle.properties", "\(home)/.m2/settings.xml", "\(home)/.codex/sessions/s", "\(home)/.netrc",
            "\(home)/.claude/file-history/abc-123", "\(home)/.claude/file-history/abc/def", "\(home)/.claude/file-history/a_b", "\(home)/.claude/file-history/",
            "\(home)/.claude/projects", "\(home)/.claude/file-history/../x",
            "\(support)/Code/User/workspaceStorage/abc123", "\(support)/Code/User/workspaceStorage/.abc", "\(support)/Code/User/workspaceStorage/a/b",
            "\(support)//User/workspaceStorage/abc", "\(support)/Code/User/workspaceStorage/a_b", "\(support)/Code/User/settings.json",
            "\(support)/Code/Cache", "\(support)/Code/Code Cache/js", "\(support)/Code/Backups/file", "\(support)/Google/Chrome/Default/Code Cache/js",
            "\(support)/Foo/data", "\(support)/Foo/Partitions/p/GPUCache", "\(support)/Foo/CacheStorage",
            "\(home)/Code/proj/node_modules", "\(home)/Code/pods/Pods", "\(home)/Code/proj/Pods", "\(home)/Code/rs/target", "\(home)/Code/gradle/build",
            "\(home)/Code/swift/.build", "\(home)/Code/proj/src", "\(home)/Code/node_modules", "\(home)/Documents/node_modules", "\(home)/Code",
            "/tmp/node_modules", "\(home)", "\(home)/Library/Caches/café", "\(home)/.Trash/thing",
        ]
        let prelude = Self.safePathFunctions + "PROJECT_DIRS=\(BashOracle.quoted("~/Code/, ~/Nope, ~, \(home)/Code/proj"))\n"
        let bash = try BashOracle.run(paths.map { "safe_path \(BashOracle.quoted($0)) && echo yes || echo no" }, home: home, prelude: prelude)
        let safe = SafePaths(home: home, projectDirs: "~/Code/, ~/Nope, ~, \(home)/Code/proj")
        for (path, answer) in zip(paths, bash) { XCTAssertEqual(safe.allows(path) ? "yes" : "no", answer, path) }
        XCTAssertEqual(safe.projectRoots(), ["\(home)/Code", "\(home)/Code/proj"])
    }

    func testKeysAreCksum() throws {
        let sources = ["", "a", "empty|/Users/me/Library/Developer/Xcode/DerivedData", "old|/x", "rm|/a\n/b", "кеш é", String(repeating: "x", count: 300)]
        let bash = try BashOracle.run(sources.map { "printf '%s' \(BashOracle.quoted($0)) | cksum | cut -d' ' -f1" })
        for (source, answer) in zip(sources, bash) {
            XCTAssertEqual(Candidates.key(task: "clean.x", source: source), "clean.x:\(answer)", source)
        }
    }

    func testVersionComparisonIsVerGt() throws {
        let pairs = [("3.0.0", "2.9.2"), ("2.9.2", "3.0.0"), ("2.10.0", "2.9.9"), ("2.9.2", "2.9.2"), ("", "2.9.2"), ("2.9", "2.9.0"), ("2.9.0", "2.9"),
                     ("3.0.0-beta", "3.0.0"), ("3.0.0", "3.0.0-beta"), ("10.0.0", "9.99.99"), ("2.9.2.1", "2.9.2"), ("x", "2.9.2"), ("2.9.2", "x")]
        let prelude = BashOracle.function("ver_gt", in: "src/commands.sh")
        let bash = try BashOracle.run(pairs.map { "ver_gt \(BashOracle.quoted($0.0)) \(BashOracle.quoted($0.1)) && echo yes || echo no" }, prelude: prelude)
        for (pair, answer) in zip(pairs, bash) { XCTAssertEqual(Version.isNewer(pair.0, than: pair.1) ? "yes" : "no", answer, "\(pair)") }
    }

    func testReportOutputLosesColorsLikeNocolor() throws {
        let texts = ["$ brew upgrade\n\u{1B}[1m==>\u{1B}[0m Upgrading\r\nlast", "\u{1B}[?25lhidden\u{1B}[?25h", "\u{1B}[31", "\u{1B}]0;title\u{07}x", "a\u{1B}[1;2mb"]
        let bash = try BashOracle.run(texts.map { "printf '%s' \(BashOracle.quoted($0)) | nocolor | tr -d '\\r'" })
        for (text, answer) in zip(texts, bash) {
            XCTAssertEqual(String(decoding: Summary.withoutColors(Data(text.utf8)), as: UTF8.self), answer, text.debugDescription)
        }
    }
}

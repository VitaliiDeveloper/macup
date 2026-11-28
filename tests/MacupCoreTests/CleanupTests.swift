@testable import MacupCore
import XCTest

final class CleanupTests: XCTestCase {
    func testSafePathIsBash() throws {
        let home = (NSTemporaryDirectory() as NSString).resolvingSymlinksInPath + "/macup-safe-\(UUID().uuidString)"
        let fm = FileManager.default
        for folder in ["Code/proj", "Code/pods", "Code/rs", "Code/gradle", "Code/swift"] { try fm.createDirectory(atPath: "\(home)/\(folder)", withIntermediateDirectories: true) }
        for file in ["Code/pods/Podfile", "Code/rs/Cargo.toml", "Code/gradle/build.gradle.kts", "Code/swift/Package.swift"] { fm.createFile(atPath: "\(home)/\(file)", contents: nil) }
        defer { try? fm.removeItem(atPath: home) }
        let support = "\(home)/Library/Application Support"
        let allowed = [
            "\(home)/Library/Caches/foo", "\(home)/Library/Caches/deno/deps", "\(home)/Library/Developer/Xcode/DerivedData",
            "\(home)/Library/Developer/Xcode/DerivedData/App-abc", "\(home)/.npm/_npx", "\(home)/.android/cache", "\(home)/.claude/file-history/abc-123",
            "\(support)/Code/User/workspaceStorage/abc123", "\(support)/Code/Cache", "\(support)/Code/Code Cache/js",
            "\(support)/Google/Chrome/Default/Code Cache/js", "\(support)/Foo/Partitions/p/GPUCache", "\(home)/Code/proj/node_modules", "\(home)/Code/pods/Pods",
            "\(home)/Code/rs/target", "\(home)/Code/gradle/build", "\(home)/Code/swift/.build", "\(home)/Code/node_modules", "\(home)/Library/Caches/café",
            "\(home)/.Trash/thing",
        ]
        let refused = [
            "\(home)/Library/Caches/foo/../bar", "\(home)/Library/Caches/x.sqlite", "\(home)/Library/Caches/com.foo.ShipIt/u",
            "\(home)/Library/Caches/Arc/org.sparkle-project.Sparkle/Installation", "\(home)/Library/Caches/deno/location_data",
            "\(home)/Library/Keychains/login.keychain-db", "\(home)/.ssh/id", "\(home)/.config/macup", "\(home)/.aws", "\(home)/.android/debug.keystore",
            "\(home)/.android/avd/Pixel.avd", "\(home)/.gradle/gradle.properties", "\(home)/.m2/settings.xml", "\(home)/.codex/sessions/s", "\(home)/.netrc",
            "\(home)/.claude/file-history/abc/def", "\(home)/.claude/file-history/a_b", "\(home)/.claude/file-history/", "\(home)/.claude/projects",
            "\(home)/.claude/file-history/../x", "\(support)/Code/User/workspaceStorage/.abc", "\(support)/Code/User/workspaceStorage/a/b",
            "\(support)//User/workspaceStorage/abc", "\(support)/Code/User/workspaceStorage/a_b", "\(support)/Code/User/settings.json",
            "\(support)/Code/Backups/file", "\(support)/Foo/data", "\(support)/Foo/CacheStorage", "\(home)/Code/proj/Pods", "\(home)/Code/proj/src",
            "\(home)/Documents/node_modules", "\(home)/Code", "/tmp/node_modules", "\(home)",
        ]
        let safe = SafePaths(home: home, projectDirs: "~/Code/, ~/Nope, ~, \(home)/Code/proj")
        for path in allowed { XCTAssertTrue(safe.allows(path), path) }
        for path in refused { XCTAssertFalse(safe.allows(path), path) }
        XCTAssertEqual(safe.projectRoots(), ["\(home)/Code", "\(home)/Code/proj"])
    }

    func testKeysAreCksum() {
        let sources = ["", "a", "empty|/Users/me/Library/Developer/Xcode/DerivedData", "old|/x", "rm|/a\n/b", "кеш é", String(repeating: "x", count: 300)]
        let sums = ["4294967295", "1220704766", "2729394625", "2284035322", "2351487438", "3038808684", "3786917833"]
        XCTAssertEqual(sources.map { Candidates.key(task: "clean.x", source: $0) }, sums.map { "clean.x:\($0)" })
    }

    func testVersionComparisonIsVerGt() {
        let cases = [("3.0.0", "2.9.2", true), ("2.9.2", "3.0.0", false), ("2.10.0", "2.9.9", true), ("2.9.2", "2.9.2", false), ("", "2.9.2", false),
                     ("2.9", "2.9.0", false), ("2.9.0", "2.9", true), ("3.0.0-beta", "3.0.0", true), ("3.0.0", "3.0.0-beta", false),
                     ("10.0.0", "9.99.99", true), ("2.9.2.1", "2.9.2", true), ("x", "2.9.2", false), ("2.9.2", "x", true)]
        for (newer, older, expected) in cases { XCTAssertEqual(Version.isNewer(newer, than: older), expected, "\(newer) > \(older)") }
    }

    func testReportOutputLosesColorsLikeNocolor() {
        let cases = [("$ brew upgrade\n\u{1B}[1m==>\u{1B}[0m Upgrading\r\nlast", "$ brew upgrade\n==> Upgrading\nlast"), ("\u{1B}[?25lhidden\u{1B}[?25h", "hidden"),
                     ("\u{1B}[31", "\u{1B}[31"), ("\u{1B}]0;title\u{07}x", "\u{1B}]0;title\u{07}x"), ("a\u{1B}[1;2mb", "ab")]
        for (text, expected) in cases {
            XCTAssertEqual(String(decoding: Summary.withoutColors(Data(text.utf8)), as: UTF8.self), expected, text.debugDescription)
        }
    }
}

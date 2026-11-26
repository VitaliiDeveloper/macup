import Foundation
import XCTest
@testable import MacupCore

final class NamesTests: XCTestCase {
    // the test folder can be on a case-insensitive volume: no two of these fold into one name. strcoll ties the Cyrillic and
    // CJK ones with each other, and é with e once FileManager stores it decomposed
    static let names = ["dev", "Library", "_x", "apple", "Zed", "e", "é", "Éclair", "Ärger", "b", "Bee", "straße", "zebra", "10", "9",
                        "Їжак", "яблуко", "Дім", "Дом", "ґанок", "日本", "中文", "f.sqlite", "macup_2026-11-01_10-00-00.md", "macup_2026-11-01_10-00-00_123.md",
                        ".hidden", "..dots", ".a", ".g.sqlite"]

    /// The locales bash and Swift start in. BashOracle's environment has LC_CTYPE=en_US.UTF-8; "" unsets it for core.sh.
    static let locales: [[String: String]] = [["LANG": "en_US.UTF-8", "LC_CTYPE": ""], ["LANG": "C", "LC_CTYPE": ""], ["LANG": "uk_UA.UTF-8"],
                                              ["LC_ALL": "C"], ["LC_ALL": "en_US.UTF-8"], ["LANG": "", "LC_CTYPE": ""]]

    /// core.sh's own line that exports LC_CTYPE: the oracle's core functions start after it.
    static let export = BashOracle.read("src/core.sh").components(separatedBy: "\n").first { $0.contains("export LC_CTYPE=") }!

    override func tearDown() {
        Names.setLocale(try! Env(ProcessInfo.processInfo.environment))
    }

    /// Swift's == takes é and e + U+0301 as one string: the tools print bytes.
    private func bytes(_ text: String) -> [UInt8] { Array(text.utf8) }

    private func useLocale(_ vars: [String: String]) throws {
        Names.setLocale(try Env(["HOME": "/Users/someone", "LC_CTYPE": "en_US.UTF-8"].merging(vars) { $1 }))
    }

    func testSortAsBash() throws {
        let list = Self.names.map(BashOracle.quoted).joined(separator: " ")
        for vars in Self.locales {
            try useLocale(vars)
            let bash = try BashOracle.run(["printf '%s\\n' \(list) | sort"], env: vars, prelude: Self.export)
            XCTAssertEqual(bytes(Names.sorted(Self.names).joined(separator: "\n")), bytes(bash[0]), "\(vars)")
        }
    }

    func testGlobAsBash() throws {
        let folder = NSTemporaryDirectory() + "macup-glob-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: folder) }
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        for name in Self.names { XCTAssertTrue(FileManager.default.createFile(atPath: "\(folder)/\(name)", contents: nil)) }
        let patterns = ["*", ".[!.]*", "*.sqlite", "macup_*.md", "[a-z]*", "?", "nothing*"]
        for vars in Self.locales {
            try useLocale(vars)
            let bash = try BashOracle.run(patterns.map { "for name in \(BashOracle.quoted(folder))/\($0); do [ -e \"$name\" ] && echo \"$name\"; done" },
                                          env: vars, prelude: Self.export)
            XCTAssertEqual(patterns.map { bytes(Names.glob(folder, $0).joined(separator: "\n")) }, bash.map(bytes), "\(vars)")
        }
    }

    /// The report tidy-up keeps the first names `ls -r` lists: two reports from the same second come in the locale's order.
    func testSameSecondReportsAsLs() throws {
        let folder = NSTemporaryDirectory() + "macup-tidy-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: folder) }
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        for name in ["macup_2026-11-01_10-00-00.md", "macup_2026-11-01_10-00-00_123.md"] { FileManager.default.createFile(atPath: "\(folder)/\(name)", contents: nil) }
        var orders: Set<[String]> = []
        for vars in Self.locales {
            try useLocale(vars)
            let bash = try BashOracle.run(["ls -r \(BashOracle.quoted(folder))/macup_*.md"], env: vars, prelude: Self.export)
            let swift = Array(Names.glob(folder, "macup_*.md").reversed())
            XCTAssertEqual(bytes(swift.joined(separator: "\n")), bytes(bash[0]), "\(vars)")
            orders.insert(swift)
        }
        XCTAssertEqual(orders.count, 2, "UTF-8 and C order the two reports differently")
    }
}

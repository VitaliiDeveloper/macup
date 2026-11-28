import Foundation
import XCTest
@testable import MacupCore

final class NamesTests: XCTestCase {
    // the test folder can be on a case-insensitive volume: no two of these fold into one name. strcoll ties the Cyrillic and
    // CJK ones with each other, and é with e once FileManager stores it decomposed
    static let names = ["dev", "Library", "_x", "apple", "Zed", "e", "é", "Éclair", "Ärger", "b", "Bee", "straße", "zebra", "10", "9",
                        "Їжак", "яблуко", "Дім", "Дом", "ґанок", "日本", "中文", "f.sqlite", "macup_2026-11-01_10-00-00.md", "macup_2026-11-01_10-00-00_123.md",
                        ".hidden", "..dots", ".a", ".g.sqlite"]

    /// The order each locale gave 2.9's bash and its tools: `sort` and `ls -r` follow the collation, globs bash's own locale.
    enum Order: String { case utf8, c, uk }

    /// Fixtures/NamesTests-orders.json: per order, what `sort`, `ls -r` and each of the glob patterns printed.
    struct Orders: Decodable {
        let sort: [String: [String]]
        let glob: [String: [[String]]]
        let ls: [String: [String]]
    }

    static let orders = try! JSONDecoder().decode(Orders.self, from: Data(Checkout.fixture("NamesTests-orders.json").utf8))

    /// The locales macup starts in. The test environment has LC_CTYPE=en_US.UTF-8; "" unsets it, as for a run started without one.
    /// bogus, en_DK.UTF-8 and the Linux spelling en_US.utf8 are locales macOS lacks: bash and its tools fall back differently.
    static let locales: [(vars: [String: String], collate: Order, glob: Order)] = [
        (["LANG": "en_US.UTF-8", "LC_CTYPE": ""], .utf8, .utf8), (["LANG": "C", "LC_CTYPE": ""], .c, .c), (["LANG": "uk_UA.UTF-8"], .uk, .uk),
        (["LC_ALL": "C"], .c, .c), (["LC_ALL": "en_US.UTF-8"], .utf8, .utf8), (["LANG": "", "LC_CTYPE": ""], .c, .c),
        (["LANG": "en_US.ISO8859-1", "LC_CTYPE": ""], .utf8, .utf8), (["LANG": "en_US.UTF-8", "LC_CTYPE": "", "LC_COLLATE": "bogus"], .c, .utf8),
        (["LANG": "uk_UA.UTF-8", "LC_CTYPE": "en_US.utf8"], .c, .uk), (["LC_COLLATE": "en_US.UTF-8", "LC_CTYPE": "en_US.utf8"], .c, .c),
        (["LANG": "en_US.UTF-8", "LC_CTYPE": "", "LC_TIME": "en_DK.UTF-8"], .c, .utf8), (["LANG": "uk_UA.UTF-8", "LC_NUMERIC": "xx"], .c, .uk),
        (["LC_ALL": "bogus", "LANG": "en_US.UTF-8"], .c, .c), (["LANG": "en_US.utf8", "LC_COLLATE": "uk_UA.UTF-8", "LC_CTYPE": ""], .c, .c),
        (["LC_COLLATE": "uk_UA.UTF-8", "LC_TIME": "bogus", "LC_CTYPE": ""], .c, .c),
    ]

    override func tearDown() {
        Names.bashLocale = nil
        Names.toolLocale = nil
    }

    /// Swift's == takes é and e + U+0301 as one string: the tools print bytes.
    private func bytes(_ text: String) -> [UInt8] { Array(text.utf8) }

    /// The names in `folder`, as the tools printed them without the folder.
    private func bytes(_ paths: [String], in folder: String) -> [UInt8] { bytes(paths.map { String($0.dropFirst(folder.count + 1)) }.joined(separator: "\n")) }

    private func useLocale(_ vars: [String: String]) throws {
        Names.setLocale(try Env(["HOME": "/Users/someone", "LC_CTYPE": "en_US.UTF-8"].merging(vars) { $1 }))
    }

    func testSortAsBash() throws {
        for locale in Self.locales {
            try useLocale(locale.vars)
            XCTAssertEqual(bytes(Names.sorted(Self.names).joined(separator: "\n")), bytes(Self.orders.sort[locale.collate.rawValue]!.joined(separator: "\n")), "\(locale.vars)")
        }
    }

    func testGlobAsBash() throws {
        let folder = NSTemporaryDirectory() + "macup-glob-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: folder) }
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        for name in Self.names { XCTAssertTrue(FileManager.default.createFile(atPath: "\(folder)/\(name)", contents: nil)) }
        let patterns = ["*", ".[!.]*", "*.sqlite", "macup_*.md", "[a-z]*", "?", "nothing*"]
        for locale in Self.locales {
            try useLocale(locale.vars)
            let expected = Self.orders.glob[locale.glob.rawValue]!.map { bytes($0.joined(separator: "\n")) }
            XCTAssertEqual(patterns.map { bytes(Names.glob(folder, $0), in: folder) }, expected, "\(locale.vars)")
        }
    }

    /// The report tidy-up keeps the first names `ls -r` lists: two reports from the same second come in the locale's order,
    /// and names strcoll ties come in the order of ls's own qsort.
    func testReportsAsLsReversed() throws {
        let folder = NSTemporaryDirectory() + "macup-tidy-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: folder) }
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        for name in ["2026-11-01_10-00-00", "2026-11-01_10-00-00_123", "б", "в", "г", "д", "ж", "з", "к", "л", "м"] {
            FileManager.default.createFile(atPath: "\(folder)/macup_\(name).md", contents: nil)
        }
        var orders: Set<[String]> = []
        for locale in Self.locales {
            try useLocale(locale.vars)
            let swift = Names.lsReversed(Names.glob(folder, "macup_*.md"))
            XCTAssertEqual(bytes(swift, in: folder), bytes(Self.orders.ls[locale.collate.rawValue]!.joined(separator: "\n")), "\(locale.vars)")
            orders.insert(swift.filter { $0.contains("2026") })
        }
        XCTAssertEqual(orders.count, 2, "UTF-8 and C order the two reports of one second differently")
    }
}

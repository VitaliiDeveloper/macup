@testable import MacupCore
import XCTest

/// hum, tokb, tokb10, ulen, pad, jstr, jlines, jarr: byte-identical with core.sh.
final class SizeTextJSONTests: XCTestCase {
    // captured from `hum` of the bash build (awk 20200816)
    let humCaptured: [(String, String)] = [
        ("0", "0 KB"), ("1", "1 KB"), ("999", "1 MB"), ("1000", "1 MB"), ("976", "999 KB"), ("977", "1 MB"),
        ("1024", "1 MB"), ("9765", "10 MB"), ("976562", "1000 MB"), ("976563", "1.0 GB"), ("1048576", "1.1 GB"),
        ("1500000", "1.5 GB"), ("-1", "-1 KB"), ("-2048", "-2 MB"), ("-1500000", "-1.5 GB"), ("abc", "0 KB"),
        ("12abc", "12 KB"), (" 7", "7 KB"), ("1e3", "1 MB"), ("0x10", "16 KB"), ("-abc", "-0 KB"), ("", "0 KB"),
        ("3.75", "3 KB"), ("+5", "5 KB"), (".5", "0 KB"), ("-nan", "nan GB"), ("inf", "inf GB"), ("-1e400", "-inf GB"),
    ]

    func testHumCaptured() {
        for (k, want) in humCaptured { XCTAssertEqual(Size.hum(k), want, "hum \(k)") }
    }

    // captured from `tokb` and `tokb10`
    let tokbCaptured: [(String, String, String)] = [
        ("1.5GB", "1572864", "1464843"), ("12.3MB", "12595", "12011"), ("12.3MB (100%)", "12595", "12011"), ("0B", "0", "0"),
        ("3gb", "3145728", "2929687"), ("1.2.3MB", "1228", "1171"), ("", "0", "0"), ("1 GB", "0", "0"), ("-1GB", "0", "0"),
        ("2TB", "2147483648", "1953125000"), ("512KB", "512", "500"), ("7B", "0", "0"), ("1GB\n2MB", "10485762048", "9765621953"),
        ("1e3KB", "0", "0"), ("-n", "", ""), ("2.5kB", "2", "2"), ("  4MB", "4096", "3906"),
    ]

    func testTokbCaptured() {
        for (s, kb, kb10) in tokbCaptured {
            XCTAssertEqual(Size.tokb(s), kb, "tokb \(s)")
            XCTAssertEqual(Size.tokb10(s), kb10, "tokb10 \(s)")
        }
    }

    func testUlenPadCaptured() {
        let cases: [(String, Int, String)] = [
            ("", 0, "        "), ("a", 1, "a       "), ("Українська", 10, "Українська "), ("\u{E9}", 1, "\u{E9}       "),
            ("e\u{301}", 2, "e\u{301}      "), ("👍🏽", 2, "👍🏽      "), ("日本語", 3, "日本語     "), ("a b", 3, "a b     "),
        ]
        for (s, n, padded) in cases {
            XCTAssertEqual(Text.ulen(s), n, "ulen \(s)")
            XCTAssertEqual(Text.pad(s, 8), padded, "pad \(s)")
        }
    }

    func testJstrCaptured() {
        XCTAssertEqual(JSON.str("a\"b"), "a\\\"b")
        XCTAssertEqual(JSON.str("a\\b"), "a\\\\b")
        XCTAssertEqual(JSON.str("tab\there"), "tabhere")
        XCTAssertEqual(JSON.str("new\nline"), "newline")
        XCTAssertEqual(JSON.str("/path/to"), "/path/to")
        XCTAssertEqual(JSON.str("\u{01}x\u{1F}\u{7F}"), "x\u{7F}")
        XCTAssertEqual(JSON.lines("a\n\nb \"q\"\n"), "[\"a\",\"b \\\"q\\\"\"]")
        XCTAssertEqual(JSON.array([]), "[]")
    }

    /// The same inputs and more through the bash functions themselves.
    func testAgainstBash() throws {
        let nums = humCaptured.map(\.0) + ["2147483647", "99999999999", "-0", "1e9", "1,5", "5.", "  -3  ", "3 x", "nan", "-inf", "0x1p3"]
        let sizes = tokbCaptured.map(\.0) + ["1.5 MB", "MB", "1.5TB", "0.5gB", "12.34567GB", "-E", "1KB\n\n3KB", "9e2MB"]
        // \001 and \177 are left out: bash 3.2 mangles them in script text (its own quoting bytes)
        let texts = ["", "x", "Пам'ять", "e\u{301}e\u{301}", "🇺🇦", "a\tb", "日本語テキスト", "tab\there", "q\"\\'", "\u{1F}é\u{1B}", "line1\nline2\n\nline4"]
        var calls: [String] = []
        calls += nums.map { "hum \(BashOracle.q($0))" }
        calls += sizes.flatMap { ["tokb \(BashOracle.q($0))", "tokb10 \(BashOracle.q($0))"] }
        calls += texts.flatMap { t in ["ulen", "pad", "jstr", "jlines", "jarr"].map { "\($0) \(BashOracle.q(t)) \($0 == "pad" ? "12" : $0 == "jarr" ? "b" : "")" } }
        let got = try BashOracle.run(calls)
        var i = 0
        for n in nums { XCTAssertEqual(Size.hum(n), got[i], "hum \(n)"); i += 1 }
        for s in sizes {
            XCTAssertEqual(Size.tokb(s), got[i], "tokb \(s.debugDescription)")
            XCTAssertEqual(Size.tokb10(s), got[i + 1], "tokb10 \(s.debugDescription)")
            i += 2
        }
        for t in texts {
            let swift = [String(Text.ulen(t)), Text.pad(t, 12), JSON.str(t), JSON.lines(t), JSON.array([t, "b"])]
            XCTAssertEqual(swift, Array(got[i..<i + 5]), "text \(t.debugDescription)")
            i += 5
        }
    }

    func testKbUsesDu() throws {
        let dir = NSTemporaryDirectory() + "macup-kb-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        try Data(count: 300 * 1024).write(to: URL(fileURLWithPath: dir + "/blob"))
        let shell = Shell(env: try Env(["HOME": "/Users/someone", "PATH": "/usr/bin:/bin", "MACUP_PATH": "keep"]))
        let want = try BashOracle.run(["kb \(BashOracle.q(dir))", "kb \(BashOracle.q(dir + "/none"))"])
        XCTAssertEqual(String(Size.kb(dir, shell: shell)), want[0])
        XCTAssertEqual(String(Size.kb(dir + "/none", shell: shell)), want[1])
        XCTAssertGreaterThanOrEqual(Size.kb(dir, shell: shell), 300)
    }
}

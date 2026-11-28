@testable import MacupCore
import XCTest

/// hum, tokb, tokb10, ulen, pad, jstr, jlines, jarr: byte-identical with what 2.9's core.sh printed.
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
        for (kilobytes, want) in humCaptured { XCTAssertEqual(Size.hum(kilobytes), want, "hum \(kilobytes)") }
    }

    // captured from `tokb` and `tokb10`
    let tokbCaptured: [(String, String, String)] = [
        ("1.5GB", "1572864", "1464843"), ("12.3MB", "12595", "12011"), ("12.3MB (100%)", "12595", "12011"), ("0B", "0", "0"),
        ("3gb", "3145728", "2929687"), ("1.2.3MB", "1228", "1171"), ("", "0", "0"), ("1 GB", "0", "0"), ("-1GB", "0", "0"),
        ("2TB", "2147483648", "1953125000"), ("512KB", "512", "500"), ("7B", "0", "0"), ("1GB\n2MB", "10485762048", "9765621953"),
        ("1e3KB", "0", "0"), ("-n", "", ""), ("2.5kB", "2", "2"), ("  4MB", "4096", "3906"),
    ]

    func testTokbCaptured() {
        for (size, kb, kb10) in tokbCaptured {
            XCTAssertEqual(Size.tokb(size), kb, "tokb \(size)")
            XCTAssertEqual(Size.tokb10(size), kb10, "tokb10 \(size)")
        }
    }

    func testUlenPadCaptured() {
        let cases: [(String, Int, String)] = [
            ("", 0, "        "), ("a", 1, "a       "), ("Українська", 10, "Українська "), ("\u{E9}", 1, "\u{E9}       "),
            ("e\u{301}", 2, "e\u{301}      "), ("👍🏽", 2, "👍🏽      "), ("日本語", 3, "日本語     "), ("a b", 3, "a b     "),
        ]
        for (text, length, padded) in cases {
            XCTAssertEqual(Text.ulen(text), length, "ulen \(text)")
            XCTAssertEqual(Text.pad(text, 8), padded, "pad \(text)")
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

    /// More inputs, as core.sh's functions answered them.
    func testMoreCaptured() {
        let hum = [("2147483647", "2199.0 GB"), ("99999999999", "102400.0 GB"), ("-0", "0 KB"), ("1e9", "1024.0 GB"), ("1,5", "1 KB"), ("5.", "5 KB"),
                   ("  -3  ", "-3 KB"), ("3 x", "3 KB"), ("nan", "nan GB"), ("-inf", "-inf GB"), ("0x1p3", "8 KB")]
        for (kilobytes, want) in hum { XCTAssertEqual(Size.hum(kilobytes), want, "hum \(kilobytes)") }
        let tokb = [("1.5 MB", "0", "0"), ("MB", "0", "0"), ("1.5TB", "1610612736", "1464843750"), ("0.5gB", "524288", "488281"),
                    ("12.34567GB", "12945373", "12056318"), ("-E", "0", "0"), ("1KB\n\n3KB", "103", "002"), ("9e2MB", "0", "0")]
        for (size, kb, kb10) in tokb {
            XCTAssertEqual(Size.tokb(size), kb, "tokb \(size.debugDescription)")
            XCTAssertEqual(Size.tokb10(size), kb10, "tokb10 \(size.debugDescription)")
        }
        // text, ulen, pad to 12, jstr, jlines; jarr is [jstr, "b"]
        let texts: [(String, Int, String, String, String)] = [
            ("", 0, "            ", "", "[]"),
            ("x", 1, "x           ", "x", "[\"x\"]"),
            ("Пам'ять", 7, "Пам'ять     ", "Пам'ять", "[\"Пам'ять\"]"),
            ("e\u{301}e\u{301}", 4, "e\u{301}e\u{301}        ", "e\u{301}e\u{301}", "[\"e\u{301}e\u{301}\"]"),
            ("🇺🇦", 2, "🇺🇦          ", "🇺🇦", "[\"🇺🇦\"]"),
            ("a\tb", 3, "a\tb         ", "ab", "[\"ab\"]"),
            ("日本語テキスト", 7, "日本語テキスト     ", "日本語テキスト", "[\"日本語テキスト\"]"),
            ("tab\there", 8, "tab\there    ", "tabhere", "[\"tabhere\"]"),
            ("q\"\\'", 4, "q\"\\'        ", "q\\\"\\\\'", "[\"q\\\"\\\\'\"]"),
            ("\u{1F}\u{E9}\u{1B}", 3, "\u{1F}\u{E9}\u{1B}         ", "\u{E9}", "[\"\u{E9}\"]"),
            ("line1\nline2\n\nline4", 18, "line1\nline2\n\nline4 ", "line1line2line4", "[\"line1\",\"line2\",\"line4\"]"),
        ]
        for (text, length, padded, string, lines) in texts {
            let swift = [String(Text.ulen(text)), Text.pad(text, 12), JSON.str(text), JSON.lines(text), JSON.array([text, "b"])]
            XCTAssertEqual(swift, [String(length), padded, string, lines, "[\"\(string)\",\"b\"]"], "text \(text.debugDescription)")
        }
    }

    func testKbUsesDu() throws {
        let dir = NSTemporaryDirectory() + "macup-kb-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        try Data(count: 300 * 1024).write(to: URL(fileURLWithPath: dir + "/blob"))
        let shell = Shell(env: try Env(["HOME": "/Users/someone", "PATH": "/usr/bin:/bin", "MACUP_PATH": "keep"]))
        XCTAssertEqual(Size.kb(dir, shell: shell), 300)
        XCTAssertEqual(Size.kb(dir + "/none", shell: shell), 0)
    }
}

@testable import MacupCore
import XCTest

final class PathsI18nTests: XCTestCase {
    func testTildifyExpandAgainstBash() throws {
        let homes = ["/Users/me", "/var/folders/x/macup-tests.AbC123/h", "/Users/a&b", "/tmp/h.x"]
        let paths = ["", "/Users/me", "/Users/me/.config/macup/config", "/Users/meme/x", "/Users/mex/y", "~", "~/Code", "~other/x",
                     "/elsewhere", "-n", "/Users/me\n/Users/me/two", "/var/folders/x/macup-testsXAbC123/h/z", "/tmp/hXx/a", "/tmp/h.x/b"]
        for home in homes {
            let p = Paths(home: home)
            let got = try BashOracle.run(paths.flatMap { ["tildify \(BashOracle.q($0))", "expand \(BashOracle.q($0))"] }, home: home)
            for (i, path) in paths.enumerated() {
                XCTAssertEqual(p.tildify(path), got[2 * i], "tildify \(path.debugDescription) with HOME=\(home)")
                XCTAssertEqual(p.expand(path), got[2 * i + 1], "expand \(path.debugDescription) with HOME=\(home)")
            }
        }
    }

    func testPrintfAgainstBash() throws {
        let cases: [(String, [String])] = [
            ("%s", ["a"]), ("%s and %s", ["a"]), ("%s=%d", ["x", "12"]), ("%d%%", ["7"]), ("a%sb", ["1", "2", "3"]),
            ("%s: %s → %s", ["Foo", "1.0", "1.1"]), ("no args", ["extra"]), ("%d", [""]), ("%d", ["0x1F"]), ("%d", ["010"]),
            ("%d", [" 42"]), ("tab\\there\\n", []), ("100%", []), ("%s%%)", ["5"]), ("\\101\\x41", []), ("%d", ["1.5"]), ("%d|%d", ["3 ", "12abc"]), ("-x %s", ["a"]),
            ("Mode: %s · macup %s · took %s", ["check", "2.9.2", "0m 1s"]),
        ]
        let got = try BashOracle.run(cases.map { c in "printf \(BashOracle.q(c.0))" + c.1.map { " " + BashOracle.q($0) }.joined() })
        for (i, c) in cases.enumerated() { XCTAssertEqual(Bash.substitution(Printf.format(c.0, c.1)), got[i], "printf \(c.0) \(c.1)") }
    }

    var translations: [String: [String: String]] {
        (try? JSONSerialization.jsonObject(with: Data(BashOracle.read("src/i18n/translations.json").utf8))) as? [String: [String: String]] ?? [:]
    }

    func testTranslationsAndFallback() {
        let uk = I18n(lang: .uk, translations: translations)
        XCTAssertEqual(uk.t("TASK"), translations["TASK"]?["uk"])
        XCTAssertEqual(uk.t("not a message"), "not a message")
        XCTAssertEqual(I18n(lang: .en, translations: translations).t("TASK"), "TASK")
        XCTAssertEqual(uk.f("Language: %s", Lang.uk.name), Printf.format(translations["Language: %s"]!["uk"]!, ["Українська"]))
        XCTAssertEqual(I18n(lang: .ru, translationsJSON: BashOracle.read("src/i18n/translations.json")).t("STATE"), translations["STATE"]?["ru"])
        // every entry has both languages and the same placeholders (build.sh refuses the build otherwise)
        for (en, tr) in translations {
            for l in ["uk", "ru"] { XCTAssertFalse((tr[l] ?? "").isEmpty, "\(l) for \(en)") }
        }
    }

    func testLangOption() {
        XCTAssertEqual(Lang.option("ua"), .uk)
        XCTAssertEqual(Lang.option("ru"), .ru)
        XCTAssertNil(Lang.option("xx"))
        XCTAssertNil(Lang(rawValue: "ua"), "MACUP_LANG=ua and language = ua are English, as in core.sh")
    }
}

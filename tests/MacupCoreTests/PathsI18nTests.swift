@testable import MacupCore
import XCTest

final class PathsI18nTests: XCTestCase {
    func testTildifyExpandAgainstBash() throws {
        let homes = ["/Users/me", "/var/folders/x/macup-tests.AbC123/h", "/Users/a&b", "/tmp/h.x"]
        let paths = ["", "/Users/me", "/Users/me/.config/macup/config", "/Users/meme/x", "/Users/mex/y", "~", "~/Code", "~other/x",
                     "/elsewhere", "-n", "/Users/me\n/Users/me/two", "/var/folders/x/macup-testsXAbC123/h/z", "/tmp/hXx/a", "/tmp/h.x/b"]
        for home in homes {
            let homePaths = Paths(home: home)
            let got = try BashOracle.run(paths.flatMap { ["tildify \(BashOracle.quoted($0))", "expand \(BashOracle.quoted($0))"] }, home: home)
            for (index, path) in paths.enumerated() {
                XCTAssertEqual(homePaths.tildify(path), got[2 * index], "tildify \(path.debugDescription) with HOME=\(home)")
                XCTAssertEqual(homePaths.expand(path), got[2 * index + 1], "expand \(path.debugDescription) with HOME=\(home)")
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
        let got = try BashOracle.run(cases.map { example in "printf \(BashOracle.quoted(example.0))" + example.1.map { " " + BashOracle.quoted($0) }.joined() })
        for (index, example) in cases.enumerated() { XCTAssertEqual(Bash.substitution(Printf.format(example.0, example.1)), got[index], "printf \(example.0) \(example.1)") }
    }

    var translations: [String: [String: String]] {
        (try? JSONSerialization.jsonObject(with: Data(BashOracle.read("src/i18n/translations.json").utf8))) as? [String: [String: String]] ?? [:]
    }

    func testTranslationsAndFallback() {
        let uk = I18n(lang: .uk, translations: translations)
        XCTAssertEqual(uk.translate("TASK"), translations["TASK"]?["uk"])
        XCTAssertEqual(uk.translate("not a message"), "not a message")
        XCTAssertEqual(I18n(lang: .en, translations: translations).translate("TASK"), "TASK")
        XCTAssertEqual(uk.format("Language: %s", Lang.uk.name), Printf.format(translations["Language: %s"]!["uk"]!, ["Українська"]))
        XCTAssertEqual(I18n(lang: .ru, translationsJSON: BashOracle.read("src/i18n/translations.json")).translate("STATE"), translations["STATE"]?["ru"])
        // every entry has both languages and the same placeholders (build.sh refuses the build otherwise)
        for (en, tr) in translations {
            for lang in ["uk", "ru"] { XCTAssertFalse((tr[lang] ?? "").isEmpty, "\(lang) for \(en)") }
        }
    }

    func testLangOption() {
        XCTAssertEqual(Lang.option("ua"), .uk)
        XCTAssertEqual(Lang.option("ru"), .ru)
        XCTAssertNil(Lang.option("xx"))
        XCTAssertNil(Lang(rawValue: "ua"), "MACUP_LANG=ua and language = ua are English, as in core.sh")
    }
}

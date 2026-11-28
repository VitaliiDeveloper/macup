@testable import MacupCore
import XCTest

final class PathsI18nTests: XCTestCase {
    /// tildify and expand as 2.9's sed did: a . in HOME matches any character, a & in it is sed's whole match, a dash path prints nothing.
    func testTildifyExpand() {
        let cases: [(home: String, path: String, tildified: String, expanded: String)] = [
            ("/Users/me", "", "", ""),
            ("/Users/me", "/Users/me", "~", "/Users/me"),
            ("/Users/me", "/Users/me/.config/macup/config", "~/.config/macup/config", "/Users/me/.config/macup/config"),
            ("/Users/me", "/Users/meme/x", "~me/x", "/Users/meme/x"),
            ("/Users/me", "/Users/mex/y", "~x/y", "/Users/mex/y"),
            ("/Users/me", "~", "~", "/Users/me"),
            ("/Users/me", "~/Code", "~/Code", "/Users/me/Code"),
            ("/Users/me", "~other/x", "~other/x", "/Users/meother/x"),
            ("/Users/me", "/elsewhere", "/elsewhere", "/elsewhere"),
            ("/Users/me", "-n", "", ""),
            ("/Users/me", "/Users/me\n/Users/me/two", "~\n~/two", "/Users/me\n/Users/me/two"),
            ("/var/folders/x/macup-tests.AbC123/h", "/var/folders/x/macup-testsXAbC123/h/z", "~/z", "/var/folders/x/macup-testsXAbC123/h/z"),
            ("/var/folders/x/macup-tests.AbC123/h", "~/Code", "~/Code", "/var/folders/x/macup-tests.AbC123/h/Code"),
            ("/var/folders/x/macup-tests.AbC123/h", "/Users/me", "/Users/me", "/Users/me"),
            ("/Users/a&b", "~", "~", "/Users/a~b"),
            ("/Users/a&b", "~/Code", "~/Code", "/Users/a~b/Code"),
            ("/tmp/h.x", "/tmp/hXx/a", "~/a", "/tmp/hXx/a"),
            ("/tmp/h.x", "/tmp/h.x/b", "~/b", "/tmp/h.x/b"),
            ("/tmp/h.x", "~other/x", "~other/x", "/tmp/h.xother/x"),
        ]
        for example in cases {
            let paths = Paths(home: example.home)
            XCTAssertEqual(paths.tildify(example.path), example.tildified, "tildify \(example.path.debugDescription) with HOME=\(example.home)")
            XCTAssertEqual(paths.expand(example.path), example.expanded, "expand \(example.path.debugDescription) with HOME=\(example.home)")
        }
    }

    /// Printf as bash's printf builtin, taken as $(…): the format reused for extra arguments, bad numbers as 0, escapes.
    func testPrintf() {
        let cases: [(format: String, arguments: [String], printed: String)] = [
            ("%s", ["a"], "a"), ("%s and %s", ["a"], "a and "), ("%s=%d", ["x", "12"], "x=12"), ("%d%%", ["7"], "7%"), ("a%sb", ["1", "2", "3"], "a1ba2ba3b"),
            ("%s: %s → %s", ["Foo", "1.0", "1.1"], "Foo: 1.0 → 1.1"), ("no args", ["extra"], "no args"), ("%d", [""], "0"), ("%d", ["0x1F"], "31"),
            ("%d", ["010"], "8"), ("%d", [" 42"], "42"), ("tab\\there\\n", [], "tab\there"), ("100%", [], "100"), ("%s%%)", ["5"], "5%)"),
            ("\\101\\x41", [], "AA"), ("%d", ["1.5"], "0"), ("%d|%d", ["3 ", "12abc"], "0|0"), ("-x %s", ["a"], ""),
            ("Mode: %s · macup %s · took %s", ["check", "2.9.2", "0m 1s"], "Mode: check · macup 2.9.2 · took 0m 1s"),
        ]
        for example in cases {
            XCTAssertEqual(Bash.substitution(Printf.format(example.format, example.arguments)), example.printed, "printf \(example.format) \(example.arguments)")
        }
    }

    var translations: [String: [String: String]] {
        (try? JSONSerialization.jsonObject(with: Data(Checkout.read("src/i18n/translations.json").utf8))) as? [String: [String: String]] ?? [:]
    }

    func testTranslationsAndFallback() {
        let uk = I18n(lang: .uk, translations: translations)
        XCTAssertEqual(uk.translate("TASK"), translations["TASK"]?["uk"])
        XCTAssertEqual(uk.translate("not a message"), "not a message")
        XCTAssertEqual(I18n(lang: .en, translations: translations).translate("TASK"), "TASK")
        XCTAssertEqual(uk.format("Language: %s", Lang.uk.name), Printf.format(translations["Language: %s"]!["uk"]!, ["Українська"]))
        XCTAssertEqual(I18n(lang: .ru, translationsJSON: Checkout.read("src/i18n/translations.json")).translate("STATE"), translations["STATE"]?["ru"])
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

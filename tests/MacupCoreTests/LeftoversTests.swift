@testable import MacupCore
import XCTest

final class LeftoversTests: XCTestCase {
    var home = ""

    override func setUpWithError() throws {
        home = (NSTemporaryDirectory() as NSString).resolvingSymlinksInPath + "/macup-lo-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: home + "/.config/macup", withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(atPath: home) }

    func makeRun(_ argv: [String] = ["check"], config: String = "") throws -> Run {
        try config.write(toFile: home + "/.config/macup/config", atomically: true, encoding: .utf8)
        let env = try Env(["HOME": home, "PATH": "/usr/bin:/bin", "MACUP_PATH": "keep", "MACUP_SYSLIB": home + "/SysLib"])
        let arguments = try Arguments.parse(argv)
        let settings = Settings(config: Config(env: env), env: env, cliSkip: arguments.cliSkip, cliOnly: arguments.cliOnly, cliEnable: arguments.cliEnable, cliLevel: arguments.level)
        let out = Output(i18n: I18n(lang: .en, translations: [:]), colors: .off, fd: open("/dev/null", O_WRONLY))
        return Run(env: env, arguments: arguments, settings: settings, shell: Shell(env: env), out: out, report: Report(path: home + "/report.md", body: home + "/body"),
                   lock: RunLock(dir: home + "/lock", held: false), started: Date(), previous: "")
    }

    /// vendor_of, lc and cap as 2.9's bash gave them: cap leaves an id whose first letter is not ASCII empty.
    func testNamesAreBash() throws {
        let ids: [(id: String, vendor: String, lc: String, cap: String)] = [
            ("ai.perplexity.CometUpdater", "ai.perplexity", "ai.perplexity.cometupdater", "Ai.perplexity.CometUpdater"),
            ("io.github.Foo.agent", "io.github.foo", "io.github.foo.agent", "Io.github.Foo.agent"), ("io.github", "", "io.github", "Io.github"),
            ("io.github.", "", "io.github.", "Io.github."), ("com", "", "com", "Com"), ("", "", "", ""), (".x.y", "", ".x.y", ".x.y"), ("a..b", "", "a..b", "A..b"),
            ("uk.co.Bank.app", "uk.co.bank", "uk.co.bank.app", "Uk.co.Bank.app"), ("Привет.Мир.x", "привет.мир", "привет.мир.x", ""),
            ("ÉCOLE.İx.y", "école.ix", "école.ix.y", ""), ("com.electron.App", "com.electron.app", "com.electron.app", "Com.electron.App"),
        ]
        for test in ids {
            XCTAssertEqual(Leftovers.vendorOf(test.id), test.vendor, test.id)
            XCTAssertEqual(Leftovers.lc(test.id), test.lc, test.id)
            XCTAssertEqual(Leftovers.capitalized(test.id), test.cap, test.id)
        }
    }

    func testNameOKIsBash() throws {
        let names = ["mac helper": false, "app": false, "helper app": true, "comet": false, "": false, "data cache": false, "cache": false]
        let lookup = Leftovers.Taken(apps: [Array("comet".utf8)], apple: [])
        for (name, answer) in names { XCTAssertEqual(Leftovers.nameOK(lookup, name), answer, name) }
    }

    func testOuterIsBash() throws {
        let lists = ["/a/b\n/a\n/a b/c\n/a/b/c": "/a\n/a b/c", "\n/x/y/\n/x/y\n/x": "/x", "/a/b/../c\n/a/bb\n/a/b": "/a/b\n/a/bb", "/Ä/x\n/A/x\n/a": "/A/x\n/a\n/Ä/x"]
        for (list, answer) in lists { XCTAssertEqual(Leftovers.outer(list), answer, list) }
    }

    func testPlistValuesArePlutil() throws {
        let file = home + "/test.plist"
        try """
        <?xml version="1.0"?><plist version="1.0"><dict><key>A</key><real>3600</real><key>B</key><true/><key>C</key><integer>3600</integer>\
        <key>D</key><dict/><key>E</key><array><string>x/y</string><string>z,w</string></array><key>F</key><string>a/b"c</string>\
        <key>G</key><string></string><key>H</key><false/><key>I</key><dict><key>b</key><true/><key>C</key><true/><key>_x</key><true/></dict>\
        <key>J</key><date>2020-01-01T00:00:00Z</date><key>K</key><data>AAEC</data>\
        <key>AssociatedBundleIdentifiers</key><array><string>com.A.b</string><string>a"b/c\\d</string><integer>5</integer><true/><array><string>n</string></array></array></dict></plist>
        """.write(toFile: file, atomically: true, encoding: .utf8)
        let keys: KeyValuePairs = ["A": "3600.000000", "B": "true", "C": "3600", "D": "", "E": "2", "F": "a/b\"c", "E.0": "x/y", "E.1": "z,w", "E.2": "NONE", "G": "",
                                   "H": "false", "I": "_x\nb\nC", "J": "2020-01-01T00:00:00Z", "K": "AAEC", "Z": "NONE", "F.x": "NONE", "AssociatedBundleIdentifiers": "5"]
        let root = Leftovers.plist(file)
        for (key, answer) in keys { XCTAssertEqual(Leftovers.raw(root, key) ?? "NONE", answer, key) }
        XCTAssertEqual(Leftovers.associatedIDs(root).joined(separator: "\n"), #"com.A.b\#na\b\/c\\d\#n5\#ntrue\#nn"#)
        XCTAssertNil(Leftovers.plist(home + "/.config/macup/config"), "not a plist: what plutil -lint refuses")
        let dated = home + "/dated.plist"
        try "<?xml version=\"1.0\"?><plist version=\"1.0\"><dict><key>AssociatedBundleIdentifiers</key><array><string>com.x</string><date>2020-01-01T00:00:00Z</date></array></dict></plist>"
            .write(toFile: dated, atomically: true, encoding: .utf8)
        XCTAssertEqual(Leftovers.associatedIDs(Leftovers.plist(dated)), [])
    }

    func testOwnFolderIsBash() throws {
        let support = home + "/Library/Application Support", sysSupport = home + "/SysLib/Application Support"
        for folder in ["\(support)/Vendor/Updater/bin", "\(support)/Flat", "\(sysSupport)/Sys/svc/bin", "\(home)/Library/Vendor/Sub", "\(home)/elsewhere/sub"] {
            try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        }
        try FileManager.default.createSymbolicLink(atPath: "\(support)/Linked", withDestinationPath: "\(home)/elsewhere")
        let programs: KeyValuePairs = [
            "\(support)/Vendor/Updater/bin/u": "\(support)/Vendor/Updater", "\(support)/Vendor/Updater/u": "\(support)/Vendor/Updater", "\(support)/Flat/updater": "",
            "\(support)/Vendor/Gone/u": "", "\(sysSupport)/Sys/svc/bin/s": "\(sysSupport)/Sys/svc", "\(home)/Library/Vendor/Sub/x": "\(home)/Library/Vendor/Sub",
            "\(support)/Linked/sub/x": "", "/opt/x/y/z": "", "\(support)//a/b": "",
        ]
        let run = try makeRun()
        for (program, answer) in programs { XCTAssertEqual(Leftovers.ownFolder(run, program), answer, program) }
    }

    func testDevContainersAreBash() throws {
        let run = try makeRun(config: "dev_container_prefixes = dev.me, com.apple.x,COM.APPLE,bad prefix,two.parts.ok nodot\n")
        let containers = home + "/Library/Containers"
        let paths: KeyValuePairs = [
            "\(containers)/dev.me": true, "\(containers)/dev.me.App": true, "\(containers)/dev.meX": false, "\(containers)/two.parts.ok.x": true,
            "\(containers)/com.apple.x.y": false, "\(containers)/dev.me.a b": false, "\(containers)/dev.me/sub": false, "\(home)/elsewhere/dev.me": false, "\(containers)/": false,
        ]
        XCTAssertEqual(Leftovers.devPrefixes(run), ["dev.me", "two.parts.ok"])
        for (path, answer) in paths { XCTAssertEqual(Leftovers.devContainer(run, path), answer, path) }
    }

    func testAppForAndNewestAreBash() throws {
        let fm = FileManager.default
        try fm.createDirectory(atPath: home + "/bin", withIntermediateDirectories: true)
        try "#!/bin/bash\nwhile read -r id; do [ \"$1\" = \"kMDItemCFBundleIdentifier == '$id'c\" ] && echo \"/Apps/$id.app\"; done <\"$HOME/ids\"\nexit 0\n"
            .write(toFile: home + "/bin/mdfind", atomically: true, encoding: .utf8)
        chmod(home + "/bin/mdfind", 0o755)
        try "dev.app\nsolo.one-x\n".write(toFile: home + "/ids", atomically: true, encoding: .utf8)
        let ids: KeyValuePairs = ["dev.app": true, "dev.app.share": true, "dev.app-LaunchAtLoginHelper": true, "dev.apps": false, "other.x.y": false, "dev": false,
                                  "solo.one-x.z": true, "solo.one-y": false]
        let containers: KeyValuePairs = ["\(home)/c/full": "2023-11-14", "\(home)/c/empty": "2022-04-15", "\(home)/c/marker": "2022-04-15"]
        for (container, _) in containers { try fm.createDirectory(atPath: container + "/sub", withIntermediateDirectories: true) }
        fm.createFile(atPath: home + "/c/full/sub/old", contents: nil, attributes: [.modificationDate: Date(timeIntervalSince1970: 1_600_000_000)])
        fm.createFile(atPath: home + "/c/full/new", contents: nil, attributes: [.modificationDate: Date(timeIntervalSince1970: 1_700_000_000)])
        fm.createFile(atPath: home + "/c/marker/.com.apple.containermanagerd.metadata.plist", contents: nil, attributes: [.modificationDate: Date(timeIntervalSince1970: 1_750_000_000)])
        for (container, _) in containers { try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_650_000_000)], ofItemAtPath: container) }
        let run = try makeRun()
        run.shell.vars["PATH"] = "\(home)/bin:/usr/bin:/bin"
        for (id, answer) in ids { XCTAssertEqual(Leftovers.appFor(run, id), answer, id) }
        for (container, answer) in containers { XCTAssertEqual(Leftovers.newest(run, container), answer, container) }
    }

    /// strcoll ties the Cyrillic and CJK names with each other: sort -u keeps the first of each tie of the same length.
    /// The expected lines are what `sort -u -t'|' -k1,1` (by key) and `sort -u` (whole) printed in each locale.
    func testSortUniqueIsSort() throws {
        let lines = ["b|2", "a|1", "b|1", "B|3", "é|4", "e\u{301}|6", "e|5", "б|7", "а|8", "аа|9", "日本|10", "中文|11", "b|12"]
        let pairs = lines.map { line -> (String, String) in let parts = line.split(separator: "|"); return (String(parts[0]), String(parts[1])) }
        let sorts: [(vars: [String: String], byKey: String, whole: String)] = [
            (["LANG": "en_US.UTF-8"], "б|7\nаа|9\na|1\nb|2\nB|3\ne|5\ne\u{301}|6\né|4", "日本|10\n中文|11\nб|7\nа|8\nаа|9\na|1\nb|1\nb|12\nb|2\nB|3\né|4\ne|5\ne\u{301}|6"),
            (["LANG": "uk_UA.UTF-8"], "é|4\n日本|10\na|1\nb|2\nB|3\ne|5\ne\u{301}|6\nа|8\nаа|9\nб|7", "日本|10\n中文|11\né|4\na|1\nb|1\nb|12\nb|2\nB|3\ne|5\ne\u{301}|6\nа|8\nаа|9\nб|7"),
            (["LC_ALL": "C"], "B|3\na|1\nb|2\ne|5\ne\u{301}|6\né|4\nа|8\nаа|9\nб|7\n中文|11\n日本|10", "B|3\na|1\nb|1\nb|12\nb|2\ne|5\ne\u{301}|6\né|4\nа|8\nаа|9\nб|7\n中文|11\n日本|10"),
        ]
        defer { Names.toolLocale = nil }
        for sort in sorts {
            Names.setLocale(try Env(["HOME": home, "LC_CTYPE": "en_US.UTF-8"].merging(sort.vars) { $1 }))
            XCTAssertEqual(Array(Leftovers.sortedUnique(pairs, key: \.0).map { "\($0.0)|\($0.1)" }.joined(separator: "\n").utf8), Array(sort.byKey.utf8), "\(sort.vars)")
            XCTAssertEqual(Array(Leftovers.sortedUnique(lines).joined(separator: "\n").utf8), Array(sort.whole.utf8), "\(sort.vars)")
        }
    }

    func testLockedEmptyFileIsSkipped() throws {
        let file = home + "/locked.plist"
        FileManager.default.createFile(atPath: file, contents: Data())
        XCTAssertFalse(Leftovers.locked(file))
        XCTAssertEqual(chflags(file, UInt32(UF_IMMUTABLE)), 0)
        defer { chflags(file, 0) }
        XCTAssertTrue(Leftovers.locked(file))
    }

    /// strcoll ties дім and дом at the same length: bash's `sort -u` kept one of them, and the other app's data could look orphaned.
    func testTakenKeepsNamesStrcollTies() throws {
        let run = try makeRun()
        defer { Names.bashLocale = nil; Names.toolLocale = nil }
        Names.setLocale(try Env(["HOME": home, "LANG": "en_US.UTF-8", "LC_CTYPE": "en_US.UTF-8"]))
        XCTAssertEqual(Leftovers.sortedUnique(["дім", "дом"]).count, 1, "the tie bash's sort -u merges")
        let state = Leftovers.State(interactive: false)
        state.apps = [Leftovers.App(id: "com.example.home", path: "/Applications/дім.app"), Leftovers.App(id: "com.example.house", path: "/Applications/дом.app")]
        let names = Leftovers.taken(run, state)
        XCTAssertFalse(Leftovers.nameOK(names, "дім"))
        XCTAssertFalse(Leftovers.nameOK(names, "дом"))
    }
}

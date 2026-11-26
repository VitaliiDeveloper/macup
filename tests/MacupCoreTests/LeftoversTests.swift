@testable import MacupCore
import XCTest

final class LeftoversTests: XCTestCase {
    var home = ""

    override func setUpWithError() throws {
        home = (NSTemporaryDirectory() as NSString).resolvingSymlinksInPath + "/macup-lo-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: home + "/.config/macup", withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(atPath: home) }

    /// leftovers.sh up to the sizes section (only definitions), and cleanup.sh's dev_prefixes and dev_container.
    var prelude: String {
        let leftovers = BashOracle.read("src/leftovers.sh").components(separatedBy: "\n").prefix { !$0.contains(" SIZES (never deleted)") }
        return "SCHED_LABEL=com.vitaliideveloper.macup\n" + leftovers.joined(separator: "\n") + "\n"
            + BashOracle.function("dev_prefixes", in: "src/cleanup.sh") + BashOracle.read("src/cleanup.sh").components(separatedBy: "\n")
            .drop { !$0.hasPrefix("dev_container(){") }.prefix { !$0.hasPrefix("in_projects(){") }.joined(separator: "\n") + "\n"
    }

    func makeRun(_ argv: [String] = ["check"], config: String = "") throws -> Run {
        try config.write(toFile: home + "/.config/macup/config", atomically: true, encoding: .utf8)
        let env = try Env(["HOME": home, "PATH": "/usr/bin:/bin", "MACUP_PATH": "keep", "MACUP_SYSLIB": home + "/SysLib"])
        let arguments = try Arguments.parse(argv)
        let settings = Settings(config: Config(env: env), env: env, cliSkip: arguments.cliSkip, cliOnly: arguments.cliOnly, cliEnable: arguments.cliEnable, cliLevel: arguments.level)
        let out = Output(i18n: I18n(lang: .en, translations: [:]), colors: .off, fd: open("/dev/null", O_WRONLY))
        return Run(env: env, arguments: arguments, settings: settings, shell: Shell(env: env), out: out, report: Report(path: home + "/report.md", body: home + "/body"),
                   lock: RunLock(dir: home + "/lock", held: false), started: Date(), previous: "")
    }

    func testNamesAreBash() throws {
        let ids = ["ai.perplexity.CometUpdater", "io.github.Foo.agent", "io.github", "io.github.", "com", "", ".x.y", "a..b", "uk.co.Bank.app",
                   "Привет.Мир.x", "ÉCOLE.İx.y", "com.electron.App"]
        let bash = try BashOracle.run(ids.flatMap { ["vendor_of \(BashOracle.quoted($0))", "lc \(BashOracle.quoted($0))", "cap \(BashOracle.quoted($0))"] }, prelude: prelude)
        for (index, id) in ids.enumerated() {
            XCTAssertEqual(Leftovers.vendorOf(id), bash[index * 3], id)
            XCTAssertEqual(Leftovers.lc(id), bash[index * 3 + 1], id)
            XCTAssertEqual(Leftovers.capitalized(id), bash[index * 3 + 2], id)
        }
    }

    func testNameOKIsBash() throws {
        let names = ["mac helper", "app", "helper app", "comet", "", "data cache", "cache"]
        let bash = try BashOracle.run(names.map { "name_ok \(BashOracle.quoted($0)) && echo yes || echo no" }, prelude: prelude + "LO_NAMES=comet\nLO_APPLE=\n")
        let lookup = Leftovers.Names(apps: [Array("comet".utf8)], apple: [])
        for (name, answer) in zip(names, bash) { XCTAssertEqual(Leftovers.nameOK(lookup, name) ? "yes" : "no", answer, name) }
    }

    func testOuterIsBash() throws {
        let lists = ["/a/b\n/a\n/a b/c\n/a/b/c", "\n/x/y/\n/x/y\n/x", "/a/b/../c\n/a/bb\n/a/b", "/Ä/x\n/A/x\n/a"]
        let bash = try BashOracle.run(lists.map { "outer \(BashOracle.quoted($0))" }, prelude: prelude)
        for (list, answer) in zip(lists, bash) { XCTAssertEqual(Leftovers.outer(list), answer, list) }
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
        let keys = ["A", "B", "C", "D", "E", "F", "E.0", "E.1", "E.2", "G", "H", "I", "J", "K", "Z", "F.x", "AssociatedBundleIdentifiers"]
        let bash = try BashOracle.run(keys.map { "pl \($0) \(BashOracle.quoted(file)) || echo NONE" } + ["assoc_ids \(BashOracle.quoted(file))"], prelude: prelude)
        let root = Leftovers.plist(file)
        for (key, answer) in zip(keys, bash) { XCTAssertEqual(Leftovers.raw(root, key) ?? "NONE", answer, key) }
        XCTAssertEqual(Leftovers.associatedIDs(root).joined(separator: "\n"), bash.last)
        XCTAssertNil(Leftovers.plist(home + "/.config/macup/config"), "not a plist: what plutil -lint refuses")
        let dated = home + "/dated.plist"
        try "<?xml version=\"1.0\"?><plist version=\"1.0\"><dict><key>AssociatedBundleIdentifiers</key><array><string>com.x</string><date>2020-01-01T00:00:00Z</date></array></dict></plist>"
            .write(toFile: dated, atomically: true, encoding: .utf8)
        XCTAssertEqual(Leftovers.associatedIDs(Leftovers.plist(dated)).joined(separator: "\n"), try BashOracle.run(["assoc_ids \(BashOracle.quoted(dated))"], prelude: prelude)[0])
    }

    func testOwnFolderIsBash() throws {
        let support = home + "/Library/Application Support", sysSupport = home + "/SysLib/Application Support"
        for folder in ["\(support)/Vendor/Updater/bin", "\(support)/Flat", "\(sysSupport)/Sys/svc/bin", "\(home)/Library/Vendor/Sub", "\(home)/elsewhere/sub"] {
            try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        }
        try FileManager.default.createSymbolicLink(atPath: "\(support)/Linked", withDestinationPath: "\(home)/elsewhere")
        let programs = ["\(support)/Vendor/Updater/bin/u", "\(support)/Vendor/Updater/u", "\(support)/Flat/updater", "\(support)/Vendor/Gone/u",
                        "\(sysSupport)/Sys/svc/bin/s", "\(home)/Library/Vendor/Sub/x", "\(support)/Linked/sub/x", "/opt/x/y/z", "\(support)//a/b"]
        let bash = try BashOracle.run(programs.map { "lo_dir \(BashOracle.quoted($0))" }, home: home, env: ["MACUP_SYSLIB": home + "/SysLib"], prelude: prelude)
        let run = try makeRun()
        for (program, answer) in zip(programs, bash) { XCTAssertEqual(Leftovers.ownFolder(run, program), answer, program) }
    }

    func testDevContainersAreBash() throws {
        let prefixes = "dev.me, com.apple.x,COM.APPLE,bad prefix,two.parts.ok nodot"
        let run = try makeRun(config: "dev_container_prefixes = \(prefixes)\n")
        let containers = home + "/Library/Containers"
        let paths = ["\(containers)/dev.me", "\(containers)/dev.me.App", "\(containers)/dev.meX", "\(containers)/two.parts.ok.x", "\(containers)/com.apple.x.y",
                     "\(containers)/dev.me.a b", "\(containers)/dev.me/sub", "\(home)/elsewhere/dev.me", "\(containers)/"]
        let bash = try BashOracle.run(["dev_prefixes"] + paths.map { "dev_container \(BashOracle.quoted($0)) && echo yes || echo no" }, home: home,
                                      prelude: "DEV_PREFIXES=\(BashOracle.quoted(prefixes))\n" + prelude)
        XCTAssertEqual(Leftovers.devPrefixes(run).joined(separator: "\n"), bash[0])
        for (path, answer) in zip(paths, bash.dropFirst()) { XCTAssertEqual(Leftovers.devContainer(run, path) ? "yes" : "no", answer, path) }
    }

    func testAppForAndNewestAreBash() throws {
        let fm = FileManager.default
        try fm.createDirectory(atPath: home + "/bin", withIntermediateDirectories: true)
        try "#!/bin/bash\nwhile read -r id; do [ \"$1\" = \"kMDItemCFBundleIdentifier == '$id'c\" ] && echo \"/Apps/$id.app\"; done <\"$HOME/ids\"\nexit 0\n"
            .write(toFile: home + "/bin/mdfind", atomically: true, encoding: .utf8)
        chmod(home + "/bin/mdfind", 0o755)
        try "dev.app\nsolo.one-x\n".write(toFile: home + "/ids", atomically: true, encoding: .utf8)
        let ids = ["dev.app", "dev.app.share", "dev.app-LaunchAtLoginHelper", "dev.apps", "other.x.y", "dev", "solo.one-x.z", "solo.one-y"]
        let containers = ["\(home)/c/full", "\(home)/c/empty", "\(home)/c/marker"]
        for container in containers { try fm.createDirectory(atPath: container + "/sub", withIntermediateDirectories: true) }
        fm.createFile(atPath: containers[0] + "/sub/old", contents: nil, attributes: [.modificationDate: Date(timeIntervalSince1970: 1_600_000_000)])
        fm.createFile(atPath: containers[0] + "/new", contents: nil, attributes: [.modificationDate: Date(timeIntervalSince1970: 1_700_000_000)])
        fm.createFile(atPath: containers[2] + "/.com.apple.containermanagerd.metadata.plist", contents: nil, attributes: [.modificationDate: Date(timeIntervalSince1970: 1_750_000_000)])
        for container in containers { try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_650_000_000)], ofItemAtPath: container) }
        let cleaners = BashOracle.read("src/cleaners.sh").components(separatedBy: "\n")
        let appFor = cleaners.drop { !$0.hasPrefix("app_for(){") }.prefix { !$0.hasPrefix("done; }") }.joined(separator: "\n") + "\ndone; }\n"
        let bash = try BashOracle.run(ids.map { "app_for \($0) && echo yes || echo no" } + containers.map { "newest \(BashOracle.quoted($0))" }, home: home,
                                      env: ["PATH": "\(home)/bin:/usr/bin:/bin"], prelude: appFor + BashOracle.function("newest", in: "src/cleaners.sh"))
        let run = try makeRun()
        run.shell.vars["PATH"] = "\(home)/bin:/usr/bin:/bin"
        for (id, answer) in zip(ids, bash) { XCTAssertEqual(Leftovers.appFor(run, id) ? "yes" : "no", answer, id) }
        for (container, answer) in zip(containers, bash.dropFirst(ids.count)) { XCTAssertEqual(Leftovers.newest(run, container), answer, container) }
    }

    func testVendorListSortsAsSort() throws {
        let lines = ["b|2", "a|1", "b|1", "B|3", "e|5"]   // ASCII only until the shared collation sets LC_CTYPE too
        let locale = ProcessInfo.processInfo.environment.filter { ["LANG", "LC_ALL", "LC_COLLATE"].contains($0.key) }   // the collation Swift sorts in
        let bash = try BashOracle.run(["printf '%s\\n' \(lines.map(BashOracle.quoted).joined(separator: " ")) | sort -u -t'|' -k1,1"], env: locale)
        let pairs = lines.map { line -> (String, String) in let parts = line.split(separator: "|"); return (String(parts[0]), String(parts[1])) }
        XCTAssertEqual(Leftovers.sortedUnique(pairs, key: \.0).map { "\($0.0)|\($0.1)" }.joined(separator: "\n"), bash[0])
    }

    func testLockedEmptyFileIsSkipped() throws {
        let file = home + "/locked.plist"
        FileManager.default.createFile(atPath: file, contents: Data())
        XCTAssertFalse(Leftovers.locked(file))
        XCTAssertEqual(chflags(file, UInt32(UF_IMMUTABLE)), 0)
        defer { chflags(file, 0) }
        XCTAssertTrue(Leftovers.locked(file))
    }

    func testRoutes() throws {
        let environment = try Env(["HOME": home, "PATH": "/usr/bin:/bin"])
        func swift(_ line: String, terminal: Bool = false) -> Bool {
            if case .swift = Router.route(line.split(separator: " ").map(String.init), env: environment, terminal: terminal) { return true }
            return false
        }
        XCTAssertTrue(swift("check --only check.startup,clean.orphan_agents,clean.orphan_data"))
        XCTAssertTrue(swift("check --only check.startup", terminal: true), "no clean task: no pick")
        XCTAssertFalse(swift("check --only clean.orphan_agents", terminal: true), "the pick")
        XCTAssertTrue(swift("clean --only clean.orphan_agents,clean.orphan_data", terminal: true), "only ever cleaned when picked")
        XCTAssertTrue(swift("check --only clean.dev_containers"), "nothing to scan without a terminal")
        XCTAssertFalse(swift("clean --only clean.dev_containers", terminal: true), "the scan needs lsof")
    }

    /// registerDevContainers stops at a preconditionFailure past its guard: no run the Swift build takes may pass the guard.
    func testNoRouteReachesTheDevContainerScan() throws {
        try "dev_container_prefixes = dev.me\n".write(toFile: home + "/.config/macup/config", atomically: true, encoding: .utf8)
        let environment = try Env(["HOME": home, "PATH": "/usr/bin:/bin"])
        for action in ["check", "clean", "all", "update", ""] {
            for selection in ["--only clean.dev_containers", "--enable clean.dev_containers", "--only clean.dev_containers,clean.orphan_data,check.startup"] {
                for flags in ["", "--quiet", "--json", "--level aggressive"] {
                    for terminal in [false, true] {
                        let argv = "\(action) \(selection) \(flags)".split(separator: " ").map(String.init)
                        guard case .swift(let arguments) = Router.route(argv, env: environment, terminal: terminal) else { continue }
                        XCTAssertFalse(terminal && !arguments.quiet, "\(argv) on a terminal reaches the dev container scan")
                    }
                }
            }
        }
    }
}

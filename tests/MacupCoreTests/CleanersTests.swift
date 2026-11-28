@testable import MacupCore
import XCTest

final class CleanersTests: XCTestCase {
    var home = ""

    override func setUp() {
        home = (NSTemporaryDirectory() as NSString).resolvingSymlinksInPath + "/macup-cleaners-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: home, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(atPath: home) }

    func make(_ relative: String, _ contents: String? = nil) {
        let path = "\(home)/\(relative)"
        if let contents {
            try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: path, contents: Data(contents.utf8))
        } else {
            try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        }
    }

    func link(_ relative: String, to target: String) {
        try? FileManager.default.createSymbolicLink(atPath: "\(home)/\(relative)", withDestinationPath: target)
    }

    /// Each line split on "|" and on a tab into three fields, as bash's `IFS=… read -r one two three` does.
    func testReadIsBashRead() throws {
        let cases = [
            ("x|y|z|", "x/y/z", "x|y|z|//"), ("x|y|z|w|", "x/y/z|w|", "x|y|z|w|//"), ("x|y|", "x/y/", "x|y|//"), ("|y| z ", "/y/ z ", "|y| z //"),
            ("x|y|z||", "x/y/z||", "x|y|z||//"), ("", "//", "//"), ("a", "a//", "a//"), ("a||b", "a//b", "a||b//"),
            ("\tx\t\ty\tz\t", "\tx\t\ty\tz\t//", "x/y/z"), ("x\ty", "x\ty//", "x/y/"), ("\t\t", "\t\t//", "//"), (" a\tb c \t", " a\tb c \t//", " a/b c /"),
            ("a\t\tb\t\tc\t\td\t", "a\t\tb\t\tc\t\td\t//", "a/b/c\t\td"),
        ]
        for (line, pipe, tab) in cases {
            XCTAssertEqual(Cleaners.read(line, "|", 3).joined(separator: "/"), pipe, "| \(line.debugDescription)")
            XCTAssertEqual(Cleaners.read(line, "\t", 3).joined(separator: "/"), tab, "tab \(line.debugDescription)")
        }
    }

    func testRuntimeNameIsSed() throws {
        let cases = [("com.apple.CoreSimulator.SimRuntime.iOS-17-2", "iOS 17.2"), ("com.apple.CoreSimulator.SimRuntime.watchOS-10-0-1", "watchOS 10.0.1"),
                     ("SimRuntime.x-SimRuntime.tvOS-9", "tvOS 9"), ("plain", "plain"), ("", ""), ("-n", ""), ("a-b", "a b")]
        for (identifier, expected) in cases { XCTAssertEqual(Cleaners.runtimeName(identifier), expected, identifier) }
    }

    func testSimListIsPython() throws {
        let devices = #"{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-17-2":[{"udid":"A1","state":"Shutdown","name":"Tab\there"},{"udid":"B2","state":"Booted","name":"x"}],"rt.watchOS-10-0":[{"udid":"C3","state":"Shutdown","name":"w"}]}}"#
        let runtimes = #"{"R1":{"runtimeIdentifier":"com.apple.CoreSimulator.SimRuntime.iOS-17-2","sizeBytes":7000000000,"lastUsedAt":"2026-01-02T10:00:00Z","version":"17.2"},"R2":{"runtimeIdentifier":"rt.watchOS-10-0","sizeBytes":-3000.7,"version":10.0},"R3":{"deletable":false},"R4":{"deletable":0,"sizeBytes":5},"R5":{"lastUsedAt":"","sizeBytes":"42"}}"#
        let deviceLines = "D\tA1\tShutdown\tcom.apple.CoreSimulator.SimRuntime.iOS-17-2\tTab here\nD\tB2\tBooted\tcom.apple.CoreSimulator.SimRuntime.iOS-17-2\tx\nD\tC3\tShutdown\trt.watchOS-10-0\tw"
        let runtimeLines = "R\tR1\t6835937\t2026-01-02\t0\t0\tiOS\t17.2\nR\tR2\t-3\t-\t0\t0\twatchOS\t10.0\nR\tR5\t0\t-\t0\t0\t\t?"
        let cases = [
            (devices + "\n@@\n" + runtimes, deviceLines + "\nR\tR1\t6835937\t2026-01-02\t2\t1\tiOS\t17.2\nR\tR2\t-3\t-\t1\t0\twatchOS\t10.0\nR\tR5\t0\t-\t0\t0\t\t?"),
            ("\n@@\n", ""), ("garbage\n@@\n" + runtimes, runtimeLines), (devices + "\n@@\n[]", deviceLines), (#"{"devices":[]}"# + "\n@@\n" + runtimes, ""),
            (#"{"devices":{"r":[1]}}"# + "\n@@\n" + runtimes, ""), (#"[1]"# + "\n@@\n" + runtimes, runtimeLines), (devices + "\n@@\n" + #"{"R":{"sizeBytes":null}}"#, deviceLines),
            (devices + "\n@@\n" + #"{"R":{"lastUsedAt":5}}"#, deviceLines), (devices + "\n@@\n" + #"{"R":{"runtimeIdentifier":7}}"#, deviceLines),
            (#"{"devices":{"r":[{"name":3}]}}"# + "\n@@\n{}", ""), (devices + "\n@@\n" + #"{"R":{"sizeBytes":"1.5"}}"#, deviceLines), (#"{"x":"@@"}"# + "\n@@\n{}", ""),
            (#"{"devices":{"a":{},"b":"","c":[{"udid":"U","name":"two\nlines"}]}}"# + "\n@@\n" + #"{"R":{"sizeBytes":" 42\n","version":"1\n2"}}"#,
             "D\tU\t\tc\ttwo\nlines\nR\tR\t0\t-\t0\t0\t\t1\n2"),
            (#"{"devices":{"a":{"k":1},"c":[{"udid":"U"}]}}"# + "\n@@\n{}", ""), (#"{"devices":{"a":"x"}}"# + "\n@@\n{}", ""),
        ]
        for (input, expected) in cases {
            XCTAssertEqual(Cleaners.simList(input).joined(separator: "\n"), expected, input)
        }
    }

    func testWorkspacesArePython() throws {
        let storage = "Library/Application Support/Code/User/workspaceStorage"
        make("Projects/here")
        make("linked-target")
        link("linked", to: "\(home)/linked-target")
        let uris = ["gone": "file://\(home)/Projects/missing", "here": "file://\(home)/Projects/here", "lib": "file://\(home)/Library/Gone/x",
                    "link": "file://\(home)/linked/missing", "host": "file://server\(home)/Projects/missing", "local": "file://localhost\(home)/Projects/per%20cent",
                    "up": "file://\(home)/Projects/../missing", "out": "file:///Volumes/Disk/missing", "web": "vscode-remote://ssh/x",
                    "query": "file://\(home)/Projects/q?x=1#frag", "hash": "file://\(home)/Projects/h#x/y", "bad": "file://\(home)/Projects/%E9%zz",
                    "deep": "file://\(home)/Projects/here/a/b/c", "double": "file://\(home)//Projects/missing", "home": "file://\(home)", "slash": "file://\(home)/",
                    "nfc": "file://\(home)/caf\u{E9}/missing", "nfd": "file://\(home)/Projects/here/cafe\u{301}", "Upper": "FILE://\(home)/x", "tab": "file://\(home)/Proj\\tects/here/x", "newline": "file://\(home)/Projects/here\\n",
                    "zzzz-bracket": "file://[x\(home)/Projects/missing", "zzzzz-after": "file://\(home)/Projects/missing", "pair": "file://[x]\(home)/Projects/missing",
                    "mark": "file://\(home)/Projects/gone/../\u{301}x"]
        for (name, uri) in uris { make("\(storage)/\(name)/workspace.json", #"{"folder": "\#(uri)"}"#) }
        make("\(storage)/ws/workspace.json", #"{"folder": "", "workspace": "file://\#(home)/Projects/w.code-workspace"}"#)
        make("\(storage)/none/workspace.json", #"{"folder": null}"#)
        make("\(storage)/number/workspace.json", #"{"folder": 5}"#)
        make("\(storage)/broken/workspace.json", #"{"folder": "#)
        make("\(storage)/bom/workspace.json", "\u{FEFF}{\"folder\": \"file://\(home)/Projects/missing\"}")
        make("\(storage)/.dot/workspace.json", #"{"folder": "file://\#(home)/Projects/missing"}"#)
        make("\(storage)/file", "")
        link("\(storage)/linked-ws", to: "\(home)/\(storage)/gone")
        // 2.9's helper stopped at the "[x" host, so nothing after zzzz-bracket is listed
        let gone = [".dot", "bad", "deep", "double", "gone", "hash", "local", "nfc", "nfd", "query", "tab", "ws"].map { "\(home)/\(storage)/\($0)" }
        XCTAssertEqual(Cleaners.goneWorkspaces("\(home)/\(storage)", home: home), gone)
        make("\(storage)/zz-array/workspace.json", "[1]")
        make("\(storage)/zzz-after/workspace.json", #"{"folder": "file://\#(home)/Projects/missing"}"#)
        XCTAssertEqual(Cleaners.goneWorkspaces("\(home)/\(storage)", home: home), gone, "a list stops the scan")
    }

    func testProfilesArePython() throws {
        let folder = "Library/MobileDevice/Provisioning Profiles"
        func profile(_ date: String) -> String {
            "bin\u{1}<?xml version=\"1.0\"?><plist version=\"1.0\"><dict><key>ExpirationDate</key><date>\(date)</date></dict></plist>tail"
        }
        make("\(folder)/old.mobileprovision", profile("2020-01-01T00:00:00Z"))
        make("\(folder)/new.provisionprofile", profile("2099-01-01T00:00:00Z"))
        make("\(folder)/b-old.provisionprofile", profile("2001-01-01T00:00:00Z"))
        make("\(folder)/old.txt", profile("2020-01-01T00:00:00Z"))
        make("\(folder)/nodate.mobileprovision", "<?xml version=\"1.0\"?><plist version=\"1.0\"><dict/></plist>")
        make("\(folder)/array.mobileprovision", "<?xml version=\"1.0\"?><plist version=\"1.0\"><array/></plist>")
        make("\(folder)/text.mobileprovision", "no plist")
        make("\(folder)/dir.mobileprovision")
        link("\(folder)/link.mobileprovision", to: "\(home)/\(folder)/old.mobileprovision")
        let expired = ["b-old.provisionprofile", "old.mobileprovision"].map { "\(home)/\(folder)/\($0)" }
        XCTAssertEqual(Cleaners.expiredProfiles(["\(home)/\(folder)", "\(home)/missing"]), expired)
        // 2.9's helper stopped at a folder it could not list
        make("locked")
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: "\(home)/locked")
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: "\(home)/locked") }
        XCTAssertEqual(Cleaners.expiredProfiles(["\(home)/locked", "\(home)/\(folder)"]), [])
        XCTAssertEqual(Cleaners.expiredProfiles(["\(home)/\(folder)", "\(home)/locked"]), expired)
    }

    func testLayoutGroupsArePython() throws {
        let support = "Library/Application Support", caches = "Library/Caches"
        for folder in ["Code/Cache", "Code/Default/GPUCache", "Slack/Partitions/p1/Code Cache", "Arc/User Data/Default/Cache", "Arc/User Data/Profile 1/GPUCache",
                       "Vendor/App/Sub/Cache", "Vendor/App/Sub/Deep/GPUCache", "Plain/Cache", "Plain/Updater.app/Cache", "com.apple.Thing/Cache",
                       "Foo.ShipIt/Cache", "Brave/x/org.sparkle-project.Sparkle/Cache", "a/b/c/d/e/f/Cache", "a/b/c/d/Cache", "Covered/One/Cache"] {
            make("\(support)/\(folder)")
        }
        for file in ["Code/Local State", "Slack/Partitions/p1/Preferences", "Slack/Partitions/p1/Cookies", "Arc/User Data/Local State",
                     "Arc/User Data/Default/History", "Vendor/App/Local State", "Vendor/App/Sub/Deep/Preferences", "Vendor/App/Sub/Deep/DIPS",
                     "Plain/Local State", "Plain/Updater.app/Local State", "a/b/c/d/Local State", "a/b/c/d/e/f/Local State", "Covered/One/Local State"] {
            make("\(support)/\(file)", "")
        }
        for folder in ["Firefox/Profiles/x/cache2", "Mozilla/Profiles/y/cache2", "Arc/User Data/Default/Cache", "Thing/Cache", "cache2", "Slack/GPUCache",
                       "deep/1/2/3/4/5/cache2"] {
            make("\(caches)/\(folder)")
        }
        make("elsewhere/Cache")
        link("\(support)/Linked", to: "\(home)/elsewhere")
        make("\(support)/Firefox/Profiles/x/History", "")
        let covered = "\(home)/\(support)/Covered/One\n\n\(home)/\(caches)/Thing/Cache\n"
        let swift = Cleaners.layoutGroups(support: "\(home)/\(support)", caches: "\(home)/\(caches)", covered: covered).map { group in
            [String(group.level), group.kind, group.name, group.opened.joined(separator: "\u{1F}"), group.paths.joined(separator: "\u{1F}")].joined(separator: "\t")
        }
        func group(_ level: Int, _ kind: String, _ name: String, _ folder: String, _ path: String) -> String {
            [String(level), kind, name, "\(home)/\(support)/\(folder)\u{1F}\(home)/\(caches)/\(folder)", path].joined(separator: "\t")
        }
        XCTAssertEqual(swift, [
            group(1, "app", "Plain", "Plain", "\(home)/\(support)/Plain/Cache"),
            group(1, "app", "Slack", "Slack", "\(home)/\(support)/Slack/Partitions/p1/Code Cache\u{1F}\(home)/\(caches)/Slack/GPUCache"),
            group(1, "app", "Vendor App", "Vendor", "\(home)/\(support)/Vendor/App/Sub/Deep/GPUCache"),
            group(1, "app", "Visual Studio Code", "Code", "\(home)/\(support)/Code/Cache"),
            group(1, "app", "a", "a", "\(home)/\(support)/a/b/c/d/Cache"),
            group(3, "browser", "Arc", "Arc", "\(home)/\(caches)/Arc/User Data/Default/Cache"),
            group(3, "browser", "Firefox", "Firefox", "\(home)/\(caches)/Firefox/Profiles/x/cache2"),
            group(3, "browser", "Mozilla", "Mozilla", "\(home)/\(caches)/Mozilla/Profiles/y/cache2"),
        ])
    }
}

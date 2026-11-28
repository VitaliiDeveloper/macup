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

    func testCleanerRunsRouteToSwift() throws {
        let environment = try Env(["HOME": home + "/none", "PATH": "/usr/bin:/bin"])
        func route(_ line: String) -> String {
            switch Router.route(line.split(separator: " ").map(String.init), env: environment, terminal: false) {
            case .bash: return "bash"
            case .swift: return "swift"
            }
        }
        let registered = Ported.cleaners.tasks.joined(separator: ",")
        XCTAssertEqual(route("check --only \(registered)"), "swift")
        XCTAssertEqual(route("check --level aggressive --only \(registered) --json"), "swift")
        XCTAssertEqual(route("clean --level aggressive --only \(registered)"), "swift")
        XCTAssertEqual(route("check --only clean.trash,clean.dev_containers"), "swift", "dev containers register through the leftovers unit")
    }

    func testReadIsBashRead() throws {
        let lines = ["x|y|z|", "x|y|z|w|", "x|y|", "|y| z ", "x|y|z||", "", "a", "a||b", "\tx\t\ty\tz\t", "x\ty", "\t\t", " a\tb c \t", "a\t\tb\t\tc\t\td\t"]
        for separator in ["|", "\t"] {
            let calls = lines.map { "IFS=\(BashOracle.quoted(separator)) read -r one two three <<< \(BashOracle.quoted($0)); printf '%s/%s/%s' \"$one\" \"$two\" \"$three\"" }
            for (line, answer) in zip(lines, try BashOracle.run(calls)) {
                XCTAssertEqual(Cleaners.read(line, separator.unicodeScalars.first!, 3).joined(separator: "/"), answer, "\(separator.debugDescription) \(line.debugDescription)")
            }
        }
    }

    func testRuntimeNameIsSed() throws {
        let identifiers = ["com.apple.CoreSimulator.SimRuntime.iOS-17-2", "com.apple.CoreSimulator.SimRuntime.watchOS-10-0-1", "SimRuntime.x-SimRuntime.tvOS-9",
                           "plain", "", "-n", "a-b"]
        let bash = try BashOracle.run(identifiers.map { "echo \(BashOracle.quoted($0)) | sed 's/.*SimRuntime\\.//; s/-/ /; s/-/./g'" })
        for (identifier, answer) in zip(identifiers, bash) { XCTAssertEqual(Cleaners.runtimeName(identifier), answer, identifier) }
    }

    func testSimListIsPython() throws {
        let devices = #"{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-17-2":[{"udid":"A1","state":"Shutdown","name":"Tab\there"},{"udid":"B2","state":"Booted","name":"x"}],"rt.watchOS-10-0":[{"udid":"C3","state":"Shutdown","name":"w"}]}}"#
        let runtimes = #"{"R1":{"runtimeIdentifier":"com.apple.CoreSimulator.SimRuntime.iOS-17-2","sizeBytes":7000000000,"lastUsedAt":"2026-01-02T10:00:00Z","version":"17.2"},"R2":{"runtimeIdentifier":"rt.watchOS-10-0","sizeBytes":-3000.7,"version":10.0},"R3":{"deletable":false},"R4":{"deletable":0,"sizeBytes":5},"R5":{"lastUsedAt":"","sizeBytes":"42"}}"#
        let inputs = [devices + "\n@@\n" + runtimes, "\n@@\n", "garbage\n@@\n" + runtimes, devices + "\n@@\n[]", #"{"devices":[]}"# + "\n@@\n" + runtimes,
                      #"{"devices":{"r":[1]}}"# + "\n@@\n" + runtimes, #"[1]"# + "\n@@\n" + runtimes, devices + "\n@@\n" + #"{"R":{"sizeBytes":null}}"#,
                      devices + "\n@@\n" + #"{"R":{"lastUsedAt":5}}"#, devices + "\n@@\n" + #"{"R":{"runtimeIdentifier":7}}"#, #"{"devices":{"r":[{"name":3}]}}"# + "\n@@\n{}",
                      devices + "\n@@\n" + #"{"R":{"sizeBytes":"1.5"}}"#, #"{"x":"@@"}"# + "\n@@\n{}",
                      #"{"devices":{"a":{},"b":"","c":[{"udid":"U","name":"two\nlines"}]}}"# + "\n@@\n" + #"{"R":{"sizeBytes":" 42\n","version":"1\n2"}}"#,
                      #"{"devices":{"a":{"k":1},"c":[{"udid":"U"}]}}"# + "\n@@\n{}", #"{"devices":{"a":"x"}}"# + "\n@@\n{}"]
        for input in inputs {
            XCTAssertEqual(Cleaners.simList(input).joined(separator: "\n"), try BashOracle.python("sim-list", [], input: input, home: home).output, input)
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
                    "zzzz-bracket": "file://[x\(home)/Projects/missing", "zzzzz-after": "file://\(home)/Projects/missing", "pair": "file://[x]\(home)/Projects/missing"]
        for (name, uri) in uris { make("\(storage)/\(name)/workspace.json", #"{"folder": "\#(uri)"}"#) }
        make("\(storage)/ws/workspace.json", #"{"folder": "", "workspace": "file://\#(home)/Projects/w.code-workspace"}"#)
        make("\(storage)/none/workspace.json", #"{"folder": null}"#)
        make("\(storage)/number/workspace.json", #"{"folder": 5}"#)
        make("\(storage)/broken/workspace.json", #"{"folder": "#)
        make("\(storage)/bom/workspace.json", "\u{FEFF}{\"folder\": \"file://\(home)/Projects/missing\"}")
        make("\(storage)/.dot/workspace.json", #"{"folder": "file://\#(home)/Projects/missing"}"#)
        make("\(storage)/file", "")
        link("\(storage)/linked-ws", to: "\(home)/\(storage)/gone")
        let python = { try BashOracle.python("editor-workspaces", ["\(self.home)/\(storage)", self.home], home: self.home).output }
        XCTAssertEqual(Cleaners.goneWorkspaces("\(home)/\(storage)", home: home).joined(separator: "\n"), try python())
        make("\(storage)/zz-array/workspace.json", "[1]")
        make("\(storage)/zzz-after/workspace.json", #"{"folder": "file://\#(home)/Projects/missing"}"#)
        XCTAssertEqual(Cleaners.goneWorkspaces("\(home)/\(storage)", home: home).joined(separator: "\n"), try python(), "Python stops at a list")
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
        let folders = ["\(home)/\(folder)", "\(home)/missing"]
        XCTAssertEqual(Cleaners.expiredProfiles(folders).joined(separator: "\n"), try BashOracle.python("profiles-expired", folders, home: home).output)
        // Python stops at a folder it cannot list
        make("locked")
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: "\(home)/locked")
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: "\(home)/locked") }
        for order in [["\(home)/locked", "\(home)/\(folder)"], ["\(home)/\(folder)", "\(home)/locked"]] {
            XCTAssertEqual(Cleaners.expiredProfiles(order).joined(separator: "\n"), try BashOracle.python("profiles-expired", order, home: home).output, "\(order)")
        }
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
        let tables = ["NAMES": CacheTables.electronCaches.joined(separator: "|"),
                      "APPS": CacheTables.electronApps.map { "\($0.folder)|\($0.app)" }.joined(separator: "\n"),
                      "BRS": CacheTables.browsers.map { "\($0.name)|\($0.app)|\($0.folders.joined(separator: ";"))" }.joined(separator: "\n"), "COVERED": covered]
        let swift = Cleaners.layoutGroups(support: "\(home)/\(support)", caches: "\(home)/\(caches)", covered: covered).map { group in
            [String(group.level), group.kind, group.name, group.opened.joined(separator: "\u{1F}"), group.paths.joined(separator: "\u{1F}")].joined(separator: "\t")
        }
        let python = try BashOracle.python("electron-caches", ["\(home)/\(support)", "\(home)/\(caches)"], home: home, env: tables).output
        XCTAssertEqual(swift.joined(separator: "\n"), python)
        XCTAssertFalse(swift.isEmpty)
    }
}

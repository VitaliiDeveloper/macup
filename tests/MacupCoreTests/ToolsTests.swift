@testable import MacupCore
import XCTest

/// The tools checks against what the bash build runs today: macup_helpers.py for what it parses, bash for the rest.
final class ToolsTests: XCTestCase {
    var home = ""
    var shell: Shell!

    override func setUpWithError() throws {
        home = (NSTemporaryDirectory() as NSString).resolvingSymlinksInPath + "/macup-tools-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: home + "/bin", withIntermediateDirectories: true)
        shell = Shell(env: try Env(["HOME": home, "PATH": "\(home)/bin:/usr/bin:/bin", "MACUP_PATH": "keep"]))
    }

    override func tearDown() { try? FileManager.default.removeItem(atPath: home) }

    /// python3 running `script` (a macup_helpers.py command, or code with -c) with this input: what it prints, as `$(…)` keeps it.
    func python(_ arguments: [String], input: String = "") throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = arguments.first == "-c" ? arguments : [BashOracle.repo + "/src/py/macup_helpers.py"] + arguments
        process.environment = ["HOME": home, "PATH": "\(home)/bin:/usr/bin:/bin", "LC_CTYPE": "en_US.UTF-8"]
        let stdout = Pipe(), stdin = Pipe()
        process.standardOutput = stdout
        process.standardInput = stdin
        process.standardError = FileHandle.nullDevice
        try process.run()
        stdin.fileHandleForWriting.write(Data(input.utf8))
        try stdin.fileHandleForWriting.close()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Bash.substitution(String(decoding: data, as: UTF8.self))
    }

    @discardableResult
    func write(_ text: String, _ name: String, executable: Bool = false) throws -> String {
        let path = name.hasPrefix("/") ? name : "\(home)/\(name)"
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try text.write(toFile: path, atomically: false, encoding: .utf8)
        if executable { chmod(path, 0o755) }
        return path
    }

    func link(_ target: String, _ name: String) throws {
        let path = "\(home)/\(name)"
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: path, withDestinationPath: target)
    }

    func testSimRuntimesAsPythonReadsThem() throws {
        let cases = [
            #"{"B":{"platformIdentifier":"com.apple.platform.iphonesimulator","version":"18.2","sizeBytes":7516192768},"A":{"platformIdentifier":"com.apple.platform.iphonesimulator","version":"17.5","sizeBytes":6979321856},"C":{"platformIdentifier":"com.apple.platform.watchsimulator","version":"11.2"}}"#,
            #"{"A":{"platformIdentifier":"x","sizeBytes":1.5e9},"B":{"version":"1","sizeBytes":true}}"#,
            #"{"A":{"platformIdentifier":"com.apple.platform.xros","version":"2.0","sizeBytes":2048},"B":{"platformIdentifier":"com.apple.platform.xros","version":"10.0","sizeBytes":1024}}"#,
            #"{"A":{"platformIdentifier":"Zplatform","version":"1"},"B":{"platformIdentifier":"aplatform","version":"1"},"C":{"platformIdentifier":"é","version":"1"}}"#,
            #"{"A":{"platformIdentifier":1}}"#, #"{"A":{"platformIdentifier":"a","version":2.0}}"#, #"{"A":{"version":"1"},"B":{"version":1}}"#,
            #"{"A":{"platformIdentifier":"a.b","version":"1","sizeBytes":5},"B":{"platformIdentifier":"a.c","version":"1","sizeBytes":"5"}}"#, #"{"A":{"sizeBytes":"big"}}"#, #"{"A":[]}"#, #"{}"#, #"[]"#, "", "{", "\u{FEFF}{}",
        ]
        for json in cases {
            XCTAssertEqual(Tools.simRuntimes(json), try python(["sim-runtimes"], input: json), json)
        }
    }

    func testCommandsAsPythonScansThem() throws {
        let local = "\(home)/.local/bin", venv = "\(home)/.local/pipx/venvs/tool/bin"
        try write("#!/usr/bin/env macup_no_such_interp\n", ".local/bin/nodecli", executable: true)
        try write("#!/usr/bin/env -S macup_no_such_interp --flag\n", ".npm-global/bin/flagcli", executable: true)
        try write("#!/bin/sh\necho ok\n", ".local/bin/okscript", executable: true)
        try write("#!/usr/bin/env VAR=1 sh\n", ".local/bin/withvar", executable: true)
        try write("#!/usr/bin/env\tmacup_tab\u{A0}interp\r\n", ".local/bin/crlf", executable: true)
        try write("#!\n", ".local/bin/empty", executable: true)
        try write("#!/usr/bin/env\n", ".local/bin/bareenv", executable: true)
        try write("#!" + String(repeating: "x", count: 300) + "\n", ".local/bin/long", executable: true)
        try write("#!/usr/bin/env macup_no_such_interp\n", ".local/bin/notexec")
        try write("#!/bin/café\n", ".local/bin/café", executable: true)
        try write("#!/bin/cafe\u{301}\n", ".local/bin/cafe\u{301}2", executable: true)
        try link("\(home)/gone/python3.12", ".local/pipx/venvs/tool/bin/python")
        try write("#!\(venv)/python\n", ".local/pipx/venvs/tool/bin/tool", executable: true)
        try link("\(venv)/tool", ".local/bin/pipxtool")
        let uv = "\(home)/.local/share/uv/tools/sometool/bin"
        try link("\(home)/gone/python3.11", ".local/share/uv/tools/sometool/bin/python")
        try write("#!\(uv)/python\n", ".local/share/uv/tools/sometool/bin/sometool", executable: true)
        try link("\(uv)/sometool", ".local/bin/sometool")
        for index in 1...12 { try link("\(home)/gone/thing", ".local/bin/gone\(index)") }
        try link("\(home)/gone/Old.app/Contents/MacOS/old", ".local/bin/oldapp")
        try link("../lib/node_modules/@scope/pkg/cli.js", ".npm-global/bin/scoped")
        try link("/Library/Frameworks/Python.framework/Versions/3.8/bin/python3.8", ".local/bin/framework")
        try link("loop", ".local/bin/loop")
        try write("#!/usr/bin/env macup_no_such_interp\n", "Cellar/x/1/bin/brewcli", executable: true)
        try link("\(home)/Cellar/x/1/bin/brewcli", ".local/bin/brewcli")
        try link("\(home)/Cellar/y/1/bin/gone", ".local/bin/brewgone")
        try link(local, "again/bin")
        let folders = [local, "\(home)/.npm-global/bin", "\(home)/again/bin", "\(home)/missing", "/opt/homebrew/bin", "/usr/local/bin"]
        XCTAssertEqual(Tools.commandScan(folders, home: home, shell: shell), try python(["commands"] + folders))
        XCTAssertEqual(Tools.commandScan(folders, home: home + "/", shell: shell), try python(["commands"] + folders))
    }

    func testPathsAsPythonResolvesThem() throws {
        try write("", "real/file")
        try link("real", "to-real")
        try link("../real/file", "dir/up")
        try link("/nonexistent/x", "dangling")
        try link("loop-b", "loop-a")
        try link("loop-a", "loop-b")
        try link("to-real/../real", "dotdot")
        let paths = ["\(home)/to-real/file", "\(home)/dir/up", "\(home)/dangling/more", "\(home)/loop-a/x", "\(home)/dotdot/file", "\(home)//a/./b/../c/",
                     "//x/y", "///x", "/", "\(home)/to-real/../to-real/missing/..", "\(home)/dir/up/../.."]
        let code = "import os, sys\nfor p in sys.argv[1:]: print(os.path.realpath(p)); print(os.path.normpath(p)); print(os.path.dirname(p)); print(os.path.basename(p))"
        let swift = paths.map { [PythonPath.realpath($0), PythonPath.normpath($0), PythonPath.dirname($0), PythonPath.basename($0)].joined(separator: "\n") }
        XCTAssertEqual(swift.joined(separator: "\n"), try python(["-c", code] + paths))
        try write("", "bin/plain")
        try write("", "bin/tool", executable: true)
        try FileManager.default.createDirectory(atPath: home + "/bin/folder", withIntermediateDirectories: true)
        let names = ["tool", "plain", "folder", "ls", "/bin/ls", "bin/tool", "nope"], searches = ["", ":", "/bin", "\(home)/bin", "/nope:\(home)/bin"]
        let whichCode = "import os, shutil, sys\nos.chdir(sys.argv[1])\nfor p in sys.argv[2:]:\n  for n in \(names): print(shutil.which(n, path=p) is not None)"
        let here = FileManager.default.currentDirectoryPath
        FileManager.default.changeCurrentDirectoryPath(home)
        defer { FileManager.default.changeCurrentDirectoryPath(here) }
        let found = searches.flatMap { search in names.map { PythonPath.which($0, path: search) ? "True" : "False" } }
        XCTAssertEqual(found.joined(separator: "\n"), try python(["-c", whichCode, home] + searches))
    }

    func testCrashesAsPythonCountsThem() throws {
        let reports = "\(home)/Library/Logs/DiagnosticReports"
        func stamp(_ daysAgo: Double, _ format: String = "%Y-%m-%d %H:%M:%S.00 +0000") -> String {
            Run.date(format, time_t(Date().timeIntervalSince1970 - daysAgo * 86400 - 3600))
        }
        func ips(_ name: String, _ app: String, bug: String = "\"309\"", daysAgo: Double = 1, path: String) throws {
            try write("{\"app_name\":\"\(app)\",\"timestamp\":\"\(stamp(daysAgo, "%Y-%m-%d %H:%M:%S.00 %z"))\",\"bug_type\":\(bug)}\n{\"procPath\":\"\(path)\"}\n", "\(reports)/\(name)")
        }
        for index in 1...3 {
            try ips("Crashy App-2026-11-2\(index)-1.ips", "Crashy App", path: "\\/Applications\\/Crashy.app\\/x")
            try ips("Retired/Crashy App-2026-11-1\(index)-1.ips", "Crashy App", daysAgo: 2, path: "/Applications/Crashy.app/x")
            try ips("ExcUserFault_X-\(index).ips", "X", path: "/Applications/X.app/x")
            try ips("Old-\(index).ips", "Old", daysAgo: 20, path: "/Applications/Old.app/x")
            try ips("Hang-\(index).ips", "Hang", bug: "385", path: "/Applications/Hang.app/x")
            try ips("Home-\(index).ips", "Home App", bug: "309", daysAgo: 3, path: "\(home)/Applications/Home.app/x")
            try ips("Café-\(index).ips", "Café", path: "/Applications/Cafe.app/x")
            try ips("Retired/Cafe\u{301}-\(index).ips", "Cafe\u{301}", path: "/Applications/Cafe.app/x")
            try ips("Two-\(index).ips", "Two  Spaces", path: "/Applications/Two.app/x")
            try write("Process: Legacy\r\nPath:    /Applications/Legacy App.app/x  \r\n", "\(reports)/Legacy App_2026-11-1\(index)-100000_Mac.crash")
            try ips("Retired/sys-\(index).ips", "sys", path: "/System/x")
        }
        try ips("Retired/Crashy App-2026-11-21-1.ips", "Crashy App", path: "/Applications/Crashy.app/x")
        try write("{\"bug_type\":309.0}\n{}\n", "\(reports)/Float-1.ips")
        try write("{\"bug_type\":309,\"name\":7}\n{\"procPath\":\"/Applications/N.app\"}\n", "\(reports)/Number-1.ips")
        try write("{\"app_name\":\"\",\"name\":\"\",\"bug_type\":\"309\",\"timestamp\":\"\(stamp(1, "%Y-%m-%d %H:%M:%S.5 +01:30"))\"}\n{\"procPath\":\"/Applications/E.app\"}\n", "\(reports)/Empty_2026-01-01x.ips")
        try write("{\"app_name\":\"Stamp\",\"bug_type\":\"309\",\"timestamp\":\"2026-02-30 10:00:00.00 +0000\"}\n{\"procPath\":\"/Applications/S.app\"}\n", "\(reports)/Stamp-1.ips")
        try write("{\"app_name\":\"Escape\",\"bug_type\":\"309\"}\n{\"procPath\":\"/Applications/\\q\"}\n", "\(reports)/Escape-1.ips")
        try write("not json\n", "\(reports)/Broken-1.ips")
        try write("\u{FEFF}{\"bug_type\":\"309\"}\n", "\(reports)/Bom-1.ips")
        try write("{}", "\(reports)/.hidden.ips")
        try FileManager.default.createDirectory(atPath: "\(reports)/Folder.ips", withIntermediateDirectories: true)
        let now = Date().timeIntervalSince1970
        XCTAssertEqual(Tools.crashCounts(home: home, now: now), try python(["crashes"]))
        try write("{\"app_name\":[1],\"bug_type\":\"309\"}\n{\"procPath\":\"/System/x\"}\n", "\(reports)/List-1.ips")
        XCTAssertEqual(Tools.crashCounts(home: home, now: now), try python(["crashes"]), "a list as the name of a system crash is not counted")
        try write("{\"app_name\":[1],\"bug_type\":\"309\"}\n{\"procPath\":\"/Applications/L.app\"}\n", "\(reports)/List-2.ips")
        XCTAssertEqual(Tools.crashCounts(home: home, now: now), try python(["crashes"]), "a list as the name of an app stops Python")
    }

    func testTimestampsAsPythonReadsThem() throws {
        let stamps = ["2026-11-20 10:11:12.00 +0000", "2026-11-20 10:11:12.123456 -0130", "2026-1-2 3:4:5.6 +01:00", "2026-11- 2 10:11:12.0 Z",
                      "2026-11-20 10:11:12.0 +01:00:30", "2026-11-20 10:11:12.0 +01:00:30.5", "2026-11-20 10:11:12.0 +0100:30", "2026-11-20 10:11:12.0 +2400",
                      "2026-02-29 10:11:12.0 +0000", "2024-02-29 10:11:12.0 +0000", "2026-11-20 10:11:60.0 +0000", "2026-11-20 10:11:12 +0000",
                      "2026-11-20 10:11:12.0 +0000\n", "2026-11-20  10:11:12.0\t+0000", "2026-11-20 10:11:12.0 z", "0000-01-01 00:00:00.0 +0000"]
        let code = "import datetime, sys\nfor s in sys.argv[1:]:\n  try: print('%.6f' % datetime.datetime.strptime(s, '%Y-%m-%d %H:%M:%S.%f %z').timestamp())\n  except Exception: print('-')"
        XCTAssertEqual(stamps.map { Tools.reportTimestamp($0).map { String(format: "%.6f", $0) } ?? "-" }.joined(separator: "\n"), try python(["-c", code] + stamps))
        let ends = ["Nov 26 10:00:00 2026 GMT", "Nov  6 10:00:00 2026 GMT", "nov 26 1:2:3 2026 utc", "Feb 30 10:00:00 2026 GMT", "Nov 26 10:00:00 2026 XYZ",
                    "November 26 10:00:00 2026 GMT", "Nov 26 10:00:00 2026", "Nov 26 10:00:60 2026 GMT"]
        let endCode = "import datetime, calendar, sys\nfor s in sys.argv[1:]:\n  try: print(calendar.timegm(datetime.datetime.strptime(s, '%b %d %H:%M:%S %Y %Z').timetuple()))\n  except Exception: print('-')"
        XCTAssertEqual(ends.map { Tools.certificateDate($0).map { String($0) } ?? "-" }.joined(separator: "\n"), try python(["-c", endCode] + ends))
    }

    func testCertificatesAsPythonReadsThem() throws {
        func certificate(_ name: String, days: Int) throws -> String {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
            process.arguments = ["req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", "/dev/null", "-days", String(days), "-subj", "/CN=\(name)/O=Test"]
            let stdout = Pipe()
            process.standardOutput = stdout
            process.standardError = FileHandle.nullDevice
            try process.run()
            let data = stdout.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(decoding: data, as: UTF8.self)
        }
        let pems = try [("Apple Development: Soon Gone (A1)", 10), ("Apple Distribution: Long Lived (B2)", 300), ("Some Web Server", 5),
                        ("Apple Development: Renewed (C3)", 10), ("Apple Development: Renewed (C3)", 300), ("Developer ID Application: Acme, Inc. (E5)", 10),
                        ("Apple Development: Zed (Z9)", 1)].map(certificate).joined()
        try write(pems, "certs.pem")
        try write("#!/bin/bash\n[ \"$1\" = find-certificate ] && cat \"$HOME/certs.pem\"\n", "bin/security", executable: true)
        let identities = ["Apple Development: Soon Gone (A1)", "Apple Distribution: Long Lived (B2)", "Apple Development: Renewed (C3)",
                          "Developer ID Application: Acme, Inc. (E5)", "Apple Development: Zed (Z9)", "Not In Keychain"].enumerated()
            .map { "  \($0.offset + 1)) 000\($0.offset) \"\($0.element)\"" }.joined(separator: "\n") + "\n     6 valid identities found\n"
        for listed in [identities, "     0 valid identities found\n", ""] {
            XCTAssertEqual(Tools.expiringCertificates(listed, shell: shell), try python(["certs-expiring"], input: listed), listed)
        }
        XCTAssertEqual(Tools.expiringCertificates(identities, shell: shell), "Apple Development: Soon Gone (A1)\nApple Development: Zed (Z9)\nDeveloper ID Application: Acme, Inc. (E5)")
    }

    func testBashPiecesAsBashHasThem() throws {
        let lines = ["node\t-\tnodecli\t", "\t-\t\t/x/bin\ta, b\t~/gone, Old.app\t\t", "a b\tc d", "solo", ""]
        for line in lines {
            let bash = try BashOracle.run(["IFS=$'\\t' read -r name hint names from <<< \(BashOracle.quoted(line)); printf '%s|' \"$name\" \"$hint\" \"$names\" \"$from\""])
            XCTAssertEqual(Tools.readTabs(line, 4).map { $0 + "|" }.joined(), bash[0], line)
        }
        for text in ["", "a\n", "a\nb\n", "a\n\nb\n\n", "a;b\nc"] {
            let bash = try BashOracle.run(["printf '%s' \(BashOracle.quoted(text)) | paste -sd';' - | sed 's/;/; /g'"])
            XCTAssertEqual(Bash.substitution(Tools.pasted(text, ";").replacingOccurrences(of: ";", with: "; ")), bash[0], text)
        }
        let colored = "\u{1B}[32m✓ ok\u{1B}[0m \u{1B}[?25l\u{1B}[1;31mbad\u{1B}[0m\n\u{1B}]8;;x\u{1B}\\"
        XCTAssertEqual(Bash.substitution(Tools.noColor(colored)), try BashOracle.run(["printf '%s' \(BashOracle.quoted(colored)) | nocolor"])[0])
        let userPath = "/usr/bin:\(home)/no/such:: :\(home)/bin:\(home)/no/such:\(home)/a,b:\(home):/x/\(home)/y\(home)/late"
        let pipeline = "printf '%s' \"$USER_PATH\" | tr ':' '\\n' | awk 'NF && !seen[$0]++' | while IFS= read -r d; do [[ \"$d\" == \"$HOME\"/* ]] && [ ! -d \"$d\" ] && tildify \"$d\"; done | paste -sd, - | sed 's/,/, /g'"
        let env = try Env(["HOME": home, "PATH": userPath])
        XCTAssertEqual(Tools.missingPathFolders(env), try BashOracle.run([pipeline], home: home, prelude: "USER_PATH=" + BashOracle.quoted(userPath))[0])
        for output in ["Apple Swift version 6.0.3 (swiftlang)\nTarget: x", "x\nSwift version \nSwift version 5.9", "none"] {
            let bash = try BashOracle.run(["printf '%s' \(BashOracle.quoted(output)) | grep -o 'Swift version [0-9.]*' | head -1 | sed 's/Swift version //'"])
            XCTAssertEqual(Tools.swiftVersion(output), bash[0], output)
        }
    }
}

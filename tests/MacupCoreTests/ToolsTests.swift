@testable import MacupCore
import XCTest

/// The tools checks, with the answers 2.9's macup_helpers.py gave for what it parsed and bash for the rest.
final class ToolsTests: XCTestCase {
    var home = ""
    var shell: Shell!

    override func setUpWithError() throws {
        home = (NSTemporaryDirectory() as NSString).resolvingSymlinksInPath + "/macup-tools-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: home + "/bin", withIntermediateDirectories: true)
        shell = Shell(env: try Env(["HOME": home, "PATH": "\(home)/bin:/usr/bin:/bin", "MACUP_PATH": "keep"]))
    }

    override func tearDown() { try? FileManager.default.removeItem(atPath: home) }

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
            (#"{"B":{"platformIdentifier":"com.apple.platform.iphonesimulator","version":"18.2","sizeBytes":7516192768},"A":{"platformIdentifier":"com.apple.platform.iphonesimulator","version":"17.5","sizeBytes":6979321856},"C":{"platformIdentifier":"com.apple.platform.watchsimulator","version":"11.2"}}"#,
             "3 14155776\niphonesimulator 17.5 · 7.0 GB\niphonesimulator 18.2 · 7.5 GB\nwatchsimulator 11.2 · 0.0 GB"),
            (#"{"A":{"platformIdentifier":"x","sizeBytes":1.5e9},"B":{"version":"1","sizeBytes":true}}"#, "2 1464843.0\n 1 · 0.0 GB\nx ? · 1.5 GB"),
            (#"{"A":{"platformIdentifier":"com.apple.platform.xros","version":"2.0","sizeBytes":2048},"B":{"platformIdentifier":"com.apple.platform.xros","version":"10.0","sizeBytes":1024}}"#,
             "2 3\nxros 10.0 · 0.0 GB\nxros 2.0 · 0.0 GB"),
            (#"{"A":{"platformIdentifier":"Zplatform","version":"1"},"B":{"platformIdentifier":"aplatform","version":"1"},"C":{"platformIdentifier":"é","version":"1"}}"#,
             "3 0\nZ 1 · 0.0 GB\na 1 · 0.0 GB\né 1 · 0.0 GB"),
            (#"{"A":{"platformIdentifier":1}}"#, "1 0"), (#"{"A":{"platformIdentifier":"a","version":2.0}}"#, "1 0\na 2.0 · 0.0 GB"), (#"{"A":{"version":"1"},"B":{"version":1}}"#, ""),
            (#"{"A":{"platformIdentifier":"a.b","version":"1","sizeBytes":5},"B":{"platformIdentifier":"a.c","version":"1","sizeBytes":"5"}}"#, ""), (#"{"A":{"sizeBytes":"big"}}"#, ""),
            (#"{"A":{"platformIdentifier":"p.a","version":"1","sizeBytes":9223372036854775807},"B":{"platformIdentifier":"p.b","version":"1","sizeBytes":1000000000}}"#,
             "2 9007199255717554\na 1 · 9223372036.9 GB\nb 1 · 1.0 GB"),
            (#"{"A":{"platformIdentifier":"p.a","sizeBytes":99999999999999999999999}}"#, "1 97656249999999999999\na ? · 100000000000000.0 GB"),
            (#"{"A":{"platformIdentifier":"p.iphonesimulator","version":18},"B":{"platformIdentifier":"p.watchsimulator","version":"11.2"}}"#,
             "2 0\niphonesimulator 18 · 0.0 GB\nwatchsimulator 11.2 · 0.0 GB"),
            (#"{"A":{"platformIdentifier":null,"version":"2"},"B":{"platformIdentifier":null,"version":"1"}}"#, "2 0"),
            (#"{"A":{"platformIdentifier":"p","version":2},"B":{"platformIdentifier":"p","version":1.5},"C":{"platformIdentifier":"p","version":true}}"#,
             "3 0\np True · 0.0 GB\np 1.5 · 0.0 GB\np 2 · 0.0 GB"),
            (#"{"A":{"platformIdentifier":"p","version":"2"},"B":{"platformIdentifier":"p","version":1}}"#, ""), (#"{"A":[]}"#, ""), (#"{}"#, "0 0"), (#"[]"#, ""),
            ("", ""), ("{", ""), ("\u{FEFF}{}", ""),
        ]
        for (json, expected) in cases {
            XCTAssertEqual(Tools.simRuntimes(json), expected, json)
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
        let folders = [local, "\(home)/.npm-global/bin", "\(home)/again/bin", "\(home)/missing"]
        let expected = [
            "12", "-\t\(local)\tframework, gone1, gone10, gone11, gone12, gone2, gone3, gone4, gone5, gone6 +5\tOld.app, Python.framework, ~/.local/bin, ~/gone",
            "-\t\(home)/.npm-global/bin\tscoped\tnode_modules/@scope/pkg", "cafe\u{301}\t-\tcafe\u{301}2\t", "caf\u{E9}\t-\tcafe\u{301}\t",
            "macup_no_such_interp\t-\tflagcli, nodecli\t", "macup_tab\t-\tcrlf\t", "python\tpipx reinstall-all\tpipxtool\t",
            "python\tuv tool install --reinstall sometool\tsometool\t", String(repeating: "x", count: 254) + "\t-\tlong\t",
        ].joined(separator: "\n")
        XCTAssertEqual(Tools.commandScan(folders, home: home, shell: shell), expected)
        XCTAssertEqual(Tools.commandScan(folders, home: home + "/", shell: shell), expected)
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
        let real = try XCTUnwrap(realpath(home, nil).map { String(cString: $0) })
        // os.path's realpath, normpath, dirname and basename of each path
        let expected = [
            ["\(real)/real/file", "\(home)/to-real/file", "\(home)/to-real", "file"], ["\(real)/real/file", "\(home)/dir/up", "\(home)/dir", "up"],
            ["/nonexistent/x/more", "\(home)/dangling/more", "\(home)/dangling", "more"], ["\(real)/loop-a/x", "\(home)/loop-a/x", "\(home)/loop-a", "x"],
            ["\(real)/real/file", "\(home)/dotdot/file", "\(home)/dotdot", "file"], ["\(real)/a/c", "\(home)/a/c", "\(home)//a/./b/../c", ""],
            ["/x/y", "//x/y", "//x", "y"], ["/x", "/x", "///", "x"], ["/", "/", "/", ""],
            ["\(real)/real", "\(home)/to-real", "\(home)/to-real/../to-real/missing", ".."], [real, home, "\(home)/dir/up/..", ".."],
        ]
        XCTAssertEqual(paths.map { [PythonPath.realpath($0), PythonPath.normpath($0), PythonPath.dirname($0), PythonPath.basename($0)] }, expected)
        try write("", "bin/plain")
        try write("", "bin/tool", executable: true)
        try FileManager.default.createDirectory(atPath: home + "/bin/folder", withIntermediateDirectories: true)
        let names = ["tool", "plain", "folder", "ls", "/bin/ls", "bin/tool", "nope"], searches = ["", ":", "/bin", "\(home)/bin", "/nope:\(home)/bin"]
        let here = FileManager.default.currentDirectoryPath
        FileManager.default.changeCurrentDirectoryPath(home)
        defer { FileManager.default.changeCurrentDirectoryPath(here) }
        // what shutil.which finds, run from the home folder
        let found = searches.map { search in names.filter { PythonPath.which($0, path: search) } }
        XCTAssertEqual(found, [["/bin/ls", "bin/tool"], ["/bin/ls", "bin/tool"], ["ls", "/bin/ls", "bin/tool"], ["tool", "/bin/ls", "bin/tool"], ["tool", "/bin/ls", "bin/tool"]])
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
        let apps = "A 6 Crashy App\nA 3 Café\nA 3 Home App\nA 3 Legacy App\nA 3 Two  Spaces"
        XCTAssertEqual(Tools.crashCounts(home: home, now: now), "S 3\n" + apps)
        try write("{\"app_name\":[1],\"bug_type\":\"309\"}\n{\"procPath\":\"/System/x\"}\n", "\(reports)/List-1.ips")
        XCTAssertEqual(Tools.crashCounts(home: home, now: now), "S 4\n" + apps, "a list as the name of a system crash is not counted")
        try write("{\"app_name\":[1],\"bug_type\":\"309\"}\n{\"procPath\":\"/Applications/L.app\"}\n", "\(reports)/List-2.ips")
        XCTAssertEqual(Tools.crashCounts(home: home, now: now), "", "a list as the name of an app stops the count, as it stopped 2.9's helper")
    }

    func testCrashesUnderAHomeWithGlobCharacters() throws {
        let base = home
        defer { home = base }
        home += "/h[1]"
        for index in 1...3 {
            try write("{\"app_name\":\"Foo\\nS 99\",\"bug_type\":\"309\"}\n{\"procPath\":\"/Applications/Foo.app/x\"}\n", "Library/Logs/DiagnosticReports/Foo-\(index).ips")
        }
        XCTAssertEqual(Tools.crashCounts(home: home, now: Date().timeIntervalSince1970), "S 0")
        home = base + "/h1"
        for index in 1...3 {
            try write("{\"app_name\":\"Foo\\nS 99\",\"bug_type\":\"309\"}\n{\"procPath\":\"/Applications/Foo.app/x\"}\n", "Library/Logs/DiagnosticReports/Foo-\(index).ips")
        }
        XCTAssertEqual(Tools.crashCounts(home: home, now: Date().timeIntervalSince1970), "S 0\nA 3 Foo\nS 99", "a name that holds a line of the answer")
    }

    func testTimestampsAsPythonReadsThem() throws {
        let stamps = ["2026-11-20 10:11:12.00 +0000", "2026-11-20 10:11:12.123456 -0130", "2026-1-2 3:4:5.6 +01:00", "2026-11- 2 10:11:12.0 Z",
                      "2026-11-20 10:11:12.0 +01:00:30", "2026-11-20 10:11:12.0 +01:00:30.5", "2026-11-20 10:11:12.0 +0100:30", "2026-11-20 10:11:12.0 +2400",
                      "2026-02-29 10:11:12.0 +0000", "2024-02-29 10:11:12.0 +0000", "2026-11-20 10:11:60.0 +0000", "2026-11-20 10:11:12 +0000",
                      "2026-11-20 10:11:12.0 +0000\n", "2026-11-20  10:11:12.0\t+0000", "2026-11-20 10:11:12.0 z", "0000-01-01 00:00:00.0 +0000"]
        // what Python's strptime(stamp, '%Y-%m-%d %H:%M:%S.%f %z').timestamp() gave
        XCTAssertEqual(stamps.map { Tools.reportTimestamp($0).map { String(format: "%.6f", $0) } ?? "-" },
                       ["1795169472.000000", "1795174872.123456", "1767319445.600000", "1793614272.000000", "1795165842.000000", "1795165841.500000", "-", "-", "-",
                        "1709201472.000000", "-", "-", "-", "1795169472.000000", "-", "-"])
        let ends = ["Nov 26 10:00:00 2026 GMT", "Nov  6 10:00:00 2026 GMT", "nov 26 1:2:3 2026 utc", "Feb 30 10:00:00 2026 GMT", "Nov 26 10:00:00 2026 XYZ",
                    "November 26 10:00:00 2026 GMT", "Nov 26 10:00:00 2026", "Nov 26 10:00:60 2026 GMT"]
        // what calendar.timegm of Python's strptime(stamp, '%b %d %H:%M:%S %Y %Z') gave
        XCTAssertEqual(ends.map { Tools.certificateDate($0).map { String($0) } ?? "-" }, ["1795687200", "1793959200", "1795654923", "-", "-", "-", "-", "-"])
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
        let cases = [(identities, "Apple Development: Soon Gone (A1)\nApple Development: Zed (Z9)\nDeveloper ID Application: Acme, Inc. (E5)"),
                     ("     0 valid identities found\n", ""), ("", "")]
        for (listed, expected) in cases {
            XCTAssertEqual(Tools.expiringCertificates(listed, shell: shell), expected, listed)
        }
    }

    func testBashPiecesAsBashHasThem() throws {
        let lines = [("node\t-\tnodecli\t", "node|-|nodecli||"), ("\t-\t\t/x/bin\ta, b\t~/gone, Old.app\t\t", "-|/x/bin|a, b|~/gone, Old.app|"), ("a b\tc d", "a b|c d|||"),
                     ("solo", "solo||||"), ("", "||||")]
        for (line, expected) in lines {
            XCTAssertEqual(Tools.readTabs(line, 4).map { $0 + "|" }.joined(), expected, line)
        }
        for (text, expected) in [("", ""), ("a\n", "a"), ("a\nb\n", "a; b"), ("a\n\nb\n\n", "a; ; b; "), ("a;b\nc", "a; b; c")] {
            XCTAssertEqual(Bash.substitution(Tools.pasted(text, ";").replacingOccurrences(of: ";", with: "; ")), expected, text)
        }
        let colored = "\u{1B}[32m✓ ok\u{1B}[0m \u{1B}[?25l\u{1B}[1;31mbad\u{1B}[0m\n\u{1B}]8;;x\u{1B}\\"
        XCTAssertEqual(Bash.substitution(Tools.noColor(colored)), "✓ ok bad\n\u{1B}]8;;x\u{1B}\\")
        let userPath = "/usr/bin:\(home)/no/such:: :\(home)/bin:\(home)/no/such:\(home)/a,b:\(home):/x/\(home)/y\(home)/late"
        XCTAssertEqual(Tools.missingPathFolders(try Env(["HOME": home, "PATH": userPath])), "~/no/such, ~/a, b")
        for (output, expected) in [("Apple Swift version 6.0.3 (swiftlang)\nTarget: x", "6.0.3"), ("x\nSwift version \nSwift version 5.9", ""), ("none", "")] {
            XCTAssertEqual(Tools.swiftVersion(output), expected, output)
        }
    }
}

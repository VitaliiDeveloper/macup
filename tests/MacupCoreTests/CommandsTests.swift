import Foundation
import XCTest
@testable import MacupCore

/// The one-off commands' pure pieces, answering as the bash functions they replace (2.9's commands.sh) did.
final class CommandsTests: XCTestCase {
    private let folder = NSTemporaryDirectory() + "macup-commands-\(UUID().uuidString)"

    override func setUpWithError() throws { try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true) }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(atPath: folder) }

    func testReportDateIsBashs() {
        let paths = ["/Users/me/Library/Logs/macup/macup_2026-11-01_10-00-00.md", "/Users/me/Library/Logs/macup/macup_2026-11-01_10-00-00_4242.md",
                     "/x/macup_odd.md", "/x/macup_2026_1.md", "/a/macup_x/macup_2026-01-02_03-04-05.md", "/x/macup_-n_1-2.md"]
        XCTAssertEqual(paths.map(Reports.date), ["2026-11-01 10:00", "2026-11-01 10:00", "odd odd:odd", "2026 1:1", "2026-01-02 03:04", "-n 1:2"])
    }

    func testReportModeIsBashs() throws {
        let thirdLines = ["Mode: check · macup 2.9.2 · took 0m 5s", "Режим: all+deep · macup 2.9.2", "Mode: Check · macup 2.9.2", "Mode:check · macup 2",
                          "Mode: check · macupx", "a: b: check · macup 1", "Mode:  check · macup 1", "Mode: clean · macup "]
        var files: [String] = []
        for (index, line) in thirdLines.enumerated() {
            let file = "\(folder)/report\(index).md"
            try "# title\n\n\(line)\nmore\n".write(toFile: file, atomically: true, encoding: .utf8)
            files.append(file)
        }
        let short = "\(folder)/short.md"
        try "# title\n\n".write(toFile: short, atomically: true, encoding: .utf8)
        files += [short, "\(folder)/missing.md"]
        XCTAssertEqual(files.map { Reports.mode($0) ?? "" }, ["check", "all+deep", "", "", "", "", "", "clean", "", ""])
    }

    func testBrewPrefixIsBashs() throws {
        let fm = FileManager.default
        try fm.createDirectory(atPath: "\(folder)/brew/Cellar/macup/1.0/bin", withIntermediateDirectories: true)
        try fm.createDirectory(atPath: "\(folder)/brew/bin", withIntermediateDirectories: true)
        try "MACUP_VERSION=\"1.0\"\n".write(toFile: "\(folder)/brew/Cellar/macup/1.0/bin/macup", atomically: true, encoding: .utf8)
        try fm.createSymbolicLink(atPath: "\(folder)/brew/bin/macup", withDestinationPath: "../Cellar/macup/1.0/bin/macup")
        try fm.createSymbolicLink(atPath: "\(folder)/brew/bin/other", withDestinationPath: "\(folder)/elsewhere/macup")
        let paths = ["/opt/homebrew/Cellar/macup/2.9.2/bin/macup", "/usr/local/opt/macup/bin/macup", "/opt/macup/bin/macup", "/Cellar/macup/x",
                     "\(folder)/brew/bin/macup", "\(folder)/brew/bin/other", "\(folder)/plain", "/a/Cellar/macup/b/Cellar/macup/c"]
        let resolved = try XCTUnwrap(realpath(folder, nil))
        defer { free(resolved) }
        XCTAssertEqual(paths.map(SelfPath.brewPrefix), ["/opt/homebrew", "/usr/local", "", "", String(cString: resolved) + "/brew", "", "", "/a"])
    }

    func testMacupIsRecognisedByItsVersionLine() throws {
        let cases: [(String, Data, Bool)] = [("script", Data("#!/bin/bash\n# macup\nMACUP_VERSION=\"2.9.2\"\n".utf8), true),
                                             ("first", Data("MACUP_VERSION=1".utf8), true),
                                             ("indented", Data("#!/bin/bash\n MACUP_VERSION=1\n".utf8), false),
                                             ("binary", Data([0xCF, 0xFA, 0xED, 0xFE, 0x00, 0x0A]) + Data("MACUP_VERSION=\"2.9.2\"".utf8), true),
                                             ("other", Data("#!/bin/sh\necho MACUP_VERSION=1\n".utf8), false)]
        for (name, contents, expected) in cases {
            try contents.write(to: URL(fileURLWithPath: "\(folder)/\(name)"))
            XCTAssertEqual(SelfPath.isMacup("\(folder)/\(name)"), expected, name)
        }
        XCTAssertFalse(SelfPath.isMacup("\(folder)/missing"))
    }

    func testCheckoutAndDirname() throws {
        try "".write(toFile: "\(folder)/build.sh", atomically: true, encoding: .utf8)
        XCTAssertFalse(SelfPath.isCheckout(folder))
        try "".write(toFile: "\(folder)/Package.swift", atomically: true, encoding: .utf8)
        XCTAssertTrue(SelfPath.isCheckout(folder))
        XCTAssertTrue(SelfPath.isBuildOutput("\(folder)/.build/debug/macup"))
        XCTAssertTrue(SelfPath.isBuildOutput("\(folder)/.build/arm64-apple-macosx/release/macup"))
        XCTAssertFalse(SelfPath.isBuildOutput("\(folder)/macup"), "the checkout's macup is the bootstrap")
        XCTAssertFalse(SelfPath.isBuildOutput("/Users/me/.build/debug/macup"))
        XCTAssertEqual(["/a/b", "/a", "a", "/"].map(SelfPath.dirname), ["/a", "/", ".", "/"])
    }

    func testNumbersPrintAsAwkPrintsThem() throws {
        let values = ["0", "-3", "1500.5", "1e3", "0x10", "11.25", "123456789012", "-0", "2.5e-7", "abc", " 42"]
        let script = "BEGIN{" + values.map { "printf \"%s\\n\", \"\($0)\" + 0;" }.joined() + "}"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/awk")
        process.arguments = [script]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let awk = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        XCTAssertEqual(values.map { History.awkString(Awk.number($0) + 0) }.joined(separator: "\n") + "\n", awk)
    }

    func testVersionLineIsSeds() {
        let lines = ["MACUP_VERSION=\"2.9.2\"", "MACUP_VERSION=\"3.0\"  # \"x\" y", "MACUP_VERSION=\"", "MACUP_VERSION=\"\"", " MACUP_VERSION=\"1\"",
                     "MACUP_VERSION=1", "MACUP_VERSION=\"1.0\" tail"]
        XCTAssertEqual(lines.map(Version.versionLine), ["2.9.2", "3.0\"  # \"x y", nil, "", nil, nil, "1.0 tail"])
    }

    func testAnswersThatMeanYes() {
        XCTAssertEqual(["y", "Y", "т", "Т", "д", "Д", "yes", "n", ""].map(Terminal.isYes), [true, true, true, true, true, true, false, false, false])
    }

    /// bash's awk h() set the global b, which was also the bold colour: its trend line began with the last FREED in bytes.
    func testHistoryTrendLineStartsWithItsLabel() throws {
        let home = NSTemporaryDirectory() + "macup-history-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: home) }
        let context = OneOff.Context(try Arguments.parse(["history"]), env: try Env(["HOME": home]), translations: "{}")
        try FileManager.default.createDirectory(atPath: (context.env.history as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try "2026-11-01 10:00,check,1000000,2000000,50,0,10,90,0,5120,0\n2026-11-02 10:00,clean,3000000,2000000,50,0,10,90,0,5120,0\n"
            .write(toFile: context.env.history, atomically: true, encoding: .utf8)
        let trend = History.text(context).components(separatedBy: "\n").dropLast().last
        XCTAssertEqual(trend, "\(context.colors.bold)Free space trend:\(context.colors.reset) ▁█  (1.0 GB … 3.1 GB)")
    }
}

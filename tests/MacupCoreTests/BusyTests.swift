@testable import MacupCore
import XCTest

final class BusyTests: XCTestCase {
    /// open_in as 2.9's bash ran it over lsof_snap, with a fake lsof printing each case's output.
    func testOpenInIsBash() throws {
        let home = (NSTemporaryDirectory() as NSString).resolvingSymlinksInPath + "/macup-busy-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: home + "/bin", withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: home) }
        try "#!/bin/bash\ncat \"$HOME/lsof.out\"\n".write(toFile: home + "/bin/lsof", atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: home + "/bin/lsof")
        let cases: [(lsof: String, folders: String, open: Bool)] = [
            ("p1\ncXcode\nn/x/Cache/a/b\n", "/x/Cache", true), ("p1\ncXcode\nn/x/Cache\n", "/x/Cache", false), ("p1\ncmds\nn/x/Cache/a\n", "/x/Cache", false),
            ("p1\ncmds\nn/x/Cache/a\np2\ncApp\nn/y\n", "/x/Cache", false), ("p1\ncmds\nn/y\np2\ncApp\nn/x/Cache/z", "/x/Cache", true), ("", "/x/Cache", true),
            ("p1\ncApp\n", "/x/Cache", false), ("p1\ncApp\nn/x/Cache2/a\n", "/x/Cache", false), ("p1\ncApp\nn/x/Cache/a\n", "/a\n\n/x/Cache", true),
            ("p1\ncApp\nn/x/Cache/a\n", "", false), ("p1\ncmds_stores\nn/x/Cache/q\n", "/x/Cache", false), ("p1\ncmdsX\nn/x/Cache/q\n", "/x/Cache", true),
            ("p1\ncApp\nn/x/Caf\u{E9}/f\n", "/x/Caf\u{E9}", true), ("cmds\np1\nn/x/Cache/a\n", "/x/Cache", true), ("p1\ncApp\nfcwd\nn/z/n/x/Cache/a\n", "/x/Cache", true),
        ]
        let shell = Shell(env: try Env(["HOME": home, "PATH": "\(home)/bin:/usr/bin:/bin", "MACUP_PATH": "keep"]))
        for test in cases {
            try test.lsof.write(toFile: home + "/lsof.out", atomically: true, encoding: .utf8)
            XCTAssertEqual(Cleanup.openIn(shell, test.folders), test.open, "\(test)")
        }
        try FileManager.default.removeItem(atPath: home + "/bin/lsof")
        XCTAssertTrue(Cleanup.openIn(shell, "/x/Cache"), "no lsof: it cannot tell")
    }
}

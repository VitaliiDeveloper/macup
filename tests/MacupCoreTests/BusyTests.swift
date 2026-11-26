@testable import MacupCore
import XCTest

final class BusyTests: XCTestCase {
    /// open_in against lsof_snap as bash runs them, with a fake lsof printing each case's output.
    func testOpenInIsBash() throws {
        let home = (NSTemporaryDirectory() as NSString).resolvingSymlinksInPath + "/macup-busy-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: home + "/bin", withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: home) }
        try "#!/bin/bash\ncat \"$HOME/lsof.out\"\n".write(toFile: home + "/bin/lsof", atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: home + "/bin/lsof")
        let cases: [(lsof: String, folders: String)] = [
            ("p1\ncXcode\nn/x/Cache/a/b\n", "/x/Cache"), ("p1\ncXcode\nn/x/Cache\n", "/x/Cache"), ("p1\ncmds\nn/x/Cache/a\n", "/x/Cache"),
            ("p1\ncmds\nn/x/Cache/a\np2\ncApp\nn/y\n", "/x/Cache"), ("p1\ncmds\nn/y\np2\ncApp\nn/x/Cache/z", "/x/Cache"), ("", "/x/Cache"),
            ("p1\ncApp\n", "/x/Cache"), ("p1\ncApp\nn/x/Cache2/a\n", "/x/Cache"), ("p1\ncApp\nn/x/Cache/a\n", "/a\n\n/x/Cache"), ("p1\ncApp\nn/x/Cache/a\n", ""),
            ("p1\ncmds_stores\nn/x/Cache/q\n", "/x/Cache"), ("p1\ncmdsX\nn/x/Cache/q\n", "/x/Cache"), ("p1\ncApp\nn/x/Caf\u{E9}/f\n", "/x/Caf\u{E9}"),
            ("cmds\np1\nn/x/Cache/a\n", "/x/Cache"), ("p1\ncApp\nfcwd\nn/z/n/x/Cache/a\n", "/x/Cache"),
        ]
        let prelude = "BODY=\(BashOracle.quoted(home + "/body"))\n" + BashOracle.function("lsof_snap", in: "src/cleanup.sh") + BashOracle.function("open_in", in: "src/cleanup.sh")
        let calls = cases.map { "printf '%s' \(BashOracle.quoted($0.lsof)) >\"$HOME/lsof.out\"; open_in \(BashOracle.quoted($0.folders)) && echo yes || echo no" }
        func bash(_ calls: [String]) throws -> [String] { try BashOracle.run(calls, home: home, env: ["PATH": "\(home)/bin:/usr/bin:/bin"], prelude: prelude) }
        let answers = try bash(calls)
        XCTAssertEqual(Set(answers), ["yes", "no"])
        let shell = Shell(env: try Env(["HOME": home, "PATH": "\(home)/bin:/usr/bin:/bin", "MACUP_PATH": "keep"]))
        for (index, test) in cases.enumerated() {
            try test.lsof.write(toFile: home + "/lsof.out", atomically: true, encoding: .utf8)
            XCTAssertEqual(Cleanup.openIn(shell, test.folders) ? "yes" : "no", answers[index], "\(test)")
        }
        try FileManager.default.removeItem(atPath: home + "/bin/lsof")
        XCTAssertEqual(Cleanup.openIn(shell, "/x/Cache") ? "yes" : "no", try bash(["open_in /x/Cache && echo yes || echo no"])[0], "no lsof: it cannot tell")
    }
}

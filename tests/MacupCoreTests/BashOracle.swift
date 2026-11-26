import Foundation
import XCTest

/// The bash build as the oracle: runs functions out of src/core.sh in /bin/bash, the way the built macup has them,
/// so a test compares the Swift port with what bash says today, not with a copy of it.
enum BashOracle {
    static let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().path

    static func read(_ relative: String) -> String {
        (try? String(contentsOfFile: "\(repo)/\(relative)", encoding: .utf8)) ?? ""
    }

    /// Every function of core.sh from its "paths" section on (that part only defines things and reads the config).
    static var coreFunctions: String {
        let core = read("src/core.sh")
        return String(core[core.range(of: "# ---------------------------------------------------------------- paths")!.lowerBound...])
    }

    /// Runs `calls` after core.sh's functions; returns what each prints, taken as `$(call)` (trailing newlines gone),
    /// which is how macup uses these functions.
    static func run(_ calls: [String], home: String = "/Users/someone", env extra: [String: String] = [:], prelude: String = "") throws -> [String] {
        let sep = "\u{1F}SEP\u{1F}"
        // a file, not `bash -c`: Process hands its arguments over decomposed (é as e + accent)
        let file = NSTemporaryDirectory() + "macup-oracle-\(UUID().uuidString).sh"
        var script = coreFunctions + "\n\(prelude)\n"
        for call in calls { script += "printf '%s' \"$(\(call))\"\nprintf '%s' '\(sep)'\n" }
        try script.write(toFile: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: file) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [file]
        var env = ["HOME": home, "PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "MACUP_PATH": "keep", "LC_CTYPE": "en_US.UTF-8", "MACUP_LANG": "en"]
        for (key, value) in extra { env[key] = value }
        process.environment = env
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        var parts = String(decoding: data, as: UTF8.self).components(separatedBy: sep)
        parts.removeLast()
        XCTAssertEqual(parts.count, calls.count, "bash did not answer every call")
        return parts
    }

    /// A function of a src file, from its `name(){` line to the first `}` alone on a line.
    static func function(_ name: String, in file: String) -> String {
        let lines = read(file).components(separatedBy: "\n").drop(while: { !$0.hasPrefix("\(name)(){") })
        return lines.prefix(while: { $0 != "}" }).joined(separator: "\n") + "\n}\n"
    }

    /// A value as a single-quoted bash word.
    static func quoted(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}

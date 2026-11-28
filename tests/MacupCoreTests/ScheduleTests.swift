import Foundation
import XCTest
@testable import MacupCore

/// The schedule and self-update pieces that need no launchd and no network (commands.sh `schedule`, tools/bootstrap.sh).
final class ScheduleTests: XCTestCase {
    private let folder = NSTemporaryDirectory() + "macup-schedule-\(UUID().uuidString)"

    override func setUpWithError() throws { try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true) }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(atPath: folder) }

    /// The plist 2.9's bash heredoc wrote for the same inputs, with its /bin/bash taken out.
    func testPlistIsBashsWithoutBash() {
        let cases: [(program: String, weekly: Bool, path: String, log: String, fixture: String)] = [
            ("/Users/me/.local/bin/macup", true, "/opt/homebrew/bin:/usr/bin:/bin", "/Users/me/Library/Logs/macup", "weekly"),
            ("/Users/a&b/<x>/macup", false, "/p&q:/r<s>", "/Users/a&b/Library/Logs/macup", "daily"),
        ]
        for item in cases {
            let swift = Schedule.text(program: item.program, weekly: item.weekly, path: item.path, log: item.log + "/schedule.log")
            XCTAssertEqual(swift, Checkout.fixture("ScheduleTests-plist-\(item.fixture).txt"))
        }
    }

    func testProgramOfEitherForm() {
        let written = Schedule.text(program: "/Users/a&b/bin/macup", weekly: true, path: "/bin", log: "/l")
        XCTAssertEqual(Schedule.program(in: written)?.path, "/Users/a&b/bin/macup")
        XCTAssertEqual(Schedule.program(in: written)?.bash, false)
        let legacy = written.replacingOccurrences(of: "<array>", with: Schedule.bashArray)
        XCTAssertEqual(Schedule.program(in: legacy)?.path, "/Users/a&b/bin/macup")
        XCTAssertEqual(Schedule.program(in: legacy)?.bash, true)
        XCTAssertNil(Schedule.program(in: "<plist/>"))
        XCTAssertTrue(Schedule.weekly(write(written)))
        XCTAssertFalse(Schedule.weekly(write(Schedule.text(program: "/m", weekly: false, path: "/bin", log: "/l"))))
        XCTAssertFalse(Schedule.weekly(folder + "/missing"))
    }

    /// `launchctl print gui/<uid>/<label>` as macOS prints it: the program line is indented with a tab.
    func testLoadedJobThatRunsBash() {
        let printed = { (program: String) in
            "gui/501/\(Env.schedLabel) = {\n\tactive count = 0\n\tstate = not running\n\n\tprogram = \(program)\n\targuments = {\n\t\t\(program)\n\t\tcheck\n\t}\n}\n"
        }
        XCTAssertTrue(Launchctl.runsBash(printed("/bin/bash")))
        XCTAssertFalse(Launchctl.runsBash(printed("/Users/me/.local/bin/macup")))
        XCTAssertFalse(Launchctl.runsBash(printed("/bin/bash2")))
        XCTAssertFalse(Launchctl.runsBash(""))
    }

    func testReleaseAssetAndTheBootstrapLine() throws {
        XCTAssertEqual(Release.assetURL(repo: "VitaliiDeveloper/macup", version: "3.0.0"),
                       "https://github.com/VitaliiDeveloper/macup/releases/download/v3.0.0/macup-3.0.0-macos-universal.tar.gz")
        let bootstrap = Checkout.root + "/tools/bootstrap.sh"
        XCTAssertTrue(Release.isBootstrap(bootstrap))
        XCTAssertFalse(Release.isBootstrap(write("#!/bin/bash\n# LEGACY_VERSION=1\nMACUP_VERSION=\"3.0.0\"\n")))
        XCTAssertTrue(Release.isBootstrap(write("LEGACY_VERSION=\"2.9.2\"\n")))
        XCTAssertFalse(Release.isBootstrap(folder + "/missing"))
    }

    private func write(_ text: String) -> String {
        let file = "\(folder)/\(UUID().uuidString)"
        FileManager.default.createFile(atPath: file, contents: Data(text.utf8))
        return file
    }
}

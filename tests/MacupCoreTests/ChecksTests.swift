@testable import MacupCore
import XCTest

/// The text the checks read out of macOS tools: the same answer as the sed, awk and grep of 2.9's checks.sh and report.sh gave.
final class ChecksTests: XCTestCase {

    func testUptimeAsSed() {
        let samples = ["10:00  up 3 days,  4:05, 2 users, load averages: 1.00 1.20 1.30", "16:35  up 20:31, 3 users, load averages: 2.81 3.07 2.53",
                       "9:01  up 5 mins, 1 user, load averages: 0.1 0.2 0.3", "9:01  up 1 day, 2 mins, 2 users, load averages: 1 1 1",
                       "9:01  up 12 days, 23:59, 1 user", "no uptime here", "", "a up b, c up 4 days, 1:02, x"]
        XCTAssertEqual(samples.map(Uptime.text), ["3 days,  4:05", "20:31", "5 mins", "1 day", "12 days, 23:59", "no uptime here", "", "4 days, 1:02"])
    }

    func testSwapAsAwk() {
        let samples = ["total = 2048.00M  used = 512.25M  free = 1535.75M  (encrypted)", "total = 8G used = 7.5G free = 0.5G", "used = x", "used =",
                       "nothing", "", "a\nused = 3.9M"]
        XCTAssertEqual(samples.map { Checks.swapUsed($0 + "\n") }, ["512", "7680", "0", "0", "", "", "3"])
    }

    func testMemoryAndBatteryFieldsAsAwk() {
        let samples = ["System-wide memory free percentage: 42%", "System-wide memory free percentage: 9.5%", "free percentage:x: 7%",
                       "free percentage", "a: free percentage: 3%\nfree percentage: 4%"]
        XCTAssertEqual(samples.map { Checks.fields($0, containing: "free percentage").map { Checks.awkNumber(Awk.number($0.replacingOccurrences(of: "%", with: ""))) }.joined(separator: "\n") },
                       ["42", "9.5", "7", "0", "0\n4"])
        let power = "Power:\n      Health Information:\n          Cycle Count: 612\n          Condition: Service Recommended\n          Maximum Capacity: 76%\n          Cycle Count: 9"
        let keys = ["Cycle Count", "Condition", "Maximum Capacity", "Missing"]
        XCTAssertEqual(keys.map { Checks.fields(power, containing: $0).first ?? "" }, ["612", "Service Recommended", "76%", ""])
        XCTAssertEqual(Checks.field("{ sec = 1795633455, usec = 34576 } Wed Nov 25", 2, separator: "sec = "), "1795633455, u")
    }

    func testTopProcessesAsAwkPasteSed() {
        let samples = [" 35.2 Xcode\n  4.0 Google  Chrome Helper\n  1.5 odd,name\n  0.1 later\n", "12.0 one\n", "", " 3.0\n"]
        let swift = samples.flatMap { [Checks.top($0) { "\($0)% " }, Checks.top($0) { Awk.format("%.1f", Awk.number($0) / 1_048_576) + " GB " }] }
        XCTAssertEqual(swift, ["35.2% Xcode, 4.0% Google Chrome Helper, 1.5% odd, name", "0.0 GB Xcode, 0.0 GB Google Chrome Helper, 0.0 GB odd, name",
                               "12.0% one", "0.0 GB one", "", "", "3.0% ", "0.0 GB "])
    }

    func testLoadComparisonAsAwk() {
        let samples = [("2.50", "8"), ("13.00", "8"), ("12", "8"), ("12.01", "8"), ("busy", "x"), ("", "8"), ("0", "0"), ("1e2", "64"), ("abc", "100")]
        XCTAssertEqual(samples.map { Checks.loadIsHigh($0.0, cores: $0.1) }, [false, true, false, true, true, false, false, true, true])
    }

    func testPercentAndBackupDateAsGrep() {
        let batteries = ["Now drawing from 'AC Power'\n -InternalBattery-0 (id=1)\t83%; charging", "a%b 12%", "x\n55%% y", "no percent", "12a34% 5%"]
        XCTAssertEqual(batteries.map(Checks.firstPercent), ["83%", "%", "55%", "", "34%"])
        let backups = ["/Volumes/x/2026-11-01-101010.backup/2026-11-24-101010.backup", "Failed to mount backup destination", "2026-1-01 and 2026-10-01\n12345-06-078"]
        XCTAssertEqual(backups.map { Checks.latestBackup($0) ?? "" }, ["2026-11-24", "", "2345-06-07"])
    }

    func testIntegerTestsAsBracket() {
        let samples = ["9", " 76 ", "9.5", "", "+7", "-3", "7x", "1\n2", "75\r", "\n 7", "7\n", "7\t"]
        XCTAssertEqual(samples.map { Checks.integer($0).map { $0 < 15 } == true }, [true, false, false, false, true, true, false, false, false, true, false, true])
    }

    func testDownloadBatchesAsXargs() {
        let paths = (1...12_001).map { "/Users/me/Downloads/item \($0)" }
        XCTAssertEqual(Checks.batches(paths, room: 1_000_000).map(\.count), [5000, 5000, 2001])
        XCTAssertEqual(Checks.batches(["/a", "/bb", "/ccc"], room: 7).map(\.count), [2, 1])
        XCTAssertEqual(Checks.batches(["/far too long for the room"], room: 4).map(\.count), [1])
        XCTAssertEqual(Checks.batches([], room: 100).count, 0)
    }

    func testProtectionStates() {
        XCTAssertEqual(Checks.isOn("Firewall is enabled. (State = 1)", "enabled"), true)
        XCTAssertEqual(Checks.isOn("Firewall is disabled. (State = 0)", "enabled"), false)
        XCTAssertEqual(Checks.isOn("Firewall is blocking all non-essential incoming connections. (State = 2)", "enabled"), false)
        XCTAssertNil(Checks.isOn("", "enabled"))
        XCTAssertEqual(Checks.isOn("FileVault is Off.", "is On"), false)
    }

    func testReadSizeAndPath() {
        let samples = ["123\t/Users/me/Code", "  7   /path with  spaces  ", "42", "", "5\t\t/tab\\path"]
        XCTAssertEqual(samples.map { Checks.sizeAndPath($0) }.map { "\($0.0)|\($0.1)" }, ["123|/Users/me/Code", "7|/path with  spaces", "42|", "|", "5|/tab\\path"])
    }

    /// The age counts from the day's midnight, as `date -j -f '%Y-%m-%d %H:%M:%S' "<day> 00:00:00"` reads it; a day strptime
    /// rejects is 0, as bash's `|| date +%s` makes it.
    func testBackupAgeFromMidnightAsDate() {
        let days = ["2026-10-20", "2026-03-08", "2026-11-01", "2026-02-31", "2026-13-01", "2026-00-10", "2026-11-18"]
        // now is local noon, so the whole days to each local midnight are the same in any zone and across a DST change
        var noon = tm()
        _ = strptime("2026-11-18 12:00", "%Y-%m-%d %H:%M", &noon)
        noon.tm_isdst = -1
        let now = mktime(&noon)
        XCTAssertEqual(days.map { Checks.backupAge($0, now: now) }, [29, 255, 17, 260, 0, 0, 0])
    }
}

@testable import MacupCore
import XCTest

/// The text the checks read out of macOS tools: the same answer as the sed, awk and grep of checks.sh and report.sh.
final class ChecksTests: XCTestCase {
    func testChecksAndDeepRouteToSwift() throws {
        let environment = try Env(["HOME": NSTemporaryDirectory() + "macup-none-\(UUID().uuidString)", "PATH": "/usr/bin:/bin"])
        let lines = ["check --only check.system,check.memory,check.cpu,check.battery", "all --only check.security --skip check.time_machine",
                     "check --only check.time_machine", "update --only check.sizes,check.creative", "check --deep --only check.disk",
                     "update --deep --only check.sizes --json", "check --only check.*,update.brew --skip check.startup,check.mcp,check.brew_doctor,check.macos_updates,check.xcode,check.devtools,check.commands,check.docker,check.gh,check.certs,check.crashes,check.self_update"]
        for line in lines {
            XCTAssertNotEqual(Router.route(line.split(separator: " ").map(String.init), env: environment, terminal: false), .bash, line)
        }
        XCTAssertEqual(Router.route(["check", "--deep", "--only", "check.startup"], env: environment, terminal: false), .bash)
    }

    func testUptimeAsSed() throws {
        let samples = ["10:00  up 3 days,  4:05, 2 users, load averages: 1.00 1.20 1.30", "16:35  up 20:31, 3 users, load averages: 2.81 3.07 2.53",
                       "9:01  up 5 mins, 1 user, load averages: 0.1 0.2 0.3", "9:01  up 1 day, 2 mins, 2 users, load averages: 1 1 1",
                       "9:01  up 12 days, 23:59, 1 user", "no uptime here", "", "a up b, c up 4 days, 1:02, x"]
        let bash = try BashOracle.run(samples.map { "printf '%s\\n' \(BashOracle.quoted($0)) | sed -E 's/.* up ([^,]+(, *[0-9]+:[0-9]+)?),.*/\\1/'" })
        XCTAssertEqual(samples.map(Uptime.text), bash)
    }

    func testSwapAsAwk() throws {
        let samples = ["total = 2048.00M  used = 512.25M  free = 1535.75M  (encrypted)", "total = 8G used = 7.5G free = 0.5G", "used = x", "used =",
                       "nothing", "", "a\nused = 3.9M"]
        let awk = #"awk '{for(i=1;i<=NF;i++) if($i=="used"){v=$(i+2); m=1; if(v~/G/)m=1024; gsub(/[MG]/,"",v); printf "%d", v*m; exit}}'"#
        let bash = try BashOracle.run(samples.map { "printf '%s\\n' \(BashOracle.quoted($0)) | \(awk)" })
        XCTAssertEqual(samples.map { Checks.swapUsed($0 + "\n") }, bash)
    }

    func testMemoryAndBatteryFieldsAsAwk() throws {
        let samples = ["System-wide memory free percentage: 42%", "System-wide memory free percentage: 9.5%", "free percentage:x: 7%",
                       "free percentage", "a: free percentage: 3%\nfree percentage: 4%"]
        let awk = #"awk -F': ' '/free percentage/{gsub(/%/,"",$2); print $2+0}'"#
        let bash = try BashOracle.run(samples.map { "printf '%s\\n' \(BashOracle.quoted($0)) | \(awk)" })
        XCTAssertEqual(samples.map { Checks.fields($0, containing: "free percentage").map { Checks.awkNumber(Awk.number($0.replacingOccurrences(of: "%", with: ""))) }.joined(separator: "\n") }, bash)
        let power = "Power:\n      Health Information:\n          Cycle Count: 612\n          Condition: Service Recommended\n          Maximum Capacity: 76%\n          Cycle Count: 9"
        let keys = ["Cycle Count", "Condition", "Maximum Capacity", "Missing"]
        let fields = try BashOracle.run(keys.map { "echo \(BashOracle.quoted(power)) | awk -F': ' '/\($0)/{print $2; exit}'" })
        XCTAssertEqual(keys.map { Checks.fields(power, containing: $0).first ?? "" }, fields)
        XCTAssertEqual(Checks.field("{ sec = 1795633455, usec = 34576 } Wed Nov 25", 2, separator: "sec = "), "1795633455, u")
    }

    func testTopProcessesAsAwkPasteSed() throws {
        let samples = [" 35.2 Xcode\n  4.0 Google  Chrome Helper\n  1.5 odd,name\n  0.1 later\n", "12.0 one\n", "", " 3.0\n"]
        let cpu = #"head -3 | awk '{p=$1; $1=""; sub(/^ /,""); printf "%s%% %s\n", p, $0}' | paste -sd ',' - | sed 's/,/, /g'"#
        let memory = #"head -3 | awk '{r=$1; $1=""; sub(/^ /,""); printf "%.1f GB %s\n", r/1048576, $0}' | paste -sd ',' - | sed 's/,/, /g'"#
        let bash = try BashOracle.run(samples.flatMap { ["printf '%s' \(BashOracle.quoted($0)) | \(cpu)", "printf '%s' \(BashOracle.quoted($0)) | \(memory)"] })
        let swift = samples.flatMap { [Checks.top($0) { "\($0)% " }, Checks.top($0) { Awk.format("%.1f", Awk.number($0) / 1_048_576) + " GB " }] }
        XCTAssertEqual(swift, bash)
    }

    func testLoadComparisonAsAwk() throws {
        let samples = [("2.50", "8"), ("13.00", "8"), ("12", "8"), ("12.01", "8"), ("busy", "x"), ("", "8"), ("0", "0"), ("1e2", "64"), ("abc", "100")]
        let bash = try BashOracle.run(samples.map { "awk -v l=\(BashOracle.quoted($0.0.isEmpty ? "0" : $0.0)) -v c=\(BashOracle.quoted($0.1)) 'BEGIN{print (l > c*1.5) ? 1 : 0}'" })
        XCTAssertEqual(samples.map { Checks.loadIsHigh($0.0, cores: $0.1) ? "1" : "0" }, bash)
    }

    func testPercentAndBackupDateAsGrep() throws {
        let batteries = ["Now drawing from 'AC Power'\n -InternalBattery-0 (id=1)\t83%; charging", "a%b 12%", "x\n55%% y", "no percent", "12a34% 5%"]
        let charge = try BashOracle.run(batteries.map { "printf '%s\\n' \(BashOracle.quoted($0)) | grep -o '[0-9]*%' | head -1" })
        XCTAssertEqual(batteries.map(Checks.firstPercent), charge)
        let backups = ["/Volumes/x/2026-11-01-101010.backup/2026-11-24-101010.backup", "Failed to mount backup destination", "2026-1-01 and 2026-10-01\n12345-06-078"]
        let dates = try BashOracle.run(backups.map { "printf '%s\\n' \(BashOracle.quoted($0)) | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | tail -1" })
        XCTAssertEqual(backups.map { Checks.latestBackup($0) ?? "" }, dates)
    }

    func testIntegerTestsAsBracket() throws {
        let samples = ["9", " 76 ", "9.5", "", "+7", "-3", "7x", "1\n2"]
        let bash = try BashOracle.run(samples.map { "[ \(BashOracle.quoted($0)) -lt 15 ] 2>/dev/null && echo yes || echo no" })
        XCTAssertEqual(samples.map { (Checks.integer($0).map { $0 < 15 } ?? false) ? "yes" : "no" }, bash)
    }

    func testProtectionStates() {
        XCTAssertEqual(Checks.isOn("Firewall is enabled. (State = 1)", "enabled"), true)
        XCTAssertEqual(Checks.isOn("Firewall is disabled. (State = 0)", "enabled"), false)
        XCTAssertEqual(Checks.isOn("Firewall is blocking all non-essential incoming connections. (State = 2)", "enabled"), false)
        XCTAssertNil(Checks.isOn("", "enabled"))
        XCTAssertEqual(Checks.isOn("FileVault is Off.", "is On"), false)
    }

    func testReadSizeAndPath() throws {
        let samples = ["123\t/Users/me/Code", "  7   /path with  spaces  ", "42", "", "5\t\t/tab\\path"]
        let bash = try BashOracle.run(samples.map { "printf '%s\\n' \(BashOracle.quoted($0)) | { read -r size path; printf '%s|%s' \"$size\" \"$path\"; }" })
        XCTAssertEqual(samples.map { Checks.sizeAndPath($0) }.map { "\($0.0)|\($0.1)" }, bash)
    }

    func testGlobOrderAsBash() throws {
        let folder = NSTemporaryDirectory() + "macup-glob-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: folder) }
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        for name in ["dev", "Library", "_x", "apple", "Zed", "e", ".hidden", "..dots", ".a", "f.sqlite", ".g.sqlite"] {
            FileManager.default.createFile(atPath: "\(folder)/\(name)", contents: nil)
        }
        for locale in ["en_US.UTF-8", "C"] {
            setenv("LC_ALL", locale, 1)
            defer { unsetenv("LC_ALL") }
            let patterns = ["*", ".[!.]*", "*.sqlite", "nothing*"]
            let bash = try BashOracle.run(patterns.map { "for name in \(BashOracle.quoted(folder))/\($0); do [ -e \"$name\" ] && echo \"$name\"; done" }, env: ["LC_ALL": locale])
            XCTAssertEqual(patterns.map { Checks.glob(folder, $0).joined(separator: "\n") }, bash, locale)
        }
    }
}

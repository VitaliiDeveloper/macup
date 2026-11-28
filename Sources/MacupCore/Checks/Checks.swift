import Darwin
import Foundation

/// checks.sh: the System section. report.sh's Security, sizes, Video & photo and the deep scan are in the other files here.
enum Checks {
    static func system(_ run: Run) {
        run.out.beginSection("System")
        if run.task("check.system") { macOS(run) }
        let data = Bash.lines(run.shell.capture(["df", "-k", "/System/Volumes/Data"], stdin: .inherit).output)
        let line = data.count > 1 ? data[1] : ""
        run.diskTotal = Int64(Awk.field(line, 2)) ?? 1
        run.freeBefore = Int64(Awk.field(line, 4)) ?? 0
        if run.task("check.disk") { disk(run) }
        if run.task("check.memory") { memory(run) }
        if run.task("check.cpu") { cpu(run) }
        if run.task("check.battery") { battery(run) }
    }

    static func macOS(_ run: Run) {
        let uptime = Uptime.text(output(run, ["uptime"]))
        let boot = records(run.shell.capture(["sysctl", "-n", "kern.boottime"], stdin: .inherit).output).first.map { Awk.int(Awk.number(field($0, 2, separator: "sec = "))) }
        let now = Int64(time(nil))
        let days = (now - (boot ?? now)) / 86400
        let version = output(run, ["sw_vers", "-productVersion"]), build = output(run, ["sw_vers", "-buildVersion"])
        let model = output(run, ["sysctl", "-n", "hw.model"])
        if days >= 14 {
            run.out.warn("macOS %s (%s) · %s · up %s — restart recommended (%s days without restart)", version, build, model, uptime, String(days))
        } else {
            run.out.ok("macOS %s (%s) · %s · up %s", version, build, model, uptime)
        }
    }

    static func disk(_ run: Run) {
        let out = run.out
        let percentage = run.freeBefore * 100 / max(run.diskTotal, 1), percent = String(percentage)
        let free = Size.hum(run.freeBefore), total = Size.hum(run.diskTotal)
        switch percentage {
        case ..<10: out.fail("Disk: %s free of %s (%s%%) — critically low", free, total, percent)
        case ..<20: out.warn("Disk: %s free of %s (%s%%) — getting low", free, total, percent)
        default: out.ok("Disk: %s free of %s (%s%%)", free, total, percent)
        }
        let swapLines = Bash.lines(run.shell.capture(["df", "-k", "/System/Volumes/VM"], stdin: .inherit).output)
        if swapLines.count > 1, let swapFiles = Int64(Awk.field(swapLines[1], 3)), swapFiles >= 1_048_576 {
            out.info("Swap files: %s of the used space (macOS removes them on restart)", Size.hum(swapFiles))
        }
        let smart = Bash.substitution(fields(run.shell.capture(["diskutil", "info", "disk0"], stdin: .inherit).output, containing: "SMART Status", separator: ": *")
            .map { $0 + "\n" }.joined())
        if !smart.isEmpty {
            if smart == "Verified" || smart == "Not Supported" { out.ok("Disk health (SMART): %s", smart) } else { out.fail("Disk health (SMART): %s — back up now", smart) }
        }
        let snapshots = Bash.lines(run.shell.capture(["tmutil", "listlocalsnapshots", "/"], stdin: .inherit).output).filter { $0.contains("com.apple") }.count
        if snapshots > 0 { out.info("Local Time Machine snapshots: %s (macOS frees them automatically when space runs low)", String(snapshots)) }
    }

    static func memory(_ run: Run) {
        run.swapMeasured = true
        let memory = orElse(run.shell.capture(["sysctl", "-n", "hw.memsize"], stdin: .inherit), "0")
        let gigabytes = (Int64(memory) ?? 0) / 1_073_741_824
        run.memFree = fields(run.shell.capture(["memory_pressure"], stdin: .inherit).output, containing: "free percentage")
            .map { awkNumber(Awk.number($0.replacingOccurrences(of: "%", with: ""))) }.joined(separator: "\n")
        run.swap = Int64(swapUsed(run.shell.capture(["sysctl", "-n", "vm.swapusage"], stdin: .inherit).output)) ?? 0
        let free = run.memFree.isEmpty ? "?" : run.memFree, swap = Size.hum(run.swap * 1024)
        if (integer(run.memFree.isEmpty ? "100" : run.memFree) ?? 100) < 15 || run.swap > 6144 {
            run.out.warn("Memory: %s GB, %s%% free, swap %s — memory is tight; quit heavy apps or restart", String(gigabytes), free, swap)
        } else {
            run.out.ok("Memory: %s GB, %s%% free, swap %s", String(gigabytes), free, swap)
        }
    }

    /// The awk that reads `sysctl -n vm.swapusage`: the MB after the first "used", "" when there is none.
    static func swapUsed(_ output: String) -> String {
        for record in records(output) {
            let words = record.unicodeScalars.split(whereSeparator: { $0 == " " || $0 == "\t" }).map { String(String.UnicodeScalarView($0)) }
            guard let used = words.firstIndex(of: "used") else { continue }
            let value = used + 2 < words.count ? words[used + 2] : ""
            let factor: Double = value.contains("G") ? 1024 : 1
            return String(Awk.int(Awk.number(value.replacingOccurrences(of: "M", with: "").replacingOccurrences(of: "G", with: "")) * factor))
        }
        return ""
    }

    static func cpu(_ run: Run) {
        let out = run.out
        let cores = orElse(run.shell.capture(["sysctl", "-n", "hw.ncpu"], stdin: .inherit), "1")
        let load = Bash.substitution(records(run.shell.capture(["sysctl", "-n", "vm.loadavg"], stdin: .inherit).output).map { Awk.field($0, 2) + "\n" }.joined())
        if loadIsHigh(load, cores: cores) {
            out.warn("CPU: load %s on %s cores — something is busy", load, cores)
        } else {
            out.ok("CPU: load %s on %s cores", load.isEmpty ? "?" : load, cores)
        }
        let topCPU = top(run.shell.capture(["ps", "-Aceo", "pcpu=,comm=", "-r"], stdin: .inherit).output) { "\($0)% " }
        let topMemory = top(run.shell.capture(["ps", "-Aceo", "rss=,comm=", "-m"], stdin: .inherit).output) { Awk.format("%.1f", Awk.number($0) / 1_048_576) + " GB " }
        if !topCPU.isEmpty { out.info("Top CPU:    %s", topCPU) }
        if !topMemory.isEmpty { out.info("Top memory: %s", topMemory) }
        let thermal = run.shell.capture(["pmset", "-g", "therm"], stdin: .inherit)
        let throttling = try! NSRegularExpression(pattern: "thermal warning level set|Speed_Limit[^0-9]*[0-9]{1,2}$", options: .caseInsensitive)
        if thermal.status == 0, Bash.lines(thermal.output).contains(where: { throttling.hasMatch(in: $0) }) { out.warn("Thermal: the Mac is throttling right now") }
    }

    /// awk's `l > c*1.5` with both passed by -v: a number compared as a number, anything else as text.
    static func loadIsHigh(_ load: String, cores: String) -> Bool {
        let value = Awk.unescape(load.isEmpty ? "0" : load), limit = Awk.number(Awk.unescape(cores)) * 1.5
        return Awk.isNumber(value) ? Awk.number(value) > limit : strcmp(value, awkNumber(limit)) > 0
    }

    /// The first three lines of ps, each as "<first column as `lead` shows it><the rest in single spaces>", joined by ", "
    /// (sed puts a space after every comma, names included).
    static func top(_ output: String, lead: (String) -> String) -> String {
        records(output).prefix(3).map { line -> String in
            let words = line.unicodeScalars.split(whereSeparator: { $0 == " " || $0 == "\t" }).map { String(String.UnicodeScalarView($0)) }
            return lead(words.first ?? "") + words.dropFirst().joined(separator: " ")
        }.joined(separator: ",").replacingOccurrences(of: ",", with: ", ")
    }

    static func battery(_ run: Run) {
        let state = run.shell.capture(["pmset", "-g", "batt"], stdin: .inherit)
        guard state.status == 0, state.output.contains("InternalBattery") else { return }
        let charge = firstPercent(state.output)
        let power = run.shell.capture(["system_profiler", "SPPowerDataType"], stdin: .inherit).output
        func first(_ key: String) -> String { fields(power, containing: key).first ?? "" }
        let cycles = first("Cycle Count"), condition = first("Condition"), capacity = first("Maximum Capacity").replacingOccurrences(of: "%", with: "")
        run.batteryCycles = cycles
        run.batteryMax = capacity
        func shown(_ text: String) -> String { text.isEmpty ? "?" : text }
        if !condition.isEmpty, condition != "Normal" {
            run.out.warn("Battery: %s charged, %s cycles, %s%% capacity, %s", charge, shown(cycles), shown(capacity), condition)
        } else if !capacity.isEmpty, let percent = integer(capacity), percent < 80 {
            run.out.warn("Battery: %s charged, %s cycles, %s%% capacity, %s — capacity under 80%%", charge, shown(cycles), capacity, shown(condition))
        } else {
            run.out.ok("Battery: %s charged, %s cycles, %s%% capacity, %s", charge, shown(cycles), shown(capacity), shown(condition))
        }
    }

    /// `grep -o '[0-9]*%' | head -1`: the digits before the first % of the first line that has one.
    static func firstPercent(_ text: String) -> String {
        for line in Bash.lines(text) {
            let scalars = Array(line.unicodeScalars)
            guard let percent = scalars.firstIndex(of: "%") else { continue }
            var start = percent
            while start > 0, ("0"..."9").contains(scalars[start - 1]) { start -= 1 }
            return String(String.UnicodeScalarView(scalars[start...percent]))
        }
        return ""
    }
}

extension Checks {
    /// `$(tool 2>/dev/null)`.
    static func output(_ run: Run, _ argv: [String]) -> String {
        Bash.substitution(run.shell.capture(argv, stdin: .inherit).output)
    }

    /// `$(tool 2>/dev/null || echo fallback)`.
    static func orElse(_ result: (status: Int32, output: String), _ fallback: String) -> String {
        Bash.substitution(result.output + (result.status == 0 ? "" : fallback + "\n"))
    }

    static func records(_ output: String) -> [String] {
        let text = Bash.substitution(output)
        return text.isEmpty ? [] : Bash.lines(text)
    }

    /// `awk -F'<separator>' '/<key>/{print $2}'`: the second field of every line that has the key.
    static func fields(_ output: String, containing key: String, separator: String = ": ") -> [String] {
        Bash.lines(output).filter { $0.contains(key) }.map { field($0, 2, separator: separator) }
    }

    static func field(_ record: String, _ number: Int, separator: String) -> String {
        let expression = try! NSRegularExpression(pattern: separator)
        let text = record as NSString
        var start = 0, index = 1
        for match in expression.matches(in: record, range: NSRange(location: 0, length: text.length)) where match.range.length > 0 {
            if index == number { return text.substring(with: NSRange(location: start, length: match.range.location - start)) }
            start = match.range.location + match.range.length
            index += 1
        }
        return index == number ? text.substring(from: start) : ""
    }

    /// How awk prints a number: an integer without decimals, anything else as "%.6g".
    static func awkNumber(_ value: Double) -> String {
        value == value.rounded(.towardZero) && abs(value) < 1e18 ? String(Int64(value)) : Awk.format("%.6g", value)
    }

    /// The number `[ "$x" -lt 15 ]` reads (bash's legal_number): any white space before it, only blanks and tabs after;
    /// anything else is not a number and the test is false.
    static func integer(_ text: String) -> Int64? {
        var scalars = Substring(text).unicodeScalars.drop(while: { " \t\n\r\u{0B}\u{0C}".unicodeScalars.contains($0) })
        while let last = scalars.last, last == " " || last == "\t" { scalars = scalars.dropLast() }
        return Int64(String(String.UnicodeScalarView(scalars)))
    }
}

/// The sed that cuts `uptime` down to how long the Mac has been up.
enum Uptime {
    private static let expression = try! NSRegularExpression(pattern: "^.* up ([^,]+(, *[0-9]+:[0-9]+)?),.*$")

    static func text(_ output: String) -> String {
        Bash.lines(output).map { line -> String in
            let range = NSRange(location: 0, length: (line as NSString).length)
            guard let match = expression.firstMatch(in: line, range: range) else { return line }
            return (line as NSString).substring(with: match.range(at: 1))
        }.joined(separator: "\n")
    }
}

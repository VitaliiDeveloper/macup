import Foundation

/// Simulators, only when you pick them: runtimes, erasing one, unused ones; running ones are left alone.
/// Unavailable ones (Xcode no longer has their runtime) at the safe level.
extension Cleaners {
    static func simulators(_ run: Run) {
        guard run.shell.have("xcrun"), ["clean.sim_runtimes", "clean.sim_erase", "clean.sim_unused"].contains(where: run.taskAllowed) else { return }
        let dev = run.env.dev, devices = dev + "/CoreSimulator/Devices"
        let listed = simList(run.shell.capture(["xcrun", "simctl", "list", "devices", "-j"], stdin: .inherit).output + "@@\n"
                             + run.shell.capture(["xcrun", "simctl", "runtime", "list", "-j"], stdin: .inherit).output)
        for line in listed {
            let fields = read(line, "\t", 8)
            guard fields[0] == "R", fields[5] == "0" else { continue }
            let last = fields[3] == "-" ? translate(run, "never") : fields[3]
            let runtime = read("\(fields[1])|\(fields[2])|\(last)|\(fields[4])|\(fields[6]) \(fields[7])", "|", 5)
            run.register(task: "clean.sim_runtimes", level: 2,
                         label: format(run, "Simulator runtime %s: last used %s, simulators: %s (Xcode downloads it again: Settings → Components)",
                                       runtime[4], runtime[2], runtime[3]),
                         kb: Int64(runtime[1]) ?? 0, kind: .cmd, paths: "simrt:\(runtime[0]) \(runtime[1])")
        }
        var unused: [String] = [], names = ""
        for line in listed {
            let fields = read(line, "\t", 5), id = fields[1], name = fields[4]
            guard fields[0] == "D", fields[2] == "Shutdown", simulatorID(run, id) else { continue }
            let folder = "\(devices)/\(id)"
            guard realFolder(folder) else { continue }
            let size = run.kb(folder + "/data")
            if size >= 102_400 {
                run.register(task: "clean.sim_erase", level: 3, label: format(run, "Erase simulator %s (%s): its apps and data are removed", name, runtimeName(fields[3])),
                             kb: size, kind: .cmd, paths: "simerase:\(id)", measureDir: folder)
            }
            if !find(run, [folder, "-maxdepth", "4", "-mtime", "-\(run.settings.simulatorDays)", "-print", "-quit"]).isEmpty { continue }
            unused.append(id)
            names += (names.isEmpty ? "" : ", ") + name
        }
        guard !unused.isEmpty else { return }
        run.register(task: "clean.sim_unused", level: 2,
                     label: format(run, "Simulators unused for %s+ days (%s): %s — add them again in Xcode → Devices and Simulators",
                                   String(run.settings.simulatorDays), String(unused.count), names),
                     kb: run.kbl(unused.map { "\(devices)/\($0)" }.joined(separator: "\n")), kind: .cmd, paths: "simdel:" + unused.joined(separator: " "),
                     measureDir: devices)
    }

    /// sim_id: a simulator id is hex digits and dashes; anything else is refused, and the report says so.
    static func simulatorID(_ run: Run, _ id: String) -> Bool {
        let valid = !id.isEmpty && id.unicodeScalars.allSatisfy { ("0"..."9").contains($0) || ("A"..."F").contains($0) || ("a"..."f").contains($0) || $0 == "-" }
        if !valid { run.log.append("macup refused simulator id: \(id)\n") }
        return valid
    }

    /// `echo "$rid" | sed 's/.*SimRuntime\.//; s/-/ /; s/-/./g'`: com.apple.CoreSimulator.SimRuntime.iOS-17-2 → iOS 17.2.
    static func runtimeName(_ identifier: String) -> String {
        var text = Bash.echoed(identifier)
        if let marker = text.range(of: "SimRuntime.", options: [.backwards, .literal]) { text = String(text[marker.upperBound...]) }
        if let dash = text.firstIndex(of: "-") { text.replaceSubrange(dash...dash, with: " ") }
        return text.replacingOccurrences(of: "-", with: ".")
    }

    /// 2.9's inline Python: `simctl list devices -j`, "@@", `simctl runtime list -j` → D and R lines, tab-separated,
    /// read back line by line as bash reads them (a name can hold a line break).
    static func simList(_ input: String) -> [String] {
        let lines = pythonSimList(input)
        return lines.isEmpty ? [] : Bash.lines(lines.joined(separator: "\n"))
    }

    /// Python stops at the first entry of an unexpected shape, after printing the lines before it.
    static func pythonSimList(_ input: String) -> [String] {
        let halves = input.components(separatedBy: "@@")
        let deviceText = halves[0], runtimeText = halves.dropFirst().joined(separator: "@@")
        var lines: [String] = []
        var devices: [(key: String, value: JSONValue)] = []
        if let parsed = JSONValue.parse(Data(deviceText.utf8)), case .object = parsed, let found = parsed["devices"] {
            guard case .object(let entries) = found else { return lines }
            devices = entries
        }
        for (runtime, list) in devices {
            let items: [JSONValue]
            switch list {
            case .array(let entries): items = entries
            case .object(let entries) where entries.isEmpty: items = []
            case .string(let text) where text.isEmpty: items = []
            default: return lines
            }
            for item in items {
                guard case .object = item, case .string(let name) = item["name"] ?? .string("") else { return lines }
                lines.append(["D", item["udid"]?.pythonString ?? "", item["state"]?.pythonString ?? "", runtime,
                              name.replacingOccurrences(of: "\t", with: " ")].joined(separator: "\t"))
            }
        }
        guard let runtimes = JSONValue.parse(Data(runtimeText.utf8)) else { return lines }
        guard case .object(let entries) = runtimes else { return lines }
        for (id, runtime) in entries {
            guard case .object = runtime else { return lines }
            if let deletable = runtime["deletable"], !deletable.isTruthy { continue }
            guard case .string(let identifier) = runtime["runtimeIdentifier"] ?? .string("") else { return lines }
            let onIt = devices.first { same($0.key, identifier) }.map { entry -> [JSONValue] in
                if case .array(let items) = entry.value { return items }
                return []
            } ?? []
            let booted = onIt.contains { $0["state"]?.string == "Booted" }
            let platform = identifier.components(separatedBy: ".").last!.components(separatedBy: "-")[0]
            guard let bytes = pythonInt(runtime["sizeBytes"] ?? .number("0")) else { return lines }
            var lastUsed = "-"
            if let used = runtime["lastUsedAt"], used.isTruthy {
                guard case .string(let text) = used else { return lines }
                lastUsed = String(String.UnicodeScalarView(text.unicodeScalars.prefix(10)))
            }
            let kilobytes: Int64 = bytes >= 0 ? bytes / 1024 : -((-bytes + 1023) / 1024)
            let version: String = runtime["version"]?.pythonString ?? "?"
            let fields: [String] = ["R", id, String(kilobytes), lastUsed, String(onIt.count), booted ? "1" : "0", platform, version]
            lines.append(fields.joined(separator: "\t"))
        }
        return lines
    }

    /// Python's int() of a JSON value; nil where it raises.
    static func pythonInt(_ value: JSONValue) -> Int64? {
        switch value {
        case .number(let text): return Int64(text) ?? Double(text).flatMap { $0.isFinite ? Int64(exactly: $0.rounded(.towardZero)) : nil }
        case .string(let text): return Int64(text.trimmingCharacters(in: .whitespacesAndNewlines))
        case .bool(let flag): return flag ? 1 : 0
        default: return nil
        }
    }

    static let simulatorUUID = try! NSRegularExpression(pattern: "[0-9A-Fa-f]{8}-([0-9A-Fa-f]{4}-){3}[0-9A-Fa-f]{12}")

    static func unavailableSimulators(_ run: Run) {
        guard run.taskAllowed("clean.sim_unavailable"), run.shell.have("xcrun") else { return }
        let dev = run.env.dev
        // simctl list → the device folders in that set
        func folders(_ argv: [String], _ set: String) -> [String] {
            prefixed(matches(simulatorUUID, in: Bash.lines(run.shell.capture(argv, stdin: .inherit).output).filter { $0.contains("(unavailable") }.joined(separator: "\n")), set)
        }
        let standard = folders(["xcrun", "simctl", "list", "devices", "unavailable"], dev + "/CoreSimulator/Devices")
        // Xcode's parallel-test clones are a device set of their own
        let tests = Run.isDirectory(dev + "/XCTestDevices")
            ? folders(["xcrun", "simctl", "--set", dev + "/XCTestDevices", "list", "devices", "unavailable"], dev + "/XCTestDevices") : []
        let all = (standard + tests).joined(separator: "\n")
        guard !all.isEmpty else { return }
        run.register(task: "clean.sim_unavailable", level: 1, label: format(run, "Unavailable simulators (%s)", String(Run.count(all))), kb: run.kbl(all), kind: .cmd,
                     paths: "sim:" + (standard.isEmpty ? "" : "default") + (tests.isEmpty ? "" : " tests"), proc: Cleanup.xcodeBusy, measureDir: all)
    }
}

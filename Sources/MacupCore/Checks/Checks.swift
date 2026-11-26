/// The checks unit fills in the rest; until then the router keeps runs with its tasks and --deep on bash.
enum Checks {
    static func system(_ run: Run) {
        run.out.beginSection("System")
        let data = Bash.lines(run.shell.capture(["df", "-k", "/System/Volumes/Data"], stdin: .inherit).output)
        let line = data.count > 1 ? data[1] : ""
        run.diskTotal = Int64(Awk.field(line, 2)) ?? 1
        run.freeBefore = Int64(Awk.field(line, 4)) ?? 0
        if run.task("check.disk") { disk(run) }
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
        let smart = Bash.substitution(Bash.lines(run.shell.capture(["diskutil", "info", "disk0"], stdin: .inherit).output)
            .filter { $0.contains("SMART Status") }
            .map { line -> String in
                let fields = line.split(separator: ":", omittingEmptySubsequences: false)
                return fields.count > 1 ? String(fields[1].drop(while: { $0 == " " })) : ""
            }.map { $0 + "\n" }.joined())
        if !smart.isEmpty {
            if smart == "Verified" || smart == "Not Supported" { out.ok("Disk health (SMART): %s", smart) } else { out.fail("Disk health (SMART): %s — back up now", smart) }
        }
        let snapshots = Bash.lines(run.shell.capture(["tmutil", "listlocalsnapshots", "/"], stdin: .inherit).output).filter { $0.contains("com.apple") }.count
        if snapshots > 0 { out.info("Local Time Machine snapshots: %s (macOS frees them automatically when space runs low)", String(snapshots)) }
    }

    static func security(_ run: Run) {}

    static func sizes(_ run: Run) {}

    static func deep(_ run: Run) {}
}

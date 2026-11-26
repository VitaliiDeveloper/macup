import Darwin
import Foundation

enum Summary {
    static func write(_ run: Run) -> Never {
        let out = run.out, i18n = out.i18n
        let data = Bash.lines(run.shell.capture(["df", "-k", "/System/Volumes/Data"], stdin: .inherit).output)
        let freeAfter = Int64(data.count > 1 ? Awk.field(data[1], 4) : "") ?? 0
        let percent = freeAfter * 100 / max(run.diskTotal, 1)
        if run.task("check.trends"), !run.previous.isEmpty { trends(run, freeAfter: freeAfter) }
        let newer = run.task("check.self_update") ? Version.newerRelease(run) : ""
        let warnings = out.warnings
        let took = run.took
        let history = [Run.date("%Y-%m-%d %H:%M"), run.mode, String(freeAfter), String(run.diskTotal), run.memFree, String(run.swap),
                       run.batteryCycles, run.batteryMax, String(run.updated.count), String(run.freed), String(warnings.count)].joined(separator: ",")
        if let handle = FileHandle(forWritingAtPath: run.env.history) ?? create(run.env.history) {
            handle.seekToEndOfFile()
            handle.write(Data((history + "\n").utf8))
            try? handle.close()
        }

        let couldClean = run.wantsCleanup, cleaned = run.cleans || run.didClean
        var text = "# " + i18n.format("macup report — %s", args: [Run.date("%Y-%m-%d %H:%M")]) + "\n\n"
        text += i18n.format("Mode: %s · macup %s · took %s", args: [run.mode, Env.version, took]) + "\n\n## " + i18n.translate("Summary") + "\n\n"
        if !run.updated.isEmpty {
            text += "- **" + i18n.format("Updated (%s):", args: [String(run.updated.count)]) + "**\n" + run.updated.map { "    - \($0)\n" }.joined()
        } else if run.updates {
            text += "- " + i18n.translate("Updates: everything was already up to date") + "\n"
        }
        if cleaned { text += "- **" + i18n.format("Freed: %s", args: [Size.hum(run.freed)]) + "**\n" }
        else if couldClean, run.potAuto > 0 { text += "- " + i18n.format("Could free: ~%s", args: [Size.hum(run.potAuto)]) + "\n" }
        if !run.cleans, !run.didClean, couldClean, run.potTrash > 0 {
            text += "- " + i18n.format("Would move to the Trash: ~%s (freed when you empty it)", args: [Size.hum(run.potTrash)]) + "\n"
        }
        if !run.skipped.isEmpty {
            text += "- **" + i18n.format("Skipped because the app is open (%s), quit it and run again:", args: [String(run.skipped.count)]) + "**\n"
                + run.skipped.map { "    - \($0)\n" }.joined()
        }
        if couldClean, !run.didClean, run.potMore > 0 { text += "- " + i18n.format("More with a higher level or by picking: ~%s", args: [Size.hum(run.potMore)]) + "\n" }
        text += "- " + i18n.format("Free disk space: %s (%s%%), was %s", args: [Size.hum(freeAfter), String(percent), Size.hum(run.freeBefore)]) + "\n"
        if !warnings.isEmpty {
            text += "- **" + i18n.format("Needs attention (%s):", args: [String(warnings.count)]) + "**\n" + warnings.map { "    - \($0)\n" }.joined()
        } else {
            text += "- " + i18n.translate("Needs attention: nothing") + "\n"
        }
        if !newer.isEmpty { text += "- " + i18n.format("macup %s is available: %s", args: [newer, Version.updateCommand(run)]) + "\n" }
        let body = FileManager.default.contents(atPath: run.report.body) ?? Data()
        FileManager.default.createFile(atPath: run.report.path, contents: Data(text.utf8) + body + Data(rawSection(run).utf8))
        run.reportDone = true

        if let saved = run.quietDescriptor { dup2(saved, 1); close(saved) }
        if run.arguments.json {
            out.write(json(run, freeAfter: freeAfter, newer: newer) + "\n")
        } else {
            terminal(run, freeAfter: freeAfter, percent: percent, newer: newer, took: took)
        }
        notify(run)
        run.end(out.errors > 0 ? 3 : 0)   // 3: an update or cleanup step failed; warnings from the checks are not failures
    }

    private static func create(_ path: String) -> FileHandle? {
        FileManager.default.createFile(atPath: path, contents: nil) ? FileHandle(forWritingAtPath: path) : nil
    }

    static func trends(_ run: Run, freeAfter: Int64) {
        let out = run.out
        out.beginSection("Since last run")
        let fields = run.previous.split(separator: ",", maxSplits: 10, omittingEmptySubsequences: false).map(String.init)
        func field(_ index: Int) -> String { index < fields.count ? fields[index] : "" }
        let date = field(0), previousFree = field(2), previousSwap = field(5), previousCycles = field(6), previousMax = field(7)
        let freeChange = freeAfter - (previousFree.isEmpty ? freeAfter : number(previousFree))
        // swap files take disk space and macOS deletes them on restart: growing swap is not something filling the disk
        var swapGrowth: Int64 = 0
        if !previousSwap.isEmpty, previousSwap.unicodeScalars.allSatisfy({ ("0"..."9").contains($0) }), run.swapMeasured, freeChange < 0 {
            swapGrowth = (run.swap - number(previousSwap)) * 1024
        }
        swapGrowth = max(swapGrowth, 0)
        if swapGrowth > -freeChange, swapGrowth > 0 { swapGrowth = -freeChange }
        let filling = freeChange + swapGrowth < -20_971_520
        if swapGrowth >= 1_048_576 {
            if filling {
                out.warn("Free space: %s since %s (%s of it is swap, freed on restart) — something is filling the disk (try: macup check --deep)", Size.hum(freeChange), date, Size.hum(swapGrowth))
            } else {
                out.info("Free space: %s since %s (%s of it is swap, freed on restart)", Size.hum(freeChange), date, Size.hum(swapGrowth))
            }
        } else if filling {
            out.warn("Free space: %s since %s — something is filling the disk (try: macup check --deep)", Size.hum(freeChange), date)
        } else {
            out.info("Free space: %s since %s", (freeChange >= 0 ? "+" : "") + Size.hum(freeChange), date)
        }
        if !run.batteryMax.isEmpty, !previousMax.isEmpty, previousMax != run.batteryMax { out.info("Battery capacity: %s%% → %s%%", previousMax, run.batteryMax) }
        if !run.batteryCycles.isEmpty, !previousCycles.isEmpty, previousCycles != run.batteryCycles {
            out.info("Battery cycles: +%s", String(number(run.batteryCycles) - number(previousCycles)))
        }
        out.info("Full history: macup history")
    }

    private static func number(_ text: String) -> Int64 { Int64(text) ?? 0 }

    static func rawSection(_ run: Run) -> String {
        guard let raw = FileManager.default.contents(atPath: run.report.raw), !raw.isEmpty else { return "" }
        return "\n## \(run.out.i18n.translate("Command output"))\n\n~~~~\n" + String(decoding: withoutColors(raw), as: UTF8.self) + "~~~~\n"
    }

    static func withoutColors(_ data: Data) -> Data {
        let bytes = [UInt8](data)
        var kept: [UInt8] = [], index = 0
        func isLetter(_ byte: UInt8) -> Bool { (0x41...0x5A).contains(byte) || (0x61...0x7A).contains(byte) }
        while index < bytes.count {
            if bytes[index] == 0x1B, index + 1 < bytes.count, bytes[index + 1] == 0x5B {
                var end = index + 2
                while end < bytes.count, (0x30...0x39).contains(bytes[end]) || bytes[end] == 0x3B || bytes[end] == 0x3F { end += 1 }
                if end < bytes.count, bytes[end] != 0x0A, isLetter(bytes[end]) { index = end + 1; continue }
            }
            if bytes[index] != 0x0D { kept.append(bytes[index]) }
            index += 1
        }
        return Data(kept)
    }

    static func json(_ run: Run, freeAfter: Int64, newer: String) -> String {
        let out = run.out
        let items = out.items.map { item in
            "{\"section\":\"\(JSON.str(item.section))\",\"kind\":\"\(item.kind)\",\"text\":\"\(JSON.str(item.text))\",\"details\":\(JSON.lines(item.details.joined(separator: "\n")))}"
        }.joined(separator: ",")
        let report = JSON.str(run.report.path)
        return "{\"schema\":1,\"version\":\"\(Env.version)\",\"mode\":\"\(run.mode)\",\"date\":\"\(Run.date("%Y-%m-%d %H:%M"))\",\"seconds\":\(run.seconds),"
            + "\"free_kb\":\(freeAfter),\"total_kb\":\(run.diskTotal),\"freed_kb\":\(run.freed),\"could_free_kb\":\(run.potAuto),"
            + "\"could_free_more_kb\":\(run.potMore),\"to_trash_kb\":\(run.potTrash),"
            + "\"updated\":\(JSON.array(run.updated)),\"skipped_open\":\(JSON.array(run.skipped)),\"needs_attention\":\(JSON.array(out.warnings)),"
            // "log" stays for older readers: the command output is at the end of the report now
            + "\"failed_steps\":\(out.errors),\"newer_macup\":\"\(newer)\",\"report\":\"\(report)\",\"log\":\"\(report)\",\"items\":[\(items)],"
            + "\"cleanable\":\(Cleanup.json(run))}"
    }

    static func terminal(_ run: Run, freeAfter: Int64, percent: Int64, newer: String, took: String) {
        let out = run.out, i18n = out.i18n, colors = out.colors
        func line(_ color: String, _ text: String) { out.write("  \(color)\(text)\(color.isEmpty ? "" : colors.reset)\n") }
        out.write("\(colors.cl)\n\(colors.bold)━━━━━━━━━━━━━━━━ \(i18n.translate("Summary")) ━━━━━━━━━━━━━━━━\(colors.reset)\n")
        if !run.updated.isEmpty {
            line(colors.green, i18n.format("Updated: %s", args: [String(run.updated.count)]))
            for entry in run.updated { out.write("    · \(entry)\n") }
        } else if run.updates {
            line(colors.green, i18n.translate("Updates: everything was already up to date"))
        }
        if run.cleans || run.didClean { line(colors.green, i18n.format("Freed: %s", args: [Size.hum(run.freed)])) }
        else if run.wantsCleanup, run.potAuto > 0 { line("", i18n.format("Could free: ~%s  (to free it: macup all)", args: [Size.hum(run.potAuto)])) }
        if !run.cleans, !run.didClean, run.wantsCleanup, run.potTrash > 0 {
            line("", i18n.format("Would move to the Trash: ~%s (freed when you empty it)", args: [Size.hum(run.potTrash)]))
        }
        if !run.skipped.isEmpty {
            line(colors.yellow, i18n.format("Skipped because the app is open (%s), quit it and run again:", args: [String(run.skipped.count)]))
            for entry in run.skipped { out.write("    · \(entry)\n") }
        }
        if run.wantsCleanup, !run.didClean, run.potMore > 0 { line("", i18n.format("More with a higher level or by picking: ~%s", args: [Size.hum(run.potMore)])) }
        line("", i18n.format("Free disk space: %s (%s%%)", args: [Size.hum(freeAfter), String(percent)]))
        if !out.warnings.isEmpty {
            line(colors.yellow, i18n.format("Needs attention: %s", args: [String(out.warnings.count)]))
            for warning in out.warnings { out.write("    \(colors.yellow)!\(colors.reset) \(warning)\n") }
        } else {
            line(colors.green, i18n.translate("Needs attention: nothing"))
        }
        if !newer.isEmpty { line(colors.cyan, i18n.format("macup %s is available: %s", args: [newer, Version.updateCommand(run)])) }
        line(colors.dim, i18n.format("Report: %s · %s", args: [run.env.paths.tildify(run.report.path), took]))
        line(colors.dim, i18n.translate("Menu: macup · trends: macup history · help: macup help"))
    }

    static func notify(_ run: Run) {
        let out = run.out, i18n = out.i18n
        let warnings = out.warnings.count, big = run.potAuto >= 1_048_576
        // nothing to say, no notification: a weekly "all good" teaches people to ignore it
        guard run.arguments.notify, run.shell.which("osascript") != nil, warnings > 0 || big else { return }
        var text = warnings > 0 ? i18n.format("Needs attention: %s", args: [String(warnings)]) : i18n.translate("Needs attention: nothing")
        if big { text += " · " + i18n.format("Could free: ~%s", args: [Size.hum(run.potAuto)]) }
        let script = "display notification \"\(JSON.str(text + ". " + i18n.translate("Details: macup last")))\" with title \"macup\""
        _ = run.shell.tl(0, ["osascript", "-e", script], stdout: .null, stderr: .null)
    }
}

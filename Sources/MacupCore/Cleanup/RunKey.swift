import Foundation

/// run_key: what a cmd candidate's key names, a tool's own clean command or a picked leftover's move to the Trash.
/// `freed` is KEY_FREED, what the tool says it freed; status 2 is "skipped", and the step said why.
extension Cleanup {
    typealias KeyResult = (status: Int32, freed: Int64?)

    static func runKey(_ run: Run, _ key: String) -> KeyResult {
        func plain(_ argv: [String]) -> KeyResult { (run.run(argv), nil) }
        // ${key#prefix} as an unquoted expansion splits it
        func words(_ prefix: String) -> [String] {
            key.dropFirst(prefix.count).split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).map(String.init)
        }
        func eachSimulator(_ prefix: String, _ argv: (String) -> [String]) -> KeyResult {
            for id in words(prefix) where !Cleaners.simulatorID(run, id) || run.run(argv(id)) != 0 { return (1, nil) }
            return (0, nil)
        }
        switch key {
        case "brew":
            let output = Cleaners.outputAndErrors(run, ["brew", "cleanup", "-s", "--prune=7"]).output
            logged(run, output)
            let amount = Cleaners.matches(brewFreed, in: Bash.echo(Bash.substitution(output))).last.map { Awk.field($0, 3) } ?? ""
            return (0, Int64(Size.tokb(amount)))
        case "npm": return plain(["npm", "cache", "verify"])
        case "pnpm": return plain(["pnpm", "store", "prune"])
        case "pip": return plain(["pip3", "cache", "purge"])
        case "uv": return plain(["uv", "cache", "prune"])
        case "go": return plain(["go", "clean", "-cache"])
        case "gomod": return plain(["go", "clean", "-modcache"])
        case "brewauto": return plain(["brew", "autoremove"])
        case "quicklook": return plain(["qlmanage", "-r", "cache"])
        case "dockerct", "dockerimg":
            let result = Cleaners.outputAndErrors(run, key == "dockerct" ? ["docker", "container", "prune", "-f"] : ["docker", "image", "prune", "-a", "-f"])
            logged(run, result.output)
            return (result.status == 0 ? 0 : 1, Int64(Size.tokb10(reclaimed(result.output).last ?? "")))
        case "docker":
            var result = Cleaners.outputAndErrors(run, ["docker", "builder", "prune", "-f"])
            if result.status == 0 {
                let images = Cleaners.outputAndErrors(run, ["docker", "image", "prune", "-f"])
                result = (images.status, result.output + images.output)
            }
            logged(run, result.output)
            return (result.status == 0 ? 0 : 1, reclaimed(result.output).reduce(0) { $0 + (Int64(Size.tokb10($1)) ?? 0) })
        case _ where key.hasPrefix("sim:"):
            // the sets that have some: sim:[default] [tests]
            var status: Int32 = 0
            if key.contains("default"), run.run(["xcrun", "simctl", "delete", "unavailable"]) != 0 { status = 1 }
            if key.contains("tests"), run.run(["xcrun", "simctl", "--set", run.env.dev + "/XCTestDevices", "delete", "unavailable"]) != 0 { status = 1 }
            return (status, nil)
        case _ where key.hasPrefix("simrt:"):
            // simrt:<id> <kb>
            let parts = words("simrt:"), id = parts.first ?? ""
            guard Cleaners.simulatorID(run, id) else { return (1, nil) }
            let status = run.run(["xcrun", "simctl", "runtime", "delete", id])
            return (status, status == 0 && parts.count > 1 ? Int64(parts[1]) : nil)
        case _ where key.hasPrefix("simerase:"): return eachSimulator("simerase:") { ["xcrun", "simctl", "erase", $0] }
        case _ where key.hasPrefix("simdel:"): return eachSimulator("simdel:") { ["xcrun", "simctl", "delete", $0] }
        case _ where key.hasPrefix("orph:"): return Leftovers.removeAgent(run, Int(key.dropFirst(5)) ?? -1)
        case _ where key.hasPrefix("odata:"): return Leftovers.removeData(run, Int(key.dropFirst(6)) ?? -1)
        case _ where key.hasPrefix("devc:"): return Leftovers.removeContainer(run, String(key.dropFirst(5)))
        default: return (0, nil)
        }
    }

    private static let brewFreed = try! NSRegularExpression(pattern: "freed approximately [0-9.]*[KMGT]*B")

    /// `echo "$out" >>"$RAW"`.
    private static func logged(_ run: Run, _ output: String) {
        run.log.append(Bash.echo(Bash.substitution(output)))
    }

    /// `echo "$out" | sed -n 's/^Total reclaimed space: *//p'`.
    private static func reclaimed(_ output: String) -> [String] {
        let marker = "Total reclaimed space:"
        return Bash.lines(Bash.substitution(output)).compactMap { line in
            guard line.unicodeScalars.starts(with: marker.unicodeScalars) else { return nil }
            return String(String.UnicodeScalarView(line.unicodeScalars.dropFirst(marker.unicodeScalars.count).drop { $0 == " " }))
        }
    }
}

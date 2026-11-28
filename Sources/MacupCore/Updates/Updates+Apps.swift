import Darwin
import Foundation

/// App Store apps through mas, and apps from a download that are behind Homebrew's cask catalog.
extension Updates {
    static func appStore(_ run: Run) {
        let out = run.out, shell = run.shell
        guard shell.have("mas") else { out.info("App Store apps aren't checked: brew install mas"); return }
        out.step("App Store")
        // "497799835 Xcode (27.1 → 27.2)": the id for mas, the rest for people
        let outdated = Bash.substitution(Bash.lines(timedOutput(run, 180, ["mas", "outdated"]).text).map(masLine).joined(separator: "\n"))
        let count = Run.count(outdated)
        let names = Bash.lines(outdated).map { line in
            line.unicodeScalars.firstIndex(of: " ").map { String(line.unicodeScalars[line.unicodeScalars.index(after: $0)...]) } ?? line
        }.joined(separator: "\n")   // cut -d' ' -f2-
        guard count > 0 else { out.ok("App Store: up to date"); return }
        guard run.updates else {
            out.warn("App Store: updates: %s", String(count))
            run.lines(names)
            return
        }
        out.info("App Store: updates: %s", String(count))
        run.lines(names)
        var log = run.log
        log.runSeconds = log.stepSeconds.saturatingTimes(4)   // an Xcode download alone can take longer than any other step
        var number = 0
        for line in Bash.lines(outdated) {
            let words = read(line, 2), id = words[0], app = words[1]
            guard !id.isEmpty else { continue }
            number += 1
            // mas runs itself through sudo, which would ask a bare "Password:" in the middle of the step line
            if !shell.sudoCached {
                var given = Terminal.available
                if given {
                    out.write(out.colors.cl)
                    given = shell.askSudo("  " + Bash.substitution(out.i18n.translate("Mac password to install App Store updates:")) + " ")
                }
                guard given else {
                    out.err("App Store: updates not installed: %s — they need your Mac password", String(count - number + 1))
                    break
                }
                run.sudo.asked = true
            }
            // sudo forgets the password after 5 minutes and one install (Xcode) takes longer, so it would ask again for the next app
            run.sudo.keepAlive()
            let outside = shell.vars["RUN_SECS"]
            shell.vars["RUN_SECS"] = String(log.runSeconds ?? log.stepSeconds)   // bash's `RUN_SECS=… tick` exports it to mas
            let status = shell.tick("App Store \(number)/\(count): \(app)", ["mas", "upgrade", id], log: log, output: out)
            shell.vars["RUN_SECS"] = outside
            if status == 0 {
                out.ok("%s: %s", "App Store", app)
                run.doneUpdate("%s: %s", "App Store", app)
            } else {
                out.err("App Store: updates not installed: %s — open the App Store", app)
            }
        }
        run.sudo.stop()
    }

    /// `sed -E 's/^ +//; s/ +/ /g; s/ -> / → /'`
    static func masLine(_ line: String) -> String {
        var out = String.UnicodeScalarView()
        for scalar in line.unicodeScalars where !(scalar == " " && (out.isEmpty || out.last == " ")) { out.append(scalar) }
        let text = String(out)
        guard let arrow = text.range(of: " -> ") else { return text }
        return text.replacingCharacters(in: arrow, with: " → ")
    }


    /// Apps installed from a download update themselves; macup only says which are behind the Homebrew catalog.
    static func apps(_ run: Run) {
        let out = run.out, label = "Apps outside Homebrew and the App Store"
        out.step(label)
        let catalog = run.env.cacheDir + "/cask.json", fresh = catalog + ".new"
        try? FileManager.default.createDirectory(atPath: run.env.cacheDir, withIntermediateDirectories: true)
        // -z: downloads the catalog (about 20 MB) only when it changed; a failed download keeps the last copy
        let ifNewer = Files.hasContent(catalog) ? ["-z", catalog] : []
        let curl = ["curl", "-fsSL", "--compressed", "--max-time", "60"] + ifNewer + ["-o", fresh, "https://formulae.brew.sh/api/cask.json"]
        if run.shell.tl(0, curl, stderr: .null) == 0, Files.hasContent(fresh) { rename(fresh, catalog) }
        unlink(fresh)
        guard Files.hasContent(catalog), let (checked, behind) = appsBehind(run, catalog) else {
            out.warn("%s: could not check for updates", out.i18n.translate(label))
            return
        }
        if !behind.isEmpty {
            // the names go into the warning itself: the summary shows warnings without their detail lines
            let names = behind.map { $0.replacing(#/ [^ ]+ → [^ ]+$/#, with: "") }
            out.warn("Apps with a newer version: %s (%s) — open or restart them to update", String(behind.count), names.joined(separator: ",").replacingOccurrences(of: ",", with: ", "))
            run.lines(behind.joined(separator: "\n"))
        } else if checked > 0 {
            out.ok("Apps outside Homebrew and the App Store: up to date (%s checked)", String(checked))
        }
    }

    /// macup_helpers.py `apps-behind`: how many apps were compared with the catalog, and "App have → new" for those behind it.
    /// nil where Python would stop with an error.
    static func appsBehind(_ run: Run, _ catalog: String) -> (checked: Int, behind: [String])? {
        let brewed = Set(run.shell.capture(["brew", "list", "--cask"]).output.split(whereSeparator: \.isWhitespace).map(String.init))
        var casks: [JSONValue] = []
        switch JSONValue.parse(file: catalog) {
        case .array(let items)?: casks = items
        case .string("")?: break   // Python iterates nothing in these
        case .object(let entries)? where entries.isEmpty: break
        default: return nil
        }
        // app name → (token, version) of each cask that installs it, as code points: a name is a key exactly as Python has it
        var byApp: [[Unicode.Scalar]: [(token: String, version: String)]] = [:]
        for cask in casks {
            guard case .object = cask, let token = cask["token"]?.string else { return nil }
            if token.contains("@") { continue }   // beta and other channels of the same app
            var artifacts: [JSONValue] = []
            switch cask["artifacts"] {
            case .array(let items)?: artifacts = items
            case nil, .string("")?: break   // Python iterates nothing in these
            case .object(let entries)? where entries.isEmpty: break
            default: return nil
            }
            let version = String((cask["version"] ?? .string("")).pythonString.split(separator: ",", omittingEmptySubsequences: false).first ?? "")
            for artifact in artifacts {
                guard case .object = artifact else { return nil }
                var app: String?
                switch artifact["app"] {
                case .array(let names)?: app = names.first?.string
                case .string(let name)? where !name.isEmpty: app = String(name.unicodeScalars.first!)
                case let other? where other.isTruthy: return nil
                default: break
                }
                if let app { byApp[Array(app.unicodeScalars), default: []].append((token, version)) }
            }
        }
        // brew upgrade covers casks brew installed; two casks with one app name and different versions are different apps (Telegram)
        var latest: [[Unicode.Scalar]: String] = [:]
        for (app, found) in byApp where !found.contains(where: { brewed.contains($0.token) }) && Set(found.map { Array($0.version.unicodeScalars) }).count == 1 {
            latest[app] = found[0].version
        }
        var checked = 0, behind: [String] = []
        for folder in ["/Applications", run.env.home + "/Applications"] where Run.isDirectory(folder) {
            guard let names = (try? FileManager.default.contentsOfDirectory(atPath: folder))?.sorted(by: Names.codePointOrder) else { return nil }
            for name in names {
                let path = folder + "/" + name
                guard let new = latest[Array(name.unicodeScalars)], !Run.isDirectory(path + "/Contents/_MASReceipt") else { continue }
                guard let data = FileManager.default.contents(atPath: path + "/Contents/Info.plist"),
                      let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) else { continue }
                guard let info = plist as? [String: Any] else { return nil }
                let have = String(bundleVersion(info).split(separator: " ", omittingEmptySubsequences: false).first ?? "")
                if have.isEmpty || new == "latest" { continue }
                checked += 1
                if versionKey(have).lexicographicallyPrecedes(versionKey(new)) {
                    behind.append("\(String(String.UnicodeScalarView(name.unicodeScalars.dropLast(4)))) \(have) → \(new)")
                }
            }
        }
        return (checked, behind)
    }

    /// `str(CFBundleShortVersionString or CFBundleVersion or "")`
    private static func bundleVersion(_ info: [String: Any]) -> String {
        for key in ["CFBundleShortVersionString", "CFBundleVersion"] {
            switch info[key] {
            case let text as String where !text.isEmpty: return text
            case let number as NSNumber where number.doubleValue != 0:
                if CFGetTypeID(number) == CFBooleanGetTypeID() { return "True" }
                return CFNumberIsFloatType(number) ? JSONValue.number("\(number.doubleValue)").pythonString : number.stringValue
            default: continue
            }
        }
        return ""
    }

    /// `[int(x) for x in re.findall(r"\d+", version)]`, each number as its digits without leading zeros, compared by length first.
    static func versionKey(_ version: String) -> [VersionNumber] {
        var numbers: [VersionNumber] = [], digits: [UInt32] = []
        for scalar in version.unicodeScalars + [" "] {
            if scalar.properties.numericType == .decimal, let value = scalar.properties.numericValue {
                digits.append(UInt32(value))
            } else if !digits.isEmpty {
                numbers.append(VersionNumber(digits: Array(digits.drop(while: { $0 == 0 }))))
                digits = []
            }
        }
        return numbers
    }

    struct VersionNumber: Comparable {
        let digits: [UInt32]
        static func < (left: VersionNumber, right: VersionNumber) -> Bool {
            left.digits.count != right.digits.count ? left.digits.count < right.digits.count : left.digits.lexicographicallyPrecedes(right.digits)
        }
    }
}

import Foundation

/// check.macos_updates: what `softwareupdate -l` lists; macup never installs it.
extension Updates {
    static func macOS(_ run: Run) {
        let out = run.out
        out.step("Looking for macOS updates (up to a minute)")
        let limit = 240
        let listed = timedOutput(run, limit, ["softwareupdate", "-l"], errors: true)
        let blank = { Config.isSpace($0, utf8: run.env.utf8Locale) }
        func after(_ prefix: String) -> [String] {
            Bash.lines(listed.text).compactMap { line in
                let rest = Substring(line).unicodeScalars.drop(while: blank)
                return rest.starts(with: prefix.unicodeScalars) ? String(rest.dropFirst(prefix.unicodeScalars.count)) : nil
            }
        }
        let labels = Bash.substitution(after("* Label: ").map { $0 + "\n" }.joined())
        // a Label is an id ("Command Line Tools for Xcode 27.2-27.2"); some Titles carry no version ("Safari")
        let titles = Bash.substitution(after("Title: ").map { title($0) + "\n" }.joined())
        if listed.status == 124 {
            out.warn("%s: no answer in %s seconds, skipped", "softwareupdate", String(limit))
        } else if labels.isEmpty, listed.status != 0 || saysOffline(listed.text) {
            out.info("macOS updates: could not check (no connection to Apple's server?)")
        } else if labels.isEmpty {
            out.ok("macOS: up to date")
        } else {
            out.warn("macOS: updates available — System Settings → General → Software Update")
            run.lines(titles.isEmpty ? labels : titles)
        }
    }

    /// awk -F', Version: ' '{v=$2; sub(/,.*/, "", v); print (v == "" || index($1, v)) ? $1 : $1 " " v}'
    static func title(_ line: String) -> String {
        guard let separator = line.range(of: ", Version: ", options: .literal) else { return line }
        let name = String(line[..<separator.lowerBound])
        let version = String(String.UnicodeScalarView(line[separator.upperBound...].unicodeScalars.prefix { $0 != "," }))
        return version.isEmpty || name.range(of: version, options: .literal) != nil ? name : name + " " + version
    }

    /// grep -qiE 'error|could not|unable to|not connected|no internet|offline'
    static func saysOffline(_ text: String) -> Bool {
        let folded = String(String.UnicodeScalarView(text.unicodeScalars.map { ("A"..."Z").contains($0) ? Unicode.Scalar($0.value + 32)! : $0 }))
        return ["error", "could not", "unable to", "not connected", "no internet", "offline"].contains { folded.range(of: $0, options: .literal) != nil }
    }
}

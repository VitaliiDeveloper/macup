import Foundation

/// clean.dev_containers: containers in ~/Library/Containers named by dev_container_prefixes whose app is gone.
/// Interactive only: reading other apps' containers can raise a privacy prompt, and only a person can pick them.
extension Leftovers {
    /// The cleaners call it where cleaners.sh registers dev containers, before the Gradle caches.
    static func registerDevContainers(_ run: Run) {
        guard run.taskAllowed("clean.dev_containers"), state(run).interactive, !devPrefixes(run).isEmpty else { return }
        preconditionFailure("the dev container scan needs lsof, which comes with the pick")
    }

    private static let prefixPattern = try! NSRegularExpression(pattern: "^[A-Za-z0-9-]+(\\.[A-Za-z0-9-]+)+$")

    /// `dev_prefixes`: a prefix needs a dot and never names Apple's own apps.
    static func devPrefixes(_ run: Run) -> [String] {
        Bash.echoed(run.settings.devPrefixes).split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\n" }).map(String.init).filter { prefix in
            let lower = prefix.lowercased()
            return Checks.matches(prefixPattern, prefix) && lower != "com.apple" && !lower.hasPrefix("com.apple.")
        }
    }

    /// `dev_container`: a folder right in ~/Library/Containers named by a prefix or below it.
    static func devContainer(_ run: Run, _ path: String) -> Bool {
        let name = basename(path)
        guard path == "\(run.env.home)/Library/Containers/\(name)",
              name.unicodeScalars.allSatisfy({ ("A"..."Z").contains($0) || ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "." || $0 == "-" }),
              !name.lowercased().hasPrefix("com.apple.") else { return false }
        return devPrefixes(run).contains { name == $0 || name.hasPrefix($0 + ".") }
    }
}

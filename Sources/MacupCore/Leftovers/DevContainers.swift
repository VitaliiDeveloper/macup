import Foundation

/// clean.dev_containers: containers in ~/Library/Containers named by dev_container_prefixes whose app is gone.
/// Interactive only: reading other apps' containers can raise a privacy prompt, and only a person can pick them.
extension Leftovers {
    /// The cleaners call it where cleaners.sh registers dev containers, before the Gradle caches.
    static func registerDevContainers(_ run: Run) {
        guard run.taskAllowed("clean.dev_containers"), state(run).interactive, !devPrefixes(run).isEmpty else { return }
        preconditionFailure("the dev container scan needs lsof, which comes with the pick")
    }

    /// `app_for`: Spotlight does not index extensions and helpers inside an app, so a container stays while any parent id
    /// has an app: dev.app for dev.app.share, and for dev.app-LaunchAtLoginHelper.
    static func appFor(_ run: Run, _ id: String) -> Bool {
        var id = id
        while true {
            if !(Bash.lines(run.shell.capture(["mdfind", "kMDItemCFBundleIdentifier == '\(id)'c"]).output).first ?? "").isEmpty { return true }
            guard let cut = id.unicodeScalars.lastIndex(where: { $0 == "." || $0 == "-" }) else { return false }
            let up = String(id.unicodeScalars[..<cut])
            guard up.contains(".") else { return false }
            id = up
        }
    }

    /// `newest`: the date of the container's newest file; the folder's own date and macOS's marker say when it was made.
    static func newest(_ run: Run, _ container: String) -> String {
        let times = run.shell.capture(["find", container, "-type", "f", "!", "-name", ".com.apple.containermanagerd.metadata.plist", "-exec", "stat", "-f", "%m", "{}", "+"])
        var newest = Bash.lines(times.output).compactMap { Int(Awk.firstField($0)) }.max()
        if newest == nil {
            var info = stat()
            if lstat(container, &info) == 0 { newest = info.st_mtimespec.tv_sec }
        }
        return newest.map { Run.date("%F", time_t($0)) } ?? ""   // date -r "" prints nothing
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

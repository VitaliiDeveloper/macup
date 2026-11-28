import Foundation

/// Interactive only: reading other apps' containers can raise a privacy prompt, and only a person can pick them.
extension Leftovers {
    /// The cleaners call it where cleaners.sh registers dev containers, before the Gradle caches.
    static func registerDevContainers(_ run: Run) {
        guard run.taskAllowed("clean.dev_containers"), state(run).interactive, !devPrefixes(run).isEmpty else { return }
        let out = run.out
        out.step("Looking for containers of dev builds")
        guard spotlightFinds(run, "kMDItemCFBundleIdentifier == 'com.apple.finder'") else {
            out.info("Dev containers: Spotlight does not answer, so macup cannot tell which apps are gone; nothing offered")
            return
        }
        let files = Cleanup.openFiles(run.shell)
        for container in Names.glob(run.env.home + "/Library/Containers", "*") {
            let name = basename(container)
            guard Run.isDirectory(container), !Run.isSymlink(container), devContainer(run, container), !appFor(run, name) else { continue }
            // lsof that cannot tell: in use, without asking it again
            if files.map({ Cleanup.openIn(run.shell, container, snapshot: $0) }) ?? true {
                out.info("%s: %s — skipped while the app is open", name, Size.hum(run.kb(container)))
                continue
            }
            guard (try? FileManager.default.contentsOfDirectory(atPath: container)) != nil else {
                out.info("%s: cannot be read — give your terminal Full Disk Access (System Settings → Privacy & Security)", name)
                continue
            }
            let items = Bash.substitution(run.shell.capture(["find", container, "-mindepth", "1", "-maxdepth", "1", "!", "-name", containerMarker]).output)
            guard !items.isEmpty else { continue }   // emptied before: only the marker macOS keeps is left
            run.register(task: "clean.dev_containers", level: 3,
                         label: out.i18n.format("Container of a dev build whose app is gone: %s (changed %s)", args: [name, newest(run, container)]),
                         kb: run.kbl(items), kind: .cmd, paths: "devc:\(container)", open: container, manual: true)
        }
    }

    /// `[ -n "$(mdfind "$query" | head -1)" ]`
    static func spotlightFinds(_ run: Run, _ query: String) -> Bool {
        !(Bash.lines(run.shell.capture(["mdfind", query]).output).first ?? "").isEmpty
    }

    /// `app_for`: Spotlight does not index extensions and helpers inside an app, so a container stays while any parent id
    /// has an app: dev.app for dev.app.share, and for dev.app-LaunchAtLoginHelper.
    static func appFor(_ run: Run, _ id: String) -> Bool {
        var id = id
        while true {
            if spotlightFinds(run, "kMDItemCFBundleIdentifier == '\(id)'c") { return true }
            guard let cut = id.unicodeScalars.lastIndex(where: { $0 == "." || $0 == "-" }) else { return false }
            let up = String(id.unicodeScalars[..<cut])
            guard up.contains(".") else { return false }
            id = up
        }
    }

    /// `newest`: the date of the container's newest file; the folder's own date and macOS's marker say when it was made.
    static func newest(_ run: Run, _ container: String) -> String {
        let times = run.shell.capture(["find", container, "-type", "f", "!", "-name", containerMarker, "-exec", "stat", "-f", "%m", "{}", "+"])
        var newest = Bash.lines(times.output).compactMap { Int(Awk.firstField($0)) }.max()
        if newest == nil {
            var info = stat()
            if lstat(container, &info) == 0 { newest = info.st_mtimespec.tv_sec }
        }
        return newest.map { Run.date("%F", time_t($0)) } ?? ""   // date -r "" prints nothing
    }

    private static let prefixPattern = try! NSRegularExpression(pattern: "^[A-Za-z0-9-]+(\\.[A-Za-z0-9-]+)+$")

    static func devPrefixes(_ run: Run) -> [String] {
        Bash.echoed(run.settings.devPrefixes).split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\n" }).map(String.init).filter { prefix in
            let lower = prefix.lowercased()
            return prefixPattern.hasMatch(in: prefix) && lower != "com.apple" && !Bash.starts(lower, "com.apple.")
        }
    }

    static func devContainer(_ run: Run, _ path: String) -> Bool {
        let name = basename(path)
        guard path == "\(run.env.home)/Library/Containers/\(name)",
              name.unicodeScalars.allSatisfy({ ("A"..."Z").contains($0) || ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "." || $0 == "-" }),
              !name.lowercased().hasPrefix("com.apple.") else { return false }
        return devPrefixes(run).contains { name == $0 || name.hasPrefix($0 + ".") }
    }
}

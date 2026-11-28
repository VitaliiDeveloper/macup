import Darwin
import Foundation

/// Homebrew, old logs, provisioning profiles, the Trash and Docker.
extension Cleaners {
    static func brewPreviewFile(_ run: Run) -> String { run.report.body + ".du.brew" }

    /// What `brew cleanup -n` would free is asked at the start, in the background: it takes seconds.
    static func startBrewPreview(_ run: Run) -> pid_t? {
        guard run.taskAllowed("clean.brew"), run.shell.have("brew") else { return nil }
        return run.shell.spawn(["brew", "cleanup", "-s", "--prune=7", "-n"], stdin: .null, stdout: .file(brewPreviewFile(run)), stderr: .null)
    }

    static func brew(_ run: Run, _ preview: pid_t?) {
        guard run.taskAllowed("clean.brew"), run.shell.have("brew") else { return }
        run.candidates.cover(Checks.output(run, ["brew", "--cache"]))
        let text: String
        if let preview {
            _ = Shell.wait(preview)
            text = String(decoding: FileManager.default.contents(atPath: brewPreviewFile(run)) ?? Data(), as: UTF8.self)
        } else {
            text = run.shell.capture(["brew", "cleanup", "-s", "--prune=7", "-n"], stdin: .inherit).output
        }
        let free = matches(freeApproximately, in: text).last.map { Awk.field($0, 3) } ?? ""
        run.register(task: "clean.brew", level: 1, label: translate(run, "Homebrew old versions & downloads"), kb: free.isEmpty ? 0 : Int64(Size.tokb(free)) ?? 0,
                     kind: .cmd, paths: "brew")
    }

    static let freeApproximately = try! NSRegularExpression(pattern: "free approximately [0-9.]*[KMGT]*B")

    /// npm keeps a log per failed command, a Gradle daemon one per start: nobody reads them a month later.
    static func logs(_ run: Run) {
        guard run.taskAllowed("clean.logs") else { return }
        let home = run.env.home
        let old = Bash.substitution(
            run.shell.capture(["find", home + "/Library/Logs", "-type", "f", "-mtime", "+30", "-not", "-path", run.env.logDir + "/*"], stdin: .inherit).output
                + run.shell.capture(["find", home + "/.npm/_logs", home + "/.gradle/daemon", "-type", "f", "-name", "*.log", "-mtime", "+30"], stdin: .inherit).output)
        guard !old.isEmpty else { return }
        let sizes = filter(run, ["xargs", "-0", "du", "-sk"], (old + "\n").replacingOccurrences(of: "\n", with: "\0"))
        let total = Bash.lines(sizes).reduce(0.0) { $0 + Awk.number(Awk.firstField($1)) }
        let size = Int64(Checks.awkNumber(total)) ?? 0
        guard size >= 1024 else { return }
        run.register(task: "clean.logs", level: 1, label: format(run, "Old logs & crash reports (%s files)", String(Run.count(old))), kb: size, kind: .rm,
                     paths: old, keySource: "logs")
    }

    /// Provisioning profiles past their date sign nothing; Xcode downloads the ones it manages again.
    static func profiles(_ run: Run) {
        guard run.taskAllowed("clean.profiles") else { return }
        let home = run.env.home
        let expired = expiredProfiles([home + "/Library/MobileDevice/Provisioning Profiles", home + "/Library/Developer/Xcode/UserData/Provisioning Profiles"])
            .joined(separator: "\n")
        guard !expired.isEmpty else { return }
        run.register(task: "clean.profiles", level: 1, label: format(run, "Expired provisioning profiles (%s)", String(Run.count(expired))), kb: run.kbl(expired),
                     kind: .rm, paths: expired, keySource: "profiles")
    }

    /// 2.9's inline Python: the profiles whose ExpirationDate has passed; an unreadable one is not ours to judge.
    static func expiredProfiles(_ folders: [String]) -> [String] {
        var expired: [String] = []
        for folder in folders where realFolder(folder) {
            // Python stops at a folder it cannot list
            guard let names = sortedNames(folder) else { return expired }
            expired += names.map { "\(folder)/\($0)" }.filter { path in
                guard path.hasSuffix(".mobileprovision") || path.hasSuffix(".provisionprofile"), !Run.isSymlink(path), isFile(path),
                      let raw = FileManager.default.contents(atPath: path),
                      let start = raw.range(of: Data("<?xml".utf8)), let end = raw.range(of: Data("</plist>".utf8), in: start.lowerBound..<raw.endIndex),
                      let plist = try? PropertyListSerialization.propertyList(from: raw[start.lowerBound..<end.upperBound], format: nil) as? [String: Any],
                      let expiry = plist["ExpirationDate"] as? Date else { return false }
                return expiry < Date()
            }
        }
        return expired
    }

    /// Python's `sorted(os.listdir(folder))`: by code point.
    static func sortedNames(_ folder: String) -> [String]? {
        (try? FileManager.default.contentsOfDirectory(atPath: folder))?.sorted(by: Names.codePointOrder)
    }

    /// `os.path.isfile`: a regular file, through a link.
    static func isFile(_ path: String) -> Bool {
        var info = stat()
        return stat(path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFREG
    }

    /// Without Full Disk Access the terminal cannot even list the Trash: it says so instead of a silent 0.
    static func trash(_ run: Run) {
        guard run.taskAllowed("clean.trash") else { return }
        let trash = run.env.home + "/.Trash"
        if Run.isDirectory(trash), !Checks.readable(trash) {
            if run.task("clean.trash") { run.out.warn("Trash: cannot be read — give your terminal Full Disk Access (System Settings → Privacy & Security)") }
        } else {
            run.register(task: "clean.trash", level: 3, label: translate(run, "Trash"), kb: run.kb(trash), kind: .empty, paths: trash)
        }
    }

    /// Volumes hold databases and are never touched. Images and stopped containers only when you pick them.
    static func docker(_ run: Run) {
        guard run.shell.have("docker"), ["clean.docker", "clean.docker_images", "clean.docker_containers"].contains(where: run.taskAllowed),
              run.shell.tl(20, ["docker", "info"], stdout: .null, stderr: .null) == 0 else { return }
        let table = Updates.timedOutput(run, 30, ["docker", "system", "df", "--format", "{{.Type}}|{{.Reclaimable}}"]).text
        // "1.2GB (50%)" → KB
        func reclaimable(_ type: String) -> Int64 {
            let values = Bash.lines(table).filter { line in
                let first = line.components(separatedBy: "|")[0]
                return Awk.isNumber(first) && Awk.isNumber(type) ? Awk.number(first) == Awk.number(type) : same(first, type)
            }.map { line -> String in
                let fields = line.components(separatedBy: "|")
                return Awk.firstField(fields.count > 1 ? fields[1] : "")
            }
            return Int64(Size.tokb10(Bash.substitution(values.map { $0 + "\n" }.joined()))) ?? 0
        }
        run.register(task: "clean.docker", level: 2, label: translate(run, "Docker build cache and dangling images (never volumes)"), kb: reclaimable("Build Cache"),
                     kind: .cmd, paths: "docker")
        let images = reclaimable("Images")
        if images >= 1024 {
            run.register(task: "clean.docker_images", level: 2, label: translate(run, "Docker images no container uses (docker pulls or builds them again)"),
                         kb: images, kind: .cmd, paths: "dockerimg")
        }
        let stopped = Run.count(Updates.timedOutput(run, 30, ["docker", "ps", "-aq", "-f", "status=exited", "-f", "status=created", "-f", "status=dead"]).text)
        if stopped > 0 {
            run.register(task: "clean.docker_containers", level: 3,
                         label: format(run, "Stopped Docker containers (%s): files saved inside them are lost, volumes stay", String(stopped)),
                         kb: reclaimable("Containers"), kind: .cmd, paths: "dockerct")
        }
    }

    /// Homebrew packages that came only as dependencies of something already removed.
    static func brewAutoremove(_ run: Run) {
        guard run.taskAllowed("clean.brew_autoremove"), run.shell.have("brew") else { return }
        let names = Bash.lines(Updates.timedOutput(run, 60, ["brew", "autoremove", "--dry-run"]).text).filter { !$0.isEmpty && !$0.hasPrefix("==>") }
        guard !names.isEmpty else { return }
        run.register(task: "clean.brew_autoremove", level: 2, label: format(run, "Homebrew packages nothing needs any more: %s", commaList(names)), kb: 0,
                     kind: .cmd, paths: "brewauto")
    }
}

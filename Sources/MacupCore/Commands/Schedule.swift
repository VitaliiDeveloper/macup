import Darwin
import Foundation

/// `macup schedule` (commands.sh `schedule`, `sched_off`): an optional LaunchAgent that runs `macup check` on its own and
/// shows a notification. A check installs and deletes nothing, so the schedule never changes the Mac behind your back.
/// The job runs this binary itself; 2.9's ran `/bin/bash <path>`, which `repair` moves onto the binary.
public enum Schedule {
    static func run(_ context: OneOff.Context) -> Int32 {
        let env = context.env, plist = env.schedPlist
        let say = { (text: String) in context.out.write(context.i18n.translate(text) + "\n") }
        let shown = {
            say(weekly(plist) ? "Schedule: macup check every Monday at 10:00, with a notification." : "Schedule: macup check every day at 10:00, with a notification.")
            say("Turn it off: macup schedule off")
        }
        let launchctl = Launchctl(env: env, shell: context.shell)
        switch context.arguments.schedArg {
        case "":
            if Files.isRegular(plist) { shown(); return 0 }
            say("No schedule: macup runs only when you start it.")
            say("Turn it on: macup schedule weekly (or daily). It runs macup check, which changes nothing, and shows a notification.")
        case "off", "remove", "stop":
            if Files.isRegular(plist) { launchctl.remove(); say("Schedule removed.") } else { say("No schedule: macup runs only when you start it.") }
        case let period where period == "daily" || period == "weekly":
            var program = SelfPath.current()
            if !program.hasPrefix("/") { program = FileManager.default.currentDirectoryPath + "/" + (program.hasPrefix("./") ? String(program.dropFirst(2)) : program) }
            guard Files.isRegular(program) else { say(context.i18n.format("Couldn't write %s", env.paths.tildify(plist))); return 1 }
            try? FileManager.default.createDirectory(atPath: SelfPath.dirname(plist), withIntermediateDirectories: true)
            try? FileManager.default.createDirectory(atPath: env.logDir, withIntermediateDirectories: true)
            if Files.isRegular(plist) { launchctl.remove() }
            let written = (try? text(program: program, weekly: period == "weekly", path: env.path, log: env.logDir + "/schedule.log")
                .write(toFile: plist, atomically: false, encoding: .utf8)) != nil
            guard written, launchctl.load(retry: false) else {
                unlink(plist)
                say("launchd did not accept the schedule; nothing changed.")
                return 1
            }
            shown()
        default:
            context.out.write("macup schedule daily | weekly | off\n")
            return 2
        }
        return 0
    }

    static func weekly(_ plist: String) -> Bool {
        FileManager.default.contents(atPath: plist).map { $0.range(of: Data("<key>Weekday</key>".utf8)) != nil } ?? false
    }

    /// The LaunchAgent as the bash build writes it, without its /bin/bash. launchd starts programs with a bare PATH: the
    /// scheduled check gets today's, so it finds the same tools (nvm's node, ~/.cargo/bin).
    static func text(program: String, weekly: Bool, path: String, log: String) -> String {
        let day = weekly ? "<key>Weekday</key><integer>1</integer>" : ""
        return """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
              <key>Label</key><string>\(Env.schedLabel)</string>
              <key>ProgramArguments</key>
              <array><string>\(escaped(program))</string><string>check</string><string>--quiet</string><string>--notify</string></array>
              <key>StartCalendarInterval</key>
              <dict>\(day)<key>Hour</key><integer>10</integer><key>Minute</key><integer>0</integer></dict>
              <key>EnvironmentVariables</key>
              <dict><key>PATH</key><string>\(escaped(path))</string></dict>
              <key>StandardOutPath</key><string>\(escaped(log))</string>
              <key>StandardErrorPath</key><string>\(escaped(log))</string>
              <key>ProcessType</key><string>Background</string>
            </dict>
            </plist>

            """
    }

    static func newer(_ path: String, than other: String) -> Bool {
        var first = stat(), second = stat()
        guard stat(path, &first) == 0, stat(other, &second) == 0 else { return false }
        let (stamped, changed) = (first.st_mtimespec, second.st_mtimespec)
        return (stamped.tv_sec, stamped.tv_nsec) >= (changed.tv_sec, changed.tv_nsec)
    }

    static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }

    static func unescaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&amp;", with: "&")
    }

    static let bashArray = "<array><string>/bin/bash</string>"

    /// The program a schedule runs and whether 2.9 wrote it after /bin/bash; nil for a plist without ProgramArguments.
    static func program(in plist: String) -> (path: String, bash: Bool)? {
        let legacy = plist.range(of: bashArray)
        guard let start = (legacy?.upperBound).map({ plist[$0...].range(of: "<string>") }) ?? plist.range(of: "<array><string>"),
              let end = plist[start.upperBound...].range(of: "</string>") else { return nil }
        return (unescaped(String(plist[start.upperBound..<end.lowerBound])), legacy != nil)
    }

    /// A 2.9 schedule runs `/bin/bash <path>`; with this binary at <path> launchd fails on every run. From a run that launchd
    /// did not start, a schedule naming this binary (after symlinks) loses its /bin/bash and is loaded again, and so is a
    /// loaded job that still runs /bin/bash. Never from the scheduled run itself: bootout would stop it before bootstrap.
    public static func repair(_ env: Env, translations: String) {
        guard getuid() != 0, getppid() != 1, ProcessInfo.processInfo.environment["XPC_SERVICE_NAME"] != Env.schedLabel,
              let data = FileManager.default.contents(atPath: env.schedPlist) else { return }
        let plist = String(decoding: data, as: UTF8.self)
        guard let program = program(in: plist), let resolved = realpath(program.path, nil) else { return }
        defer { free(resolved) }
        guard String(cString: resolved) == SelfPath.executable() else { return }
        let shell = Shell(env: env), launchctl = Launchctl(env: env, shell: shell)
        if program.bash {
            guard replace(env.schedPlist, with: plist.replacingOccurrences(of: bashArray, with: "<array>")) else { return }
        } else {
            // looked at once after each change of the plist, not on every run
            let stamp = env.stateDir + "/schedule_checked"
            guard !newer(stamp, than: env.schedPlist), let bash = launchctl.runsBash() else { return }
            if !bash {
                try? FileManager.default.createDirectory(atPath: env.stateDir, withIntermediateDirectories: true)
                FileManager.default.createFile(atPath: stamp, contents: nil)
                return
            }
        }
        launchctl.unload()
        if launchctl.load(retry: true) { return }
        var config = Config(env: env)
        config.reportsErrors = false
        let i18n = I18n(lang: Lang.initial(env: env, config: config, shell: shell), translationsJSON: translations)
        Shell.writeText(i18n.translate("launchd did not take the updated schedule; it applies after the next login.") + "\n", to: 2)
    }

    /// By rename from a file of its own, so two first runs at once never leave a half-written plist.
    static func replace(_ path: String, with text: String) -> Bool {
        var template = Array("\(SelfPath.dirname(path))/.macup-plist.XXXXXX".utf8CString)
        let descriptor = mkstemp(&template)
        guard descriptor >= 0 else { return false }
        let temporary = String(cString: template)
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        guard fchmod(descriptor, 0o644) == 0, (try? handle.write(contentsOf: Data(text.utf8))) != nil, rename(temporary, path) == 0 else {
            unlink(temporary)
            return false
        }
        return true
    }
}

/// The LaunchAgent's launchctl calls, all quiet.
struct Launchctl {
    let env: Env
    let shell: Shell

    private var domain: String { "gui/\(getuid())" }

    private func quiet(_ argv: [String]) -> Bool {
        shell.spawn(["launchctl"] + argv, stdout: .null, stderr: .null).map(Shell.wait) == 0
    }

    func unload() {
        if !quiet(["bootout", "\(domain)/\(Env.schedLabel)"]) { _ = quiet(["unload", env.schedPlist]) }
    }

    /// `sched_off`.
    func remove() {
        unload()
        unlink(env.schedPlist)
    }

    /// Right after a bootout, bootstrap can fail once.
    func load(retry: Bool) -> Bool {
        if quiet(["bootstrap", domain, env.schedPlist]) { return true }
        if retry { sleep(1); if quiet(["bootstrap", domain, env.schedPlist]) { return true } }
        return quiet(["load", "-w", env.schedPlist])
    }

    /// The loaded job still starts /bin/bash (`launchctl print` says `program = /bin/bash`); nil when launchctl cannot say.
    func runsBash() -> Bool? {
        let printed = shell.capture(["launchctl", "print", "\(domain)/\(Env.schedLabel)"])
        return printed.status == 0 ? Launchctl.runsBash(printed.output) : nil
    }

    static func runsBash(_ printed: String) -> Bool {
        Bash.lines(printed).contains { $0.trimmingCharacters(in: .whitespaces) == "program = /bin/bash" }
    }
}

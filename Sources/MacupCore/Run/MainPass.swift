import Darwin
import Foundation

public enum MainPass {
    public static func run(_ arguments: Arguments, env: Env, translations: String) -> Never {
        let started = Date()
        env.apply()
        let shell = Shell(env: env)
        let config = Config(env: env)
        var lang = Lang.initial(env: env, config: config, shell: shell)   // core.sh reads it before the options
        if let chosen = arguments.lang { lang = chosen }
        var colors = Colors.initial(env: env)
        if arguments.noColor { colors = .off }
        let i18n = I18n(lang: lang, translationsJSON: translations)
        let out = Output(i18n: i18n, colors: colors)
        if env.underSudo {
            // under sudo the config, the reports and the history would become root's, and the next plain run could not write them
            out.write(i18n.translate("macup does not need sudo: run it as yourself.") + "\n")
            exit(1)
        }
        let settings = Settings(config: config, env: env, cliSkip: arguments.cliSkip, cliOnly: arguments.cliOnly, cliEnable: arguments.cliEnable, cliLevel: arguments.level)
        func nospace(_ text: String) -> String { String(text.unicodeScalars.filter { $0 != " " }) }
        let unknownInConfig = Tasks.unknown("\(nospace(config.value("skip", ""))),\(nospace(config.value("enable", "")))")
        let fm = FileManager.default
        try? fm.createDirectory(atPath: env.logDir, withIntermediateDirectories: true)
        try? fm.createDirectory(atPath: env.stateDir, withIntermediateDirectories: true)
        // one run at a time: two would update the same tools and delete the same folders
        let lock: RunLock
        switch RunLock.acquire(stateDir: env.stateDir) {
        case .acquired(let held): lock = held
        case .busy(let other):
            out.write(i18n.format("macup is already running (pid %s). If it is not, remove %s", args: [other, env.paths.tildify(env.stateDir + "/lock")]) + "\n")
            exit(1)
        }
        Tidy.run(env: env, settings: settings, shell: shell)
        guard let report = Report.create(env: env) else {
            lock.release()
            Shell.writeText("macup: cannot write a temporary file in \(env.tmpDir)\n", to: 2)
            exit(1)
        }
        let previous = Bash.regularFileContents(env.history).map { Bash.substitution(String(decoding: Tidy.lastLines($0, 1), as: UTF8.self)) } ?? ""
        let run = Run(env: env, arguments: arguments, settings: settings, shell: shell, out: out, report: report, lock: lock, started: started, previous: previous)
        Interrupt.install({ interrupted(run) }, shell: shell)
        out.body = FileHandle(forWritingAtPath: report.body)
        if arguments.json { out.colors = .off; out.json = true }
        // --quiet: only the summary is printed (--json: only the JSON); everything is still in the report
        if arguments.quiet { run.quietDescriptor = quiet() }

        let colorsNow = out.colors
        let note = arguments.dry ? " · " + i18n.translate("nothing is installed or deleted unless you pick it") : ""
        out.write("\(colorsNow.bold)macup \(Env.version)\(colorsNow.reset) · \(run.mode)\(note)\n")
        if !unknownInConfig.isEmpty {
            out.warn("Unknown task in %s: %s (see every id with: macup tasks)", env.paths.tildify(env.conf), unknownInConfig)
        }

        Checks.system(run)
        Checks.security(run)
        Updates.run(run)
        Tools.run(run)
        Cleanup.run(run)
        Checks.sizes(run)
        Leftovers.startup(run)
        Checks.deep(run)
        Summary.write(run)
    }

    private static func quiet() -> Int32 {
        let saved = dup(1)
        let null = open("/dev/null", O_WRONLY)
        dup2(null, 1)
        close(null)
        return saved
    }

    static func interrupted(_ run: Run) -> Never {
        if !run.reportDone {
            let i18n = run.out.i18n
            var text = "# " + i18n.format("macup report — %s", args: [Run.date("%Y-%m-%d %H:%M")]) + "\n\n"
            text += i18n.format("Mode: %s · macup %s · took %s", args: [run.mode, Env.version, Run.duration(run.seconds)]) + "\n\n"
            text += "**" + i18n.translate("Interrupted: this report is incomplete.") + "**\n\n"
            run.writeReport(text, sayingSedErrors: false)
        }
        let colors = run.out.colors
        Shell.writeText("\n\(colors.yellow)\(run.out.i18n.format("Interrupted. Report: %s", args: [run.env.paths.tildify(run.report.path)]))\(colors.reset)\n", to: 2)
        run.end(130)
    }
}

extension Run {
    /// In place and through a symlink, as `>"$REPORT"` writes it.
    func writeReport(_ header: String, sayingSedErrors: Bool) {
        let body = FileManager.default.contents(atPath: report.body) ?? Data()
        let descriptor = open(report.path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        guard descriptor >= 0 else { return }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        try? handle.write(contentsOf: Data(header.utf8) + body + Summary.rawSection(self, sayingSedErrors: sayingSedErrors))
    }

    func end(_ status: Int32) -> Never {
        measure.stop()
        try? out.body?.close()
        for file in [report.body, report.raw] { unlink(file) }
        let folder = (report.body as NSString).deletingLastPathComponent, prefix = (report.body as NSString).lastPathComponent + ".du."
        for name in (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? [] where name.hasPrefix(prefix) { unlink("\(folder)/\(name)") }
        sudo.stop()
        lock.release()
        exit(status)
    }
}

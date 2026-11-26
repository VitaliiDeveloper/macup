import Darwin
import Foundation

/// Where a run keeps what its commands print (core.sh's $RAW) and how long a command may take.
public struct RunLog {
    public let raw: String
    public var stepSeconds: Int
    /// RUN_SECS: a longer limit for one kind of step (App Store installs).
    public var runSeconds: Int?

    public init(raw: String, stepSeconds: Int, runSeconds: Int? = nil) {
        self.raw = raw
        self.stepSeconds = stepSeconds
        self.runSeconds = runSeconds
    }

    func append(_ text: String) {
        let fd = open(raw, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        guard fd >= 0 else { return }
        _ = text.withCString { Darwin.write(fd, $0, strlen($0)) }
        close(fd)
    }
}

public extension Shell {
    /// `run`: the command with its output (both streams) at the end of the report, no input, stopped after the step limit
    /// with a warning that says so.
    func run(_ argv: [String], log: RunLog, output: Output) -> Int32 {
        run(argv, log: log, output: output, beforeWarning: {})
    }

    /// `beforeWarning`: what has to stop writing to the terminal before the timeout warning (tick's step line).
    private func run(_ argv: [String], log: RunLog, output: Output, beforeWarning: () -> Void) -> Int32 {
        let secs = log.runSeconds ?? log.stepSeconds
        log.append("$ " + argv.joined(separator: " ") + "\n")
        let rc = tl(secs, argv, stdin: .null, stdout: .file(log.raw), stderr: .stdout)
        beforeWarning()
        if rc == 124 {
            log.append("macup: stopped after \(secs / 60) minutes: \(argv.joined(separator: " "))\n")
            output.warn("%s: stopped after %s minutes without finishing (step_timeout_minutes in %s)",
                        argv.first ?? "", String(secs / 60), env.paths.tildify(env.conf))
        }
        return rc
    }

    /// `tick`: `run`, and on a terminal a step line that counts the time and shows the command's latest "==> " phase,
    /// so a long job does not look hung.
    func tick(_ label: String, _ argv: [String], log: RunLog, output: Output) -> Int32 {
        guard isatty(output.fd) == 1, !output.colors.cl.isEmpty else { return run(argv, log: log, output: output) }
        let from = lineCount(log.raw) + 2   // past the "$ cmd" line run writes
        let cols = Int(Bash.substitution(capture(["tput", "cols"]).output)) ?? 80
        let width = max(10, cols - 30)
        let shown = String(String.UnicodeScalarView(label.unicodeScalars.prefix(width)))   // a wrapped line would stay behind on every redraw
        let done = DispatchSemaphore(value: 0)
        let t0 = Date()
        let ticker = Thread { [self] in
            repeat {
                let ph = latestPhase(log.raw, from: from)
                let elapsed = Int(Date().timeIntervalSince(t0))
                let colors = output.colors
                let phase = ph.isEmpty ? "" : " · " + output.i18n.translate(ph)
                output.write(colors.cl + "  " + colors.dim + "… " + shown + phase + " · " + String(elapsed / 60) + ":" + String(format: "%02d", elapsed % 60) + colors.reset)
            } while done.wait(timeout: .now() + 1) == .timedOut
        }
        ticker.start()
        return run(argv, log: log, output: output) {
            done.signal()
            while !ticker.isFinished { usleep(1000) }
        }
    }

    private func lineCount(_ path: String) -> Int {
        guard let contents = FileManager.default.contents(atPath: path) else { return 0 }
        return contents.reduce(0) { $1 == 0x0A ? $0 + 1 : $0 }
    }

    /// The word after the last "==> " at the start of a line, from line `from` on.
    private func latestPhase(_ path: String, from: Int) -> String {
        guard let contents = FileManager.default.contents(atPath: path) else { return "" }
        var phase = ""
        for line in Bash.lines(String(decoding: contents, as: UTF8.self)).dropFirst(max(0, from - 1)) where line.hasPrefix("==> ") {
            phase = String(line.dropFirst(4).unicodeScalars.prefix(while: { ("A"..."Z").contains($0) || ("a"..."z").contains($0) }))
        }
        return phase
    }
}

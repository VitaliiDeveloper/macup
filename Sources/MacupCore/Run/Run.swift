import Darwin
import Foundation

public final class Run {
    public let env: Env
    public let arguments: Arguments
    public let settings: Settings
    public let selection: Selection
    public let shell: Shell
    public let out: Output
    public let log: RunLog
    let report: Report
    let lock: RunLock
    let started: Date
    public let mode: String
    public let previous: String

    public var diskTotal: Int64 = 1
    public var freeBefore: Int64 = 0
    public var memFree = ""
    public var batteryCycles = ""
    public var batteryMax = ""
    public var swap: Int64 = 0
    public var swapMeasured = false
    public var freed: Int64 = 0
    public var didClean = false
    public var potAuto: Int64 = 0
    public var potMore: Int64 = 0
    public var potTrash: Int64 = 0
    public var updated: [String] = []
    public var skipped: [String] = []
    public let candidates = Candidates()
    public let measure: Measure
    public let sudo: SudoKeep
    var reportDone = false
    var quietDescriptor: Int32?

    init(env: Env, arguments: Arguments, settings: Settings, shell: Shell, out: Output, report: Report, lock: RunLock, started: Date, previous: String) {
        self.env = env
        self.arguments = arguments
        self.settings = settings
        selection = Selection(settings)
        self.shell = shell
        self.out = out
        self.report = report
        self.lock = lock
        self.started = started
        self.previous = previous
        log = RunLog(raw: report.raw, stepSeconds: settings.stepSeconds)
        measure = Measure(shell: shell, body: report.body)
        sudo = SudoKeep(shell: shell)
        var mode = arguments.dry ? "check" : !arguments.doUpdate ? "clean" : !arguments.doClean ? "update" : "all"
        if arguments.deep { mode += "+deep" }
        self.mode = mode
    }


    public func task(_ id: String) -> Bool { selection.runs(id) }
    public func taskAllowed(_ id: String) -> Bool { selection.allowed(id) }
    public var updates: Bool { !arguments.dry && arguments.doUpdate }
    public var cleans: Bool { !arguments.dry && arguments.doClean }
    public var wantsUpdates: Bool { arguments.doUpdate || arguments.dry }
    public var wantsCleanup: Bool { arguments.doClean || arguments.dry }

    @discardableResult public func run(_ argv: [String]) -> Int32 { shell.run(argv, log: log, output: out) }

    public func doneUpdate(_ fmt: String, _ args: String...) { updated.append(out.i18n.format(fmt, args: args)) }

    public func versionLine(_ name: String, _ old: String, _ new: String) {
        guard !new.isEmpty else { return }
        if !old.isEmpty, old != new {
            out.ok("%s: %s → %s", name, old, new)
            updated.append("\(name) \(old) → \(new)")
        } else {
            out.ok("%s %s", name, new)
        }
    }

    public func lines(_ text: String) {
        for line in Bash.lines(text) where !line.isEmpty { out.sub(line) }
    }

    public static func count(_ text: String) -> Int {
        Bash.lines(text).filter { !$0.isEmpty }.count
    }

    public func kb(_ path: String) -> Int64 { Size.kb(path, shell: shell) }

    public func kbl(_ paths: String) -> Int64 {
        Bash.lines(paths).filter { !$0.isEmpty && !Run.isSymlink($0) }.reduce(0) { $0 + kb($1) }
    }

    public static func isSymlink(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFLNK
    }

    public static func isDirectory(_ path: String) -> Bool {
        var info = stat()
        return stat(path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFDIR
    }

    public static func date(_ format: String, _ time: time_t = Darwin.time(nil)) -> String {
        var seconds = time
        var parts = tm()
        localtime_r(&seconds, &parts)
        var buffer = [CChar](repeating: 0, count: 64)
        strftime(&buffer, buffer.count, format, &parts)
        return String(cString: buffer)
    }

    var seconds: Int { Int(Date().timeIntervalSince(started)) }

    static func duration(_ seconds: Int) -> String { "\(seconds / 60)m \(seconds % 60)s" }
}

public final class SudoKeep {
    let shell: Shell
    public var asked = false
    private var stopping: DispatchSemaphore?

    init(shell: Shell) { self.shell = shell }

    public func keepAlive() {
        guard stopping == nil else { return }
        let semaphore = DispatchSemaphore(value: 0)
        stopping = semaphore
        let loopShell = Shell(env: shell.env)   // its own environment: the main thread may still add to the run's
        loopShell.signalsToReset = shell.signalsToReset
        Thread { [loopShell] in
            while semaphore.wait(timeout: .now() + 50) == .timedOut {
                if loopShell.tl(0, ["sudo", "-n", "-v"], stdin: .null, stdout: .null, stderr: .null) != 0 { break }
            }
        }.start()
    }

    public func stop() {
        stopping?.signal()
        stopping = nil
        if asked { _ = shell.tl(0, ["sudo", "-k"], stderr: .null) }
        asked = false
    }
}

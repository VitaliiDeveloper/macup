import Darwin
import Foundation

/// Running tools: 2.9's core.sh's `have`, `tl`, `run` and `tick`.
/// Tools are found through PATH (`Env.path`), never at fixed paths, so the tests' fakes win.
/// A tool runs in macup's process group: Ctrl-C and sudo's password prompt reach it.
public final class Shell {
    public let env: Env
    /// The tools' environment (PATH with Homebrew first, LC_CTYPE); a run adds what bash exports on the way.
    public var vars: [String: String]
    /// Signals the run handles through a dispatch source (and so ignores): a tool gets them back at their default.
    public var signalsToReset: [Int32] = []

    public init(env: Env) {
        self.env = env
        vars = env.childVars
    }

    // MARK: finding tools

    /// `command -v`: the first executable file of that name in PATH (an empty entry is the current folder).
    public func which(_ name: String) -> String? {
        if name.contains("/") { return isExecutableFile(name) ? name : nil }
        for dir in (vars["PATH"] ?? "").split(separator: ":", omittingEmptySubsequences: false) {
            let candidate = (dir.isEmpty ? "." : String(dir)) + "/" + name
            if isExecutableFile(candidate) { return candidate }
        }
        return nil
    }

    private func isExecutableFile(_ path: String) -> Bool {
        var st = stat()
        return stat(path, &st) == 0 && (st.st_mode & S_IFMT) == S_IFREG && access(path, X_OK) == 0
    }

    private lazy var cltOK: Bool = {
        let developerDir = Bash.substitution(capture(["xcode-select", "-p"]).output)
        var isDir: ObjCBool = false
        return !developerDir.isEmpty && FileManager.default.fileExists(atPath: developerDir, isDirectory: &isDir) && isDir.boolValue
    }()

    /// `have`: the tool is there. Without the Command Line Tools, /usr/bin/python3, swift, xcrun, xcodebuild and git
    /// are stubs that pop up an install dialog: those count only when the tools are installed.
    public func have(_ name: String) -> Bool {
        guard let path = which(name) else { return false }
        switch path {
        case "/usr/bin/python3", "/usr/bin/pip3", "/usr/bin/swift", "/usr/bin/xcrun", "/usr/bin/xcodebuild", "/usr/bin/git":
            return cltOK
        default:
            return true
        }
    }

    // MARK: starting tools

    public enum Input { case inherit, null, fd(Int32) }
    /// `.stdout` (for stderr): the same descriptor as stdout, like `2>&1`.
    public enum Out { case inherit, null, fd(Int32), file(String), stdout }

    /// Starts a tool in macup's process group; nil when there is no such tool or it cannot start.
    public func spawn(_ argv: [String], stdin: Input = .inherit, stdout: Out = .inherit, stderr: Out = .inherit) -> pid_t? {
        guard let first = argv.first, let path = which(first) else { return nil }
        var fa: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fa)
        defer { posix_spawn_file_actions_destroy(&fa) }
        // POSIX_SPAWN_CLOEXEC_DEFAULT below: only these three reach the tool, so no pipe or report of macup's stays open in it
        switch stdin {
        case .inherit: posix_spawn_file_actions_addinherit_np(&fa, 0)
        case .null: posix_spawn_file_actions_addopen(&fa, 0, "/dev/null", O_RDONLY, 0)
        case .fd(let descriptor): posix_spawn_file_actions_adddup2(&fa, descriptor, 0)
        }
        for (target, out) in [(Int32(1), stdout), (Int32(2), stderr)] {
            switch out {
            case .inherit: posix_spawn_file_actions_addinherit_np(&fa, target)
            case .null: posix_spawn_file_actions_addopen(&fa, target, "/dev/null", O_WRONLY, 0)
            case .fd(let descriptor): posix_spawn_file_actions_adddup2(&fa, descriptor, target)
            case .file(let file): posix_spawn_file_actions_addopen(&fa, target, file, O_WRONLY | O_CREAT | O_APPEND, 0o644)
            case .stdout: if target == 2 { posix_spawn_file_actions_adddup2(&fa, 1, 2) }
            }
        }
        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        var none = sigset_t(), reset = sigset_t()
        sigemptyset(&none)
        sigemptyset(&reset)
        for signal in signalsToReset { sigaddset(&reset, signal) }
        posix_spawnattr_setsigmask(&attr, &none)
        posix_spawnattr_setsigdefault(&attr, &reset)
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_CLOEXEC_DEFAULT))

        let cArgs = argv.map { strdup($0) } + [nil]
        let cEnv = vars.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { (cArgs + cEnv).forEach { free($0) } }
        var pid: pid_t = 0
        let rc = posix_spawn(&pid, path, &fa, &attr, cArgs, cEnv)
        return rc == 0 ? pid : nil
    }

    /// Waits for a tool; its exit status as bash gives it (128 + signal when a signal ended it).
    public static func wait(_ pid: pid_t) -> Int32 {
        let ended = waitForSignal(pid)
        return ended.signal.map { 128 + $0 } ?? ended.status
    }

    /// The exit status, or the signal that ended the tool: the two can share a number.
    static func waitForSignal(_ pid: pid_t) -> (status: Int32, signal: Int32?) {
        var st: Int32 = 0
        while waitpid(pid, &st, 0) < 0 { if errno != EINTR { return (127, nil) } }
        Interrupt.check()
        if st & 0x7F == 0 { return ((st >> 8) & 0xFF, nil) }
        return (128 + (st & 0x7F), st & 0x7F)
    }

    /// A tool's standard output, its standard error dropped (`$(tool 2>/dev/null)`, trailing newlines kept).
    public func capture(_ argv: [String], stdin: Input = .null) -> (status: Int32, output: String) {
        var fds: [Int32] = [0, 0]
        guard pipe(&fds) == 0 else { return (127, "") }
        guard let pid = spawn(argv, stdin: stdin, stdout: .fd(fds[1]), stderr: .null) else {
            close(fds[0]); close(fds[1]); return (127, "")
        }
        close(fds[1])
        let data = FileHandle(fileDescriptor: fds[0], closeOnDealloc: true).readDataToEndOfFile()
        return (Shell.wait(pid), String(decoding: data, as: UTF8.self))
    }

    // MARK: tl

    /// `tl`: runs a tool and stops it after `seconds` (macOS has no `timeout`); 124 when it was stopped.
    /// It stays in the foreground process group, so Ctrl-C and sudo prompts still reach it. When time is up, it and
    /// everything it started (found through `ps`) get SIGTERM, and whatever of them is still there 5 seconds later gets
    /// SIGKILL, before this returns. 127 when the tool is not there.
    public func tl(_ seconds: Int, _ argv: [String], stdin: Input = .inherit, stdout: Out = .inherit, stderr: Out = .inherit) -> Int32 {
        let result = timed(seconds, argv, stdin: stdin, stdout: stdout, stderr: stderr)
        return result.stopped ? 124 : result.status
    }

    func timed(_ seconds: Int, _ argv: [String], stdin: Input, stdout: Out, stderr: Out) -> (status: Int32, signal: Int32?, stopped: Bool) {
        guard let pid = spawn(argv, stdin: stdin, stdout: stdout, stderr: stderr) else {
            notFound(argv, stderr: stderr)
            return (127, nil, false)
        }
        guard seconds > 0 else {
            let ended = Shell.waitForSignal(pid)
            return (ended.status, ended.signal, false)
        }
        let ended = DispatchSemaphore(value: 0), watched = DispatchSemaphore(value: 0)
        let stopped = ManagedFlag()
        Thread { [self] in
            defer { watched.signal() }
            guard ended.wait(timeout: .now() + .seconds(seconds)) == .timedOut else { return }
            stopped.set()
            stop(descendants(of: pid))
        }.start()
        let result = Shell.waitForSignal(pid)
        ended.signal()
        // a child that ignores SIGTERM outlives the tool: it would keep a capture's pipe open, and macup's exit would spare it
        watched.wait()
        return (result.status, result.signal, stopped.isSet)
    }

    /// SIGTERM, then SIGKILL for those still there after `grace` seconds. A process counts as still there while its pid has
    /// the start time it had: a pid that ended and was given to another process by then is left alone.
    func stop(_ pids: [pid_t], grace: TimeInterval = 5) {
        // one macup cannot signal (all root) would only hold up the others
        var alive = pids.compactMap { pid in Shell.startTime(pid).map { (pid: pid, start: $0) } }.filter { kill($0.pid, SIGTERM) == 0 }
        let deadline = DispatchTime.now() + grace
        while !alive.isEmpty, DispatchTime.now() < deadline {
            usleep(50_000)
            alive = alive.filter { Shell.startTime($0.pid) == $0.start }
        }
        alive.forEach { kill($0.pid, SIGKILL) }
    }

    /// When the process started, in microseconds; nil when there is none. sysctl answers for any process: proc_pidinfo
    /// refuses a setuid one such as sudo, which still takes macup's signals and passes them on.
    static func startTime(_ pid: pid_t) -> UInt64? {
        var info = kinfo_proc(), size = MemoryLayout<kinfo_proc>.size
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&name, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let started = info.kp_proc.p_un.__p_starttime
        return UInt64(started.tv_sec) * 1_000_000 + UInt64(started.tv_usec)
    }

    /// The process and every process below it, from `ps -Ao pid=,ppid=` (as 2.9's core.sh's tl finds them).
    func descendants(of root: pid_t) -> [pid_t] {
        var parent: [pid_t: pid_t] = [:]
        for line in Bash.lines(capture(["ps", "-Ao", "pid=,ppid="]).output) {
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            if fields.count >= 2, let pid = pid_t(fields[0]), let parentPID = pid_t(fields[1]) { parent[pid] = parentPID }
        }
        var out: [pid_t] = []
        for process in parent.keys {
            var ancestor = process
            while let parentPID = parent[ancestor], ancestor != root, ancestor > 1 { ancestor = parentPID }
            if ancestor == root, process != root { out.append(process) }
        }
        return out + [root]
    }

    // MARK: sudo

    /// `sudo -n true`: a password is cached, so sudo would not ask.
    public var sudoCached: Bool { tl(0, ["sudo", "-n", "true"], stderr: .null) == 0 }

    /// `sudo -v -p prompt`: asks for the Mac password on the terminal; false when it was not given.
    public func askSudo(_ prompt: String) -> Bool { tl(0, ["sudo", "-v", "-p", prompt]) == 0 }

    /// `sudo -k`: forgets the cached password.
    public func forgetSudo(errors: Out = .null) { _ = tl(0, ["sudo", "-k"], stderr: errors) }

    private func notFound(_ argv: [String], stderr: Out) {
        let msg = "macup: \(argv.first ?? ""): command not found\n"
        switch stderr {
        case .inherit, .stdout: Shell.writeText(msg, to: 2)
        case .null: break
        case .fd(let descriptor): Shell.writeText(msg, to: descriptor)
        case .file(let file):
            let descriptor = open(file, O_WRONLY | O_CREAT | O_APPEND, 0o644)
            if descriptor >= 0 { Shell.writeText(msg, to: descriptor); close(descriptor) }
        }
    }

    /// One write(2) of the text, as far as its first NUL byte.
    static func writeText(_ text: String, to fd: Int32) {
        _ = text.withCString { write(fd, $0, strlen($0)) }
    }
}

/// A flag one thread sets and another reads.
final class ManagedFlag {
    private var value = false
    private let lock = NSLock()
    func set() { lock.lock(); value = true; lock.unlock() }
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
}

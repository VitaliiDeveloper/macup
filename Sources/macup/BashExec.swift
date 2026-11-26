import Darwin
import Foundation

/// Hands the invocation to the bash build: `exec /bin/bash /dev/fd/N args…` on the script written to an unlinked file.
/// execve, not a child process, so macup keeps its pid (the lock, the watchdogs, the suite's kill), its terminal and its
/// exit status; nothing is left in the temp folder.
enum BashExec {
    static func run() -> Never {
        let fd = scriptDescriptor()
        setenv("MACUP_SELF", selfPath(), 1)
        // the arguments as the C strings macup got: a Swift String would replace bytes that are not UTF-8
        var cArgs: [UnsafeMutablePointer<CChar>?] = [strdup("/bin/bash"), strdup("/dev/fd/\(fd)")]
        for i in 1..<Int(CommandLine.argc) { cArgs.append(CommandLine.unsafeArgv[i]) }
        cArgs.append(nil)
        execv("/bin/bash", cArgs)
        fail("cannot run /bin/bash: \(String(cString: strerror(errno)))")
    }

    /// The script on a descriptor of its own, 10 or above: the script itself uses 3 and 4.
    private static func scriptDescriptor() -> Int32 {
        // /tmp when TMPDIR cannot take it: the bash build runs its one-off commands without a temp folder
        let dirs = [ProcessInfo.processInfo.environment["TMPDIR"].flatMap { $0.isEmpty ? nil : $0 }, "/tmp"].compactMap { $0 }
        var template: [CChar] = []
        var w: Int32 = -1
        for d in dirs where w < 0 {
            template = Array("\(d)/macup.XXXXXX".utf8CString)
            w = mkstemp(&template)
        }
        guard w >= 0 else { fail("cannot write a temporary file in \(dirs.joined(separator: " or ")): \(String(cString: strerror(errno)))") }
        let path = String(cString: template)
        defer { unlink(path) }
        let data = Array(LegacyScript.text.utf8)
        var off = 0
        while off < data.count {
            let n = data.withUnsafeBytes { write(w, $0.baseAddress! + off, $0.count - off) }
            if n < 0 { if errno == EINTR { continue }; fail("cannot write \(path): \(String(cString: strerror(errno)))") }
            off += n
        }
        close(w)
        let r = open(path, O_RDONLY)
        guard r >= 0 else { fail("cannot read \(path): \(String(cString: strerror(errno)))") }
        let fd = fcntl(r, F_DUPFD, 10)
        guard fd >= 0 else { fail("no descriptor for the script: \(String(cString: strerror(errno)))") }
        close(r)
        return fd
    }

    /// The path this binary was started by, as the bash build's $0 was: the path the shell found in PATH, a symlink kept as
    /// a symlink (Homebrew's bin/macup, which a schedule must keep pointing at). Not resolved to the real file.
    /// A binary in a checkout's .build is the build output, like ./macup there: it is named as ./macup, so uninstall leaves it.
    static func selfPath() -> String {
        var size: UInt32 = 0
        _NSGetExecutablePath(nil, &size)
        var buf = [CChar](repeating: 0, count: Int(size) + 1)
        guard _NSGetExecutablePath(&buf, &size) == 0 else { return CommandLine.arguments[0] }
        let path = String(cString: buf)
        if let r = path.range(of: "/.build/", options: .backwards) {
            let checkout = String(path[..<r.lowerBound])
            let fm = FileManager.default
            if fm.fileExists(atPath: checkout + "/build.sh"), fm.fileExists(atPath: checkout + "/src") { return checkout + "/macup" }
        }
        return path
    }

    private static func fail(_ msg: String) -> Never {
        FileHandle.standardError.write(Data("macup: \(msg)\n".utf8))
        exit(1)
    }
}

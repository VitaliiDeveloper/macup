import Darwin
import Foundation
import MacupCore

/// Hands the invocation to the bash build: `exec /bin/bash /dev/fd/N args…` on the script written to an unlinked file.
/// execve, not a child process, so macup keeps its pid (the lock, the watchdogs, the suite's kill), its terminal and its
/// exit status; nothing is left in the temp folder.
enum BashExec {
    static func run(prepending words: [String] = []) -> Never {
        let fd = scriptDescriptor()
        setenv("MACUP_SELF", SelfPath.current(), 1)
        // the arguments as the C strings macup got: a Swift String would replace bytes that are not UTF-8
        var cArgs: [UnsafeMutablePointer<CChar>?] = [strdup("/bin/bash"), strdup("/dev/fd/\(fd)")] + words.map { strdup($0) }
        for index in 1..<Int(CommandLine.argc) { cArgs.append(CommandLine.unsafeArgv[index]) }
        cArgs.append(nil)
        execv("/bin/bash", cArgs)
        fail("cannot run /bin/bash: \(String(cString: strerror(errno)))")
    }

    /// The script on a descriptor of its own, 10 or above: the script itself uses 3 and 4.
    private static func scriptDescriptor() -> Int32 {
        // /tmp when TMPDIR cannot take it: the bash build runs its one-off commands without a temp folder
        let dirs = [Env.nonEmpty(ProcessInfo.processInfo.environment, "TMPDIR"), "/tmp"].compactMap { $0 }
        var template: [CChar] = []
        var writeDescriptor: Int32 = -1
        for dir in dirs where writeDescriptor < 0 {
            template = Array("\(dir)/macup.XXXXXX".utf8CString)
            writeDescriptor = mkstemp(&template)
        }
        guard writeDescriptor >= 0 else { fail("cannot write a temporary file in \(dirs.joined(separator: " or ")): \(String(cString: strerror(errno)))") }
        let path = String(cString: template)
        defer { unlink(path) }
        let data = Array(LegacyScript.text.utf8)
        var off = 0
        while off < data.count {
            let written = data.withUnsafeBytes { write(writeDescriptor, $0.baseAddress! + off, $0.count - off) }
            if written < 0 { if errno == EINTR { continue }; fail("cannot write \(path): \(String(cString: strerror(errno)))") }
            off += written
        }
        close(writeDescriptor)
        let readDescriptor = open(path, O_RDONLY)
        guard readDescriptor >= 0 else { fail("cannot read \(path): \(String(cString: strerror(errno)))") }
        let fd = fcntl(readDescriptor, F_DUPFD, 10)
        guard fd >= 0 else { fail("no descriptor for the script: \(String(cString: strerror(errno)))") }
        close(readDescriptor)
        return fd
    }

    private static func fail(_ msg: String) -> Never {
        FileHandle.standardError.write(Data("macup: \(msg)\n".utf8))
        exit(1)
    }
}

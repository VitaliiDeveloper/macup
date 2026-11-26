import Darwin
import Foundation

/// One run at a time: the lock of arguments.sh, a folder with a pid file. A 2.9 run and a 3.0 run use the same one,
/// so a scheduled check of either version and a run of the other still exclude each other.
public struct RunLock {
    public let dir: String
    /// False when the pid could not be written: the run goes on without a lock, as the bash build does.
    public let held: Bool

    public enum Result {
        case acquired(RunLock)
        /// Another macup holds it: its pid as the file has it.
        case busy(pid: String)
    }

    /// Takes the lock in `stateDir`/lock; a lock whose pid no longer runs was left by a run that was killed and is taken over.
    public static func acquire(stateDir: String, pid: pid_t = getpid()) -> Result {
        let dir = stateDir + "/lock"
        if mkdir(dir, 0o777) != 0 {
            let other = Bash.substitution(String(decoding: FileManager.default.contents(atPath: dir + "/pid") ?? Data(), as: UTF8.self))
            if !other.isEmpty, alive(other) { return .busy(pid: other) }
            try? FileManager.default.removeItem(atPath: dir)
            mkdir(dir, 0o777)
        }
        let held = (try? "\(pid)\n".write(toFile: dir + "/pid", atomically: false, encoding: .utf8)) != nil
        return .acquired(RunLock(dir: dir, held: held))
    }

    /// `kill -0 pid`: the process exists and macup may signal it (another user's process does not count).
    static func alive(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: CharacterSet(charactersIn: " \t\n"))
        guard let p = Int32(t) else { return false }
        return kill(p, 0) == 0
    }

    /// `unlock`.
    public func release() {
        guard held else { return }
        try? FileManager.default.removeItem(atPath: dir)
    }
}

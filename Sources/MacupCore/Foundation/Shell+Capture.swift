import Darwin
import Foundation

public extension Shell {
    /// `$(tl seconds tool…)`: what the tool wrote to stdout, and to stderr with `errorsToo` (a missing tool's "command not
    /// found" too, as with 2>&1), and its status (124 when it was stopped, 127 when it is not there); `input`, when given, is
    /// what it reads. Once a timed tool has ended, what it wrote is taken 5 seconds later at most: something it left
    /// running in the background may hold the pipe open for good.
    func timedCapture(_ seconds: Int, _ argv: [String], stdin: Input = .inherit, stderr: Out = .null, errorsToo: Bool = false,
                      input: String? = nil) -> (status: Int32, data: Data) {
        var output: [Int32] = [0, 0], feed: [Int32] = [-1, -1]
        guard pipe(&output) == 0 else { return (127, Data()) }
        var source = stdin
        if let input {
            guard pipe(&feed) == 0 else { close(output[0]); close(output[1]); return (127, Data()) }
            source = .fd(feed[0])
            _ = fcntl(feed[1], F_SETNOSIGPIPE, 1)   // a tool that ends without reading all of it must not take macup along
            let writer = feed[1]
            Thread { Shell.writeText(input, to: writer); close(writer) }.start()
        }
        let drain = Drain(output[0])
        let status = tl(seconds, argv, stdin: source, stdout: .fd(output[1]), stderr: errorsToo ? .fd(output[1]) : stderr)
        close(output[1])
        if feed[0] >= 0 { close(feed[0]) }
        return (status, drain.data(waiting: seconds > 0 ? 5 : nil))
    }
}

/// Reads a pipe to its end on a thread of its own while the tool runs: a full pipe would stop the tool before it ends.
final class Drain {
    private var bytes = Data()
    private let lock = NSLock(), done = DispatchSemaphore(value: 0)

    init(_ descriptor: Int32) {
        Thread { [self] in
            var buffer = [UInt8](repeating: 0, count: 65_536)
            while true {
                let count = read(descriptor, &buffer, buffer.count)
                if count > 0 {
                    lock.lock()
                    bytes.append(contentsOf: buffer[0..<count])
                    lock.unlock()
                } else if count < 0, errno == EINTR {
                    continue
                } else {
                    break
                }
            }
            close(descriptor)
            done.signal()
        }.start()
    }

    /// Everything, once the pipe is closed; with `seconds`, what came by then if it is still open.
    func data(waiting seconds: Int?) -> Data {
        if let seconds { _ = done.wait(timeout: .now() + .seconds(seconds)) } else { done.wait() }
        lock.lock()
        defer { lock.unlock() }
        return bytes
    }
}

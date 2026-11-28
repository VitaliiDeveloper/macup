import Darwin
import Foundation

/// Like bash's trap, the run reacts only after the tool in the foreground has returned.
public enum Interrupt {
    public static let signals = [SIGINT, SIGTERM, SIGHUP]
    private static let noted = ManagedFlag(), piped = ManagedFlag()
    private static var sources: [DispatchSourceSignal] = []
    private static var action: (() -> Never)?
    private static var pipeAction: (() -> Never)?

    /// `pipeClosed`: what ends the run when its output has no reader any more (`macup check | head -1`).
    public static func install(_ handler: @escaping () -> Never, pipeClosed: (() -> Never)? = nil, shell: Shell) {
        action = handler
        // like bash, a signal ignored when macup started (nohup, a background job) stays ignored, for its tools too
        let handled = (signals + (pipeClosed == nil ? [] : [SIGPIPE])).filter { number in
            var current = sigaction()
            return sigaction(number, nil, &current) == 0
                && unsafeBitCast(current.__sigaction_u.__sa_handler, to: Int.self) != unsafeBitCast(SIG_IGN, to: Int.self)
        }
        shell.signalsToReset = handled
        for number in handled {
            signal(number, SIG_IGN)   // a dispatch source only sees a signal that does not kill the process first
            if number == SIGPIPE {
                pipeAction = pipeClosed   // the write fails with EPIPE instead, and Output.write says so
                continue
            }
            let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
            source.setEventHandler { noted.set() }
            source.resume()
            sources.append(source)
        }
    }

    /// A write to the run's output found no reader.
    static func pipeClosed() {
        piped.set()
        check()
    }

    static func check() {
        guard Thread.isMainThread else { return }
        if piped.isSet, let handler = pipeAction {
            pipeAction = nil
            action = nil
            handler()
        }
        guard noted.isSet, let handler = action else { return }
        action = nil
        handler()
    }
}

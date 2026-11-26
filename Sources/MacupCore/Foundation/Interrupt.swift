import Darwin
import Foundation

/// Like bash's trap, the run reacts only after the tool in the foreground has returned.
public enum Interrupt {
    public static let signals = [SIGINT, SIGTERM, SIGHUP]
    private static let noted = ManagedFlag()
    private static var sources: [DispatchSourceSignal] = []
    private static var action: (() -> Never)?

    public static func install(_ handler: @escaping () -> Never, shell: Shell) {
        action = handler
        shell.signalsToReset = signals
        for number in signals {
            signal(number, SIG_IGN)   // a dispatch source only sees a signal that does not kill the process first
            let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
            source.setEventHandler { noted.set() }
            source.resume()
            sources.append(source)
        }
    }

    static func check() {
        guard Thread.isMainThread, noted.isSet, let handler = action else { return }
        action = nil
        handler()
    }
}

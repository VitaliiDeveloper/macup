import Darwin

/// 2.9's core.sh's `ask`: the question goes to /dev/tty and the answer comes from there, so it works under `curl | bash`.
enum Terminal {
    static var available: Bool {
        let descriptor = Darwin.open("/dev/tty", O_RDONLY)
        guard descriptor >= 0 else { return false }
        close(descriptor)
        return true
    }

    /// The line typed, as `read -r` and `echo` hand it on: blanks at both ends gone. "" without a terminal.
    /// A run ignores SIGINT for its dispatch source, so the wait looks at the interrupt itself: Ctrl-C at a question ends the
    /// run, as bash's trap does once the question's subshell is gone. The terminal is read without blocking (poll() cannot
    /// wait on /dev/tty on macOS: it answers POLLNVAL at once).
    static func ask(_ prompt: String) -> String {
        say(prompt)
        let reader = Darwin.open("/dev/tty", O_RDONLY | O_NONBLOCK)
        guard reader >= 0 else { return "" }
        defer { close(reader) }
        var bytes: [UInt8] = [], byte: UInt8 = 0
        while true {
            Interrupt.check()
            let count = read(reader, &byte, 1)
            if count < 0, errno == EAGAIN || errno == EINTR {
                usleep(50_000)
                continue
            }
            if count != 1 || byte == 0x0A { break }
            if byte != 0 { bytes.append(byte) }
        }
        let blanks: Set<UInt8> = [0x20, 0x09, 0x0A]
        let trimmed = bytes.drop(while: blanks.contains).reversed().drop(while: blanks.contains).reversed()
        return Bash.substitution(Bash.echo(String(decoding: Array(trimmed), as: UTF8.self)))
    }

    /// `printf '%s' "$text" >/dev/tty`.
    static func say(_ text: String) {
        let writer = Darwin.open("/dev/tty", O_WRONLY)
        guard writer >= 0 else { return }
        Shell.writeText(text, to: writer)
        close(writer)
    }

    static func isYes(_ answer: String) -> Bool { ["y", "Y", "т", "Т", "д", "Д"].contains(answer) }
}

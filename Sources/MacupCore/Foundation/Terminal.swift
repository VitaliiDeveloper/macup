import Darwin

/// core.sh's `ask`: the question goes to /dev/tty and the answer comes from there, so it works under `curl | bash`.
enum Terminal {
    static var available: Bool {
        let descriptor = Darwin.open("/dev/tty", O_RDONLY)
        guard descriptor >= 0 else { return false }
        close(descriptor)
        return true
    }

    /// The line typed, as `read -r` and `echo` hand it on: blanks at both ends gone. "" without a terminal.
    static func ask(_ prompt: String) -> String {
        let writer = Darwin.open("/dev/tty", O_WRONLY)
        if writer >= 0 { Shell.writeText(prompt, to: writer); close(writer) }
        let reader = Darwin.open("/dev/tty", O_RDONLY)
        guard reader >= 0 else { return "" }
        defer { close(reader) }
        var bytes: [UInt8] = [], byte: UInt8 = 0
        while true {
            let count = read(reader, &byte, 1)
            if count < 0, errno == EINTR { continue }
            if count != 1 || byte == 0x0A { break }
            if byte != 0 { bytes.append(byte) }
        }
        let blanks: Set<UInt8> = [0x20, 0x09, 0x0A]
        let trimmed = bytes.drop(while: blanks.contains).reversed().drop(while: blanks.contains).reversed()
        return Bash.substitution(Bash.echo(String(decoding: Array(trimmed), as: UTF8.self)))
    }

    static func isYes(_ answer: String) -> Bool { ["y", "Y", "т", "Т", "д", "Д"].contains(answer) }
}

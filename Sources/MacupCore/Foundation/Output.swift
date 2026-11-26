import Darwin
import Foundation

/// The colours of core.sh: on a terminal without NO_COLOR, off with --no-color (and --json for a run).
public struct Colors: Equatable {
    public var bold = "", green = "", yellow = "", red = "", cyan = "", dim = "", reset = "", cl = ""

    public static let off = Colors()
    public static let on = Colors(bold: "\u{1B}[1m", green: "\u{1B}[32m", yellow: "\u{1B}[33m", red: "\u{1B}[31m", cyan: "\u{1B}[36m",
                                  dim: "\u{1B}[2m", reset: "\u{1B}[0m", cl: "\r\u{1B}[K")

    /// What core.sh starts with: colours when stdout is a terminal and NO_COLOR is not set.
    public static func initial(env: Env, fd: Int32 = 1) -> Colors {
        isatty(fd) == 1 && !env.noColor ? .on : .off
    }
}

/// One line of a run for --json: its section, kind (ok, info, warn, fail), text and the lines under it.
public struct Item: Equatable {
    public var section: String
    public var kind: String
    public var text: String
    public var details: [String] = []
}

/// The lines of a run: core.sh's `ok`, `info`, `warn`, `fail`, `err`, `sub`, `mdonly`, `step`, `section`, `md`, `detail`.
/// Each goes to the terminal, to the report (markdown) and, with --json, to the items.
public final class Output {
    public var colors: Colors
    public let i18n: I18n
    /// Where the terminal lines go (a run with --quiet points it at /dev/null).
    public var fd: Int32
    /// The report being written (core.sh's $BODY); nil before a run has one, and md then writes nothing.
    public var body: FileHandle?
    public var json = false

    public private(set) var items: [Item] = []
    public private(set) var warnings: [String] = []
    public private(set) var errors = 0
    /// The section whose header is printed with its first line: a section with nothing to say stays hidden.
    public private(set) var pending = ""
    public private(set) var section = ""

    public init(i18n: I18n, colors: Colors, fd: Int32 = 1) {
        self.i18n = i18n
        self.colors = colors
        self.fd = fd
    }

    public func write(_ text: String) {
        var rest = Data(text.utf8)
        while !rest.isEmpty {
            let written = rest.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
            if written < 0 { if errno == EINTR { continue }; return }
            rest.removeFirst(written)
        }
    }

    public func md(_ text: String) {
        try? body?.write(contentsOf: Data((text + "\n").utf8))   // a report that cannot be written does not stop the run
    }

    public func beginSection(_ en: String) {
        pending = i18n.translate(en)
        section = pending
    }

    func flush() {
        guard !pending.isEmpty else { return }
        write("\(colors.cl)\n\(colors.bold)\(colors.cyan)▸ \(pending)\(colors.reset)\n")
        md(""); md("## \(pending)"); md("")
        pending = ""
    }

    /// The message as `m=$(_f "$@")` has it: translated, formatted, trailing newlines gone.
    private func message(_ fmt: String, _ args: [String]) -> String {
        Bash.substitution(i18n.format(fmt, args: args))
    }

    public func ok(_ fmt: String, _ args: String...) { ok(fmt, args: args) }
    public func info(_ fmt: String, _ args: String...) { info(fmt, args: args) }
    public func warn(_ fmt: String, _ args: String...) { warn(fmt, args: args) }
    public func fail(_ fmt: String, _ args: String...) { fail(fmt, args: args) }
    /// A step that did not do its job: the run ends with exit status 3.
    public func err(_ fmt: String, _ args: String...) { err(fmt, args: args) }

    public func ok(_ fmt: String, args: [String]) { emit("ok", "✓", colors.green, "✅ ", fmt, args) }
    public func info(_ fmt: String, args: [String]) { emit("info", "·", colors.dim, "", fmt, args) }
    public func warn(_ fmt: String, args: [String]) { emit("warn", "!", colors.yellow, "⚠️ ", fmt, args) }
    public func fail(_ fmt: String, args: [String]) { emit("fail", "✗", colors.red, "❌ ", fmt, args) }

    /// One line on the terminal, in the report and, with --json, in the items; warn and fail also count as warnings.
    private func emit(_ kind: String, _ mark: String, _ color: String, _ badge: String, _ fmt: String, _ args: [String]) {
        let text = message(fmt, args)
        flush()
        write("\(colors.cl)  \(color)\(mark)\(colors.reset) \(text)\n")
        md("- \(badge)\(text)")
        if kind == "warn" || kind == "fail" { warnings.append(text) }
        if json { items.append(Item(section: section, kind: kind, text: text)) }
    }

    public func err(_ fmt: String, args: [String]) {
        fail(fmt, args: args)
        errors += 1
    }

    /// A line under the last one, as it is (not translated).
    public func sub(_ text: String) {
        flush()
        write("      \(colors.dim)\(text)\(colors.reset)\n")
        mdonly(text)
    }

    /// A line under the last one in the report and --json only.
    public func mdonly(_ text: String) {
        md("    - \(text)"); detail(text)
    }

    /// With --json, a line under the last item.
    /// The bash build keeps details in a file of "item<TAB>text" lines: only the first line of a detail survives, an empty one none.
    public func detail(_ text: String) {
        guard json, !items.isEmpty, body != nil, let first = Bash.lines(text).first, !first.isEmpty else { return }
        items[items.count - 1].details.append(first)
    }

    /// The transient "… doing this" line, only on a terminal with colours.
    public func step(_ fmt: String, _ args: String...) {
        guard isatty(fd) == 1, !colors.cl.isEmpty else { return }
        write("\(colors.cl)  \(colors.dim)… \(message(fmt, args))\(colors.reset)")
    }
}

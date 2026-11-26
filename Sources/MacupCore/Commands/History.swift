import Foundation

/// `macup history` and `macup history --json` (commands.sh `show_history`, `history_json`): history.csv as awk -F, reads it.
enum History {
    static func text(_ context: OneOff.Context) -> String {
        let i18n = context.i18n, colors = context.colors
        guard let records = records(context.env.history) else {
            return i18n.translate("No history yet. Every run adds a line; run: macup check") + "\n"
        }
        var out = "\(colors.bold)\(i18n.translate("Last runs"))\(colors.reset)  (\(context.env.paths.tildify(context.env.history)))\n\n"
        let headers = [("DATE", 18), ("MODE", 11), ("FREE", 11), ("CHANGE", 11), ("SWAP", 10), ("BATTERY", 9), ("UPDATED", 9), ("FREED", 10)]
        out += colors.bold + headers.map { Text.pad(i18n.translate($0.0), $0.1) }.joined() + i18n.translate("WARN") + colors.reset + "\n"
        let shown = records.suffix(15).map(fields)
        for (index, field) in shown.enumerated() {
            let change = index > 0 ? Size.hum("\(Awk.number(field[2]) - Awk.number(shown[index - 1][2]))") : ""
            let battery = field[7].isEmpty ? "-" : field[7] + "%"
            let columns = [(field[0], 18), (field[1], 11), (hum(field[2]), 11), (change, 11), (field[5] + " MB", 10),
                           (battery, 9), (field[8], 9), (hum(field[9]), 10)]
            out += columns.map { awkPad($0.0, $0.1) }.joined() + field[10] + "\n"
        }
        guard shown.count >= 2 else { return out }
        let free = shown.map { $0[2] }
        var low = free[0], high = free[0]
        for value in free {
            if awkLess(value, low) { low = value }
            if awkLess(high, value) { high = value }
        }
        let bars = ["▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]
        let flat = !awkLess(low, high) && !awkLess(high, low)
        let line = free.map { value -> String in
            let level = flat ? 4 : Awk.int((Awk.number(value) - Awk.number(low)) / (Awk.number(high) - Awk.number(low)) * 7) &+ 1
            return (1...8).contains(level) ? bars[Int(level) - 1] : ""
        }.joined()
        // awk's h() sets a global b, the same name the bold colour came in as: the line starts with the last FREED in bytes
        let freed = shown[shown.count - 1][9]
        let clobbered = awkString((Awk.lessThanZero(freed) ? -Awk.number(freed) : Awk.number(freed)) * 1024)
        let trend = Awk.unescape(i18n.translate("Free space trend:"))
        out += "\n\(clobbered)\(trend)\(colors.reset) \(line)  (\(hum(low)) … \(hum(high)))\n"
        return out
    }

    static func json(_ context: OneOff.Context) -> String {
        guard let records = records(context.env.history) else { return "{\"schema\":1,\"runs\":[]}\n" }
        func number(_ value: String) -> String { value.isEmpty ? "null" : awkString(Awk.number(value) + 0) }
        let runs = records.map(fields).map { field in
            "{\"date\":\"\(field[0])\",\"mode\":\"\(field[1])\",\"free_kb\":\(number(field[2])),\"total_kb\":\(number(field[3]))," +
                "\"memory_free_pct\":\(number(field[4])),\"swap_mb\":\(number(field[5])),\"battery_cycles\":\(number(field[6]))," +
                "\"battery_max_pct\":\(number(field[7])),\"updated\":\(number(field[8])),\"freed_kb\":\(number(field[9])),\"warnings\":\(number(field[10]))}"
        }
        return "{\"schema\":1,\"runs\":[" + runs.joined(separator: ",") + "]}\n"
    }

    /// nil where `[ -s ]` is false.
    private static func records(_ path: String) -> [String]? {
        var info = stat()
        guard stat(path, &info) == 0, info.st_size > 0, let data = FileManager.default.contents(atPath: path) else { return nil }
        return Files.records(data).map { String(decoding: $0, as: UTF8.self) }
    }

    private static func fields(_ record: String) -> [String] {
        var parts = record.isEmpty ? [] : record.unicodeScalars.split(separator: ",", omittingEmptySubsequences: false).map { String(String.UnicodeScalarView($0)) }
        while parts.count < 11 { parts.append("") }
        return parts
    }

    /// awk's h() of a field: like `hum`, but an empty field is below "0" as a string, so it is "-0 KB".
    private static func hum(_ field: String) -> String { field.isEmpty ? "-" + Size.hum("0") : Size.hum(field) }

    /// awk's `%-Ns`: macOS awk counts bytes and never adds a space beyond the width.
    private static func awkPad(_ text: String, _ width: Int) -> String {
        text + String(repeating: " ", count: max(0, width - text.utf8.count))
    }

    /// awk's `<` between two fields: numbers when both look like numbers, otherwise strings.
    private static func awkLess(_ left: String, _ right: String) -> Bool {
        if Awk.isNumber(left), Awk.isNumber(right) { return Awk.number(left) < Awk.number(right) }
        return strcmp(left, right) < 0
    }

    /// A number as awk prints it with %s: a whole number with %.30g, the rest with CONVFMT (%.6g).
    static func awkString(_ value: Double) -> String {
        var whole = 0.0
        return Awk.format(modf(value, &whole) == 0 ? "%.30g" : "%.6g", value)
    }
}

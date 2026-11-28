import Foundation

/// JSON as 2.9's inline Python read it with its json module: an object keeps its keys in the order of the document
/// (npm's outdated list is installed in that order), a repeated key keeps its first place and its last value.
enum JSONValue {
    case string(String), number(String), bool(Bool), null
    case array([JSONValue])
    case object([(key: String, value: JSONValue)])

    /// nil where Python's json.loads raises.
    static func parse(_ data: Data) -> JSONValue? {
        guard !data.starts(with: [0xEF, 0xBB, 0xBF]), let text = String(data: data, encoding: .utf8) else { return nil }   // Python refuses a BOM
        var reader = Reader(scalars: Array(text.unicodeScalars))
        guard let value = reader.value() else { return nil }
        reader.skipBlanks()
        return reader.index == reader.scalars.count ? value : nil
    }

    static func parse(file path: String) -> JSONValue? {
        FileManager.default.contents(atPath: path).flatMap(parse)
    }

    subscript(key: String) -> JSONValue? {
        guard case .object(let entries) = self else { return nil }
        return entries.first { $0.key.unicodeScalars.elementsEqual(key.unicodeScalars) }?.value
    }

    var string: String? {
        if case .string(let text) = self { return text }
        return nil
    }

    /// Python's truth test: an empty string, 0, false, null and an empty list or object are false.
    var isTruthy: Bool {
        switch self {
        case .string(let text): return !text.isEmpty
        case .number(let text): return (Double(text) ?? 0) != 0
        case .bool(let value): return value
        case .null: return false
        case .array(let items): return !items.isEmpty
        case .object(let entries): return !entries.isEmpty
        }
    }

    /// Python's str() of a scalar value.
    var pythonString: String {
        switch self {
        case .string(let text): return text
        case .number(let text):
            guard text.contains(where: { $0 == "." || $0 == "e" || $0 == "E" }), let value = Double(text) else { return text }
            return value == value.rounded() && abs(value) < 1e16 ? String(format: "%.1f", value) : "\(value)"
        case .bool(let value): return value ? "True" : "False"
        case .null: return "None"
        case .array, .object: return ""
        }
    }

    private struct Reader {
        let scalars: [Unicode.Scalar]
        var index = 0
        /// Python gives up on nesting deeper than its recursion limit; deeper still would overflow the stack here.
        var depth = 0

        mutating func skipBlanks() {
            while index < scalars.count, [" ", "\t", "\n", "\r"].contains(scalars[index]) { index += 1 }
        }

        mutating func value() -> JSONValue? {
            skipBlanks()
            guard index < scalars.count, depth < 990 else { return nil }
            switch scalars[index] {
            case "{": return object()
            case "[": return array()
            case "\"": return string().map(JSONValue.string)
            case "t": return word("true", .bool(true))
            case "f": return word("false", .bool(false))
            case "n": return word("null", .null)
            case "N": return word("NaN", .number("nan"))
            case "I": return word("Infinity", .number("inf"))
            default: return number()
            }
        }

        private mutating func word(_ text: String, _ value: JSONValue) -> JSONValue? {
            let wanted = Array(text.unicodeScalars)
            guard index + wanted.count <= scalars.count, Array(scalars[index..<index + wanted.count]) == wanted else { return nil }
            index += wanted.count
            return value
        }

        private mutating func number() -> JSONValue? {
            let start = index
            if index < scalars.count, scalars[index] == "-" {
                index += 1
                if index < scalars.count, scalars[index] == "I" { return word("Infinity", .number("-inf")) }
            }
            func digits() -> Int {
                let from = index
                while index < scalars.count, ("0"..."9").contains(scalars[index]) { index += 1 }
                return index - from
            }
            let whole = digits()
            guard whole > 0, !(whole > 1 && scalars[index - whole] == "0") else { return nil }
            if index < scalars.count, scalars[index] == "." {
                index += 1
                guard digits() > 0 else { return nil }
            }
            if index < scalars.count, scalars[index] == "e" || scalars[index] == "E" {
                index += 1
                if index < scalars.count, scalars[index] == "+" || scalars[index] == "-" { index += 1 }
                guard digits() > 0 else { return nil }
            }
            return .number(String(String.UnicodeScalarView(scalars[start..<index])))
        }

        private mutating func string() -> String? {
            index += 1
            var out = String.UnicodeScalarView()
            while index < scalars.count {
                let scalar = scalars[index]
                index += 1
                switch scalar {
                case "\"": return String(out)
                case "\\":
                    guard index < scalars.count else { return nil }
                    let escaped = scalars[index]
                    index += 1
                    let simple: [Unicode.Scalar: Unicode.Scalar] = ["\"": "\"", "\\": "\\", "/": "/", "b": "\u{8}", "f": "\u{C}", "n": "\n", "r": "\r", "t": "\t"]
                    if let replacement = simple[escaped] { out.append(replacement); continue }
                    guard escaped == "u", var code = hex() else { return nil }
                    if (0xD800..<0xDC00).contains(code), index + 1 < scalars.count, scalars[index] == "\\", scalars[index + 1] == "u" {
                        let saved = index
                        index += 2
                        if let low = hex(), (0xDC00..<0xE000).contains(low) { code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00) } else { index = saved }
                    }
                    out.append(Unicode.Scalar(code) ?? "\u{FFFD}")
                default:
                    guard scalar.value >= 0x20 else { return nil }
                    out.append(scalar)
                }
            }
            return nil
        }

        private mutating func hex() -> UInt32? {
            guard index + 4 <= scalars.count, scalars[index..<index + 4].allSatisfy({ $0.properties.isASCIIHexDigit }),
                  let code = UInt32(String(String.UnicodeScalarView(scalars[index..<index + 4])), radix: 16) else { return nil }
            index += 4
            return code
        }

        private mutating func array() -> JSONValue? {
            index += 1
            depth += 1
            defer { depth -= 1 }
            var items: [JSONValue] = []
            skipBlanks()
            if index < scalars.count, scalars[index] == "]" { index += 1; return .array(items) }
            while true {
                guard let item = value() else { return nil }
                items.append(item)
                skipBlanks()
                guard index < scalars.count else { return nil }
                index += 1
                if scalars[index - 1] == "]" { return .array(items) }
                guard scalars[index - 1] == "," else { return nil }
            }
        }

        private mutating func object() -> JSONValue? {
            index += 1
            depth += 1
            defer { depth -= 1 }
            var entries: [(key: String, value: JSONValue)] = []
            var places: [[Unicode.Scalar]: Int] = [:]
            skipBlanks()
            if index < scalars.count, scalars[index] == "}" { index += 1; return .object(entries) }
            while true {
                skipBlanks()
                guard index < scalars.count, scalars[index] == "\"", let key = string() else { return nil }
                skipBlanks()
                guard index < scalars.count, scalars[index] == ":" else { return nil }
                index += 1
                guard let item = value() else { return nil }
                let name = Array(key.unicodeScalars)
                if let place = places[name] { entries[place].value = item } else { places[name] = entries.count; entries.append((key, item)) }
                skipBlanks()
                guard index < scalars.count else { return nil }
                index += 1
                if scalars[index - 1] == "}" { return .object(entries) }
                guard scalars[index - 1] == "," else { return nil }
            }
        }
    }
}

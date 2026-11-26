/// Column widths of core.sh: `ulen` counts the bytes that start a UTF-8 character, so a width is in Unicode scalars,
/// not grapheme clusters ("é" written as e + combining accent is 2).
public enum Text {
    public static func ulen(_ text: String) -> Int {
        text.utf8.reduce(0) { $1 & 0xC0 == 0x80 ? $0 : $0 + 1 }
    }

    /// `pad`: the text and at least one space, up to `width`.
    public static func pad(_ text: String, _ width: Int) -> String {
        text + String(repeating: " ", count: max(1, width - ulen(text)))
    }
}

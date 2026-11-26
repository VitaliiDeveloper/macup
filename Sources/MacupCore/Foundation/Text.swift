/// Column widths of core.sh: `ulen` counts the bytes that start a UTF-8 character, so a width is in Unicode scalars,
/// not grapheme clusters ("é" written as e + combining accent is 2).
public enum Text {
    public static func ulen(_ s: String) -> Int {
        s.utf8.reduce(0) { $1 & 0xC0 == 0x80 ? $0 : $0 + 1 }
    }

    /// `pad`: the text and at least one space, up to `width`.
    public static func pad(_ s: String, _ width: Int) -> String {
        s + String(repeating: " ", count: max(1, width - ulen(s)))
    }
}

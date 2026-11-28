import Foundation

/// Files of this checkout a test reads: the translations, the bootstrap, and expected values kept in Fixtures/.
enum Checkout {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().path

    static func read(_ relative: String) -> String {
        (try? String(contentsOfFile: "\(root)/\(relative)", encoding: .utf8)) ?? ""
    }

    /// tests/MacupCoreTests/Fixtures/`name`.
    static func fixture(_ name: String) -> String { read("tests/MacupCoreTests/Fixtures/\(name)") }
}

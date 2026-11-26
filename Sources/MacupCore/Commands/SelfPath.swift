import Foundation

/// Where this macup is and who installed it (commands.sh `resolve_self`, `brew_prefix`), and what counts as a macup.
public enum SelfPath {
    /// The path this binary was started by, as the bash build's $0 was: the path the shell found in PATH, a symlink kept as
    /// a symlink (Homebrew's bin/macup, which a schedule must keep pointing at). Not resolved to the real file.
    /// A binary in a checkout's .build is the build output, like ./macup there: it is named as ./macup, so uninstall leaves it.
    public static func current() -> String {
        var size: UInt32 = 0
        _NSGetExecutablePath(nil, &size)
        var buf = [CChar](repeating: 0, count: Int(size) + 1)
        guard _NSGetExecutablePath(&buf, &size) == 0 else { return CommandLine.arguments[0] }
        let path = String(cString: buf)
        if let range = path.range(of: "/.build/", options: .backwards) {
            let checkout = String(path[..<range.lowerBound])
            if isCheckout(checkout) { return checkout + "/macup" }
        }
        return path
    }

    static func isCheckout(_ dir: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: dir + "/build.sh", isDirectory: &isDir) && !isDir.boolValue
            && FileManager.default.fileExists(atPath: dir + "/src", isDirectory: &isDir) && isDir.boolValue
    }

    /// `brew_prefix`: the Homebrew prefix that installed the macup at this path; "" for any other install.
    static func brewPrefix(_ path: String) -> String {
        if let range = path.range(of: "/Cellar/macup/") { return String(path[..<range.lowerBound]) }
        if path.hasSuffix("/opt/macup/bin/macup") { return String(path.dropLast("/opt/macup/bin/macup".count)) }
        guard let link = try? FileManager.default.destinationOfSymbolicLink(atPath: path), link.contains("/Cellar/macup/"),
              let resolved = realpath(dirname(path) + "/..", nil) else { return "" }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    static func dirname(_ path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return "." }
        return slash == path.startIndex ? "/" : String(path[..<slash])
    }

    /// A file macup made: a 2.9 copy has a line that starts with MACUP_VERSION=, and so does a 3.0 binary today, which
    /// carries the bash build. Phase 5 decides how a binary without it is recognised; this is the one place to change.
    static func isMacup(_ path: String) -> Bool {
        guard let data = FileManager.default.contents(atPath: path) else { return false }
        let marker = Data("MACUP_VERSION=".utf8)
        if data.starts(with: marker) { return true }
        return data.range(of: Data([0x0A]) + marker) != nil
    }
}

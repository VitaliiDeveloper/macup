import Foundation

/// Files as 2.9's tests and tools saw them.
enum Files {
    /// `[ -f ]`, through symlinks; with `followingLinks: false`, find's `-type f`.
    static func isRegular(_ path: String, followingLinks: Bool = true) -> Bool {
        var info = stat()
        let found = followingLinks ? stat(path, &info) : lstat(path, &info)
        return found == 0 && (info.st_mode & S_IFMT) == S_IFREG
    }

    /// `[ -s path ]`
    static func hasContent(_ path: String) -> Bool {
        var info = stat()
        return stat(path, &info) == 0 && info.st_size > 0
    }

    /// The records awk reads: a last newline ends the last line, it does not start another.
    static func records(_ data: Data) -> [Data] {
        var lines = data.split(separator: 0x0A, omittingEmptySubsequences: false).map { Data($0) }
        if lines.last?.isEmpty == true { lines.removeLast() }
        return lines
    }
}

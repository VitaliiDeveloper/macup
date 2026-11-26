import Foundation

/// Files as the bash build's tests and tools see them.
enum Files {
    /// `[ -f ]`, through symlinks; with `followingLinks: false`, find's `-type f`.
    static func isRegular(_ path: String, followingLinks: Bool = true) -> Bool {
        var info = stat()
        let found = followingLinks ? stat(path, &info) : lstat(path, &info)
        return found == 0 && (info.st_mode & S_IFMT) == S_IFREG
    }

    /// The records awk reads: a last newline ends the last line, it does not start another.
    static func records(_ data: Data) -> [Data] {
        var lines = data.split(separator: 0x0A, omittingEmptySubsequences: false).map { Data($0) }
        if lines.last?.isEmpty == true { lines.removeLast() }
        return lines
    }

    /// The order of bash's globs and of ls: the collation of LC_ALL, LC_COLLATE or LANG, not the bytes.
    static func order(_ env: Env) -> (String, String) -> Bool {
        let name = Env.nonEmpty(env.vars, "LC_ALL") ?? Env.nonEmpty(env.vars, "LC_COLLATE") ?? Env.nonEmpty(env.vars, "LANG") ?? "C"
        guard let locale = newlocale(LC_COLLATE_MASK, name, nil) ?? newlocale(LC_COLLATE_MASK, "C", nil) else { return { $0.utf8.lexicographicallyPrecedes($1.utf8) } }
        return { left, right in
            let previous = uselocale(locale)
            defer { uselocale(previous) }
            return strcoll(left, right) < 0
        }
    }
}

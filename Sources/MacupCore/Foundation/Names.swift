import Foundation

/// Names listed and sorted as bash's globs, `sort` and `ls` do: fnmatch and strcoll in the locale bash has once core.sh is
/// loaded. strcoll ties names that differ only in letters the collation lacks (Cyrillic, CJK) or in combining marks, so
/// each order also breaks ties the way its tool does.
public enum Names {
    /// bash takes LC_COLLATE from LC_ALL, LC_COLLATE or LANG, and LC_CTYPE as core.sh exports it (LC_ALL still wins).
    /// strcoll needs both: under LC_CTYPE "C" it reads UTF-8 bytes one by one and sorts é before b.
    /// main.swift calls it once, before anything runs on another thread: setlocale is not thread-safe.
    public static func setLocale(_ env: Env) {
        let vars = env.vars, all = Env.nonEmpty(vars, "LC_ALL"), lang = Env.nonEmpty(vars, "LANG") ?? "C"
        setlocale(LC_COLLATE, all ?? Env.nonEmpty(vars, "LC_COLLATE") ?? lang)
        setlocale(LC_CTYPE, all ?? env.lcCtype ?? Env.nonEmpty(vars, "LC_CTYPE") ?? lang)
    }

    /// A bash glob of names in one folder; a leading dot only matches a dot, and . and .. never match.
    /// bash 3.2 collects the matches in the reverse of readdir's order, then qsorts the paths with strcoll.
    static func glob(_ folder: String, _ pattern: String) -> [String] {
        guard let handle = opendir(folder) else { return [] }
        defer { closedir(handle) }
        var paths: [UnsafeMutablePointer<CChar>] = []
        defer { paths.forEach { free($0) } }
        while let entry = readdir(handle) {
            let name = withUnsafeBytes(of: entry.pointee.d_name) { String(decoding: $0.prefix(Int(entry.pointee.d_namlen)), as: UTF8.self) }
            if name != ".", name != "..", fnmatch(pattern, name, FNM_PERIOD) == 0 { paths.append(strdup("\(folder)/\(name)")!) }
        }
        paths.reverse()
        qsort(&paths, paths.count, MemoryLayout<UnsafeMutablePointer<CChar>>.stride) {
            strcoll($0!.load(as: UnsafePointer<CChar>.self), $1!.load(as: UnsafePointer<CChar>.self))
        }
        return paths.map { String(cString: $0) }
    }

    /// `sort`'s order: strcoll, then the shorter name first; names equal to both keep their order.
    static func sorted(_ names: [String]) -> [String] {
        names.sorted { left, right in
            let order = strcoll(left, right)
            return order != 0 ? order < 0 : left.unicodeScalars.count < right.unicodeScalars.count
        }
    }

    /// `ls`'s comparison of two names.
    static func ordered(_ left: String, _ right: String) -> Bool { strcoll(left, right) < 0 }
}

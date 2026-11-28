import Foundation

/// Names listed and sorted as bash's globs, `sort` and `ls` do. bash and the tools it runs pick their locale differently
/// when a variable names one macOS lacks (LC_TIME=en_DK.UTF-8 forwarded by ssh from Linux), so each order runs in its own.
/// strcoll ties names that differ only in letters the collation lacks (Cyrillic, CJK) or in combining marks: each order
/// also breaks ties the way its tool does.
public enum Names {
    /// Set by main.swift before anything runs on another thread; nil leaves the process's locale.
    static var bashLocale: locale_t?
    static var toolLocale: locale_t?

    public static func setLocale(_ env: Env) {
        for case let locale? in [bashLocale, toolLocale] { freelocale(locale) }
        bashLocale = make(bashNames(env))
        toolLocale = make(toolNames(env))
    }

    /// A bash glob of names in one folder; a leading dot only matches a dot, and . and .. never match.
    /// bash 3.2 collects the matches in the reverse of readdir's order, then qsorts the paths with strcoll.
    static func glob(_ folder: String, _ pattern: String) -> [String] {
        guard let handle = opendir(folder) else { return [] }
        defer { closedir(handle) }
        return within(bashLocale) {
            var paths: [String] = []
            while let entry = readdir(handle) {
                // only d_namlen bytes: the record can end before d_name's full 1024
                let start = UnsafeRawPointer(entry) + MemoryLayout<dirent>.offset(of: \dirent.d_name)!
                let name = String(decoding: UnsafeRawBufferPointer(start: start, count: Int(entry.pointee.d_namlen)), as: UTF8.self)
                if name != ".", name != "..", fnmatch(pattern, name, FNM_PERIOD) == 0 { paths.append("\(folder)/\(name)") }
            }
            return qsorted(paths.reversed(), descending: false)
        }
    }

    /// Python's sort of str keys: by code point.
    static func codePointOrder(_ left: String, _ right: String) -> Bool {
        left.unicodeScalars.lexicographicallyPrecedes(right.unicodeScalars)
    }

    /// `ls -r` on these paths: ls takes its operands in reverse, then qsorts them with strcoll reversed.
    static func lsReversed(_ paths: [String]) -> [String] {
        within(toolLocale) { qsorted(paths.reversed(), descending: true) }
    }

    /// `ls`'s comparison of two names.
    static func ordered(_ left: String, _ right: String) -> Bool {
        within(toolLocale) { strcoll(left, right) < 0 }
    }

    /// `sort`'s order: strcoll, then the shorter name first; names equal to both keep their order.
    static func sorted(_ names: [String]) -> [String] {
        within(toolLocale) {
            names.sorted { left, right in
                let order = strcoll(left, right)
                return order != 0 ? order < 0 : left.unicodeScalars.count < right.unicodeScalars.count
            }
        }
    }

    private static let categories: [(mask: Int32, variable: String)] = [
        (LC_COLLATE_MASK, "LC_COLLATE"), (LC_CTYPE_MASK, "LC_CTYPE"), (LC_MESSAGES_MASK, "LC_MESSAGES"),
        (LC_MONETARY_MASK, "LC_MONETARY"), (LC_NUMERIC_MASK, "LC_NUMERIC"), (LC_TIME_MASK, "LC_TIME"),
    ]

    /// bash starts with setlocale(LC_ALL, ""). When a category names a locale macOS lacks, that fails as a whole, and bash
    /// sets LANG, then each LC_x that exists over it; without a LANG that exists it stays C. core.sh's LC_CTYPE export
    /// comes last, unless LC_ALL is set.
    static func bashNames(_ env: Env) -> (collate: String, ctype: String) {
        let vars = env.vars
        if let all = Env.nonEmpty(vars, "LC_ALL") { return (all, all) }
        let lang = Env.nonEmpty(vars, "LANG")
        func value(_ variable: String) -> String { Env.nonEmpty(vars, variable) ?? lang ?? "C" }
        var names = (collate: value("LC_COLLATE"), ctype: value("LC_CTYPE"))
        if !categories.allSatisfy({ exists(value($0.variable), $0.mask) }) {
            guard let lang, exists(lang, categories.reduce(0) { $0 | $1.mask }) else { return ("C", env.lcCtype ?? "C") }
            func own(_ variable: String, _ mask: Int32) -> String {
                Env.nonEmpty(vars, variable).flatMap { exists($0, mask) ? $0 : nil } ?? lang
            }
            names = (own("LC_COLLATE", LC_COLLATE_MASK), own("LC_CTYPE", LC_CTYPE_MASK))
        }
        if let exported = env.lcCtype { names.ctype = exported }
        return names
    }

    /// The tools bash runs call setlocale(LC_ALL, "") on the environment it exports: one locale macOS lacks and all is C.
    static func toolNames(_ env: Env) -> (collate: String, ctype: String) {
        let vars = env.childVars
        func value(_ variable: String) -> String {
            Env.nonEmpty(vars, "LC_ALL") ?? Env.nonEmpty(vars, variable) ?? Env.nonEmpty(vars, "LANG") ?? "C"
        }
        guard categories.allSatisfy({ exists(value($0.variable), $0.mask) }) else { return ("C", "C") }
        return (value("LC_COLLATE"), value("LC_CTYPE"))
    }

    private static func exists(_ name: String, _ mask: Int32) -> Bool {
        guard let locale = newlocale(mask, name, nil) else { return false }
        freelocale(locale)
        return true
    }

    private static func make(_ names: (collate: String, ctype: String)) -> locale_t? {
        let collate = exists(names.collate, LC_COLLATE_MASK) ? names.collate : "C"
        let ctype = exists(names.ctype, LC_CTYPE_MASK) ? names.ctype : "C"
        return newlocale(LC_CTYPE_MASK, ctype, newlocale(LC_COLLATE_MASK, collate, nil))
    }

    /// strcoll and fnmatch read this thread's locale.
    private static func within<Result>(_ locale: locale_t?, _ body: () -> Result) -> Result {
        guard let locale else { return body() }
        let previous = uselocale(locale)
        defer { uselocale(previous) }
        return body()
    }

    private static func qsorted(_ paths: [String], descending: Bool) -> [String] {
        var pointers = paths.map { strdup($0)! }
        defer { pointers.forEach { free($0) } }
        let compare: @convention(c) (UnsafeRawPointer?, UnsafeRawPointer?) -> Int32 = descending
            ? { strcoll($1!.load(as: UnsafePointer<CChar>.self), $0!.load(as: UnsafePointer<CChar>.self)) }
            : { strcoll($0!.load(as: UnsafePointer<CChar>.self), $1!.load(as: UnsafePointer<CChar>.self)) }
        qsort(&pointers, pointers.count, MemoryLayout<UnsafeMutablePointer<CChar>>.stride, compare)
        return pointers.map { String(cString: $0) }
    }
}

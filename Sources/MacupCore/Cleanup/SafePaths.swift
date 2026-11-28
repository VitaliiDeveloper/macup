import Darwin

public struct SafePaths {
    public let home: String
    public let projectDirs: String

    public func allows(_ path: String) -> Bool {
        if aiPath(path) { return true }
        if !(Bash.starts(path, home + "/Library/") || Bash.starts(path, home + "/.")) {
            guard inProjects(path), SafePaths.artifactOK(path) else { return false }
        }
        if SafePaths.never.contains(where: { fnmatch($0, path, 0) == 0 }) { return false }
        let support = home + "/Library/Application Support"
        if Bash.starts(path, support + "/") { return SafePaths.inCacheFolder(String(decoding: path.utf8.dropFirst(support.utf8.count), as: UTF8.self)) }
        return true
    }

    /// Updaters keep downloaded updates in Sparkle and ShipIt folders until they are installed.
    static let never = ["*/../*", "*/..", "*/.codex/sessions*", "*/.codex/archived_sessions*", "*/deno/location_data", "*/deno/location_data/*",
                        "*.sqlite", "*/User", "*/User/*", "*/Backups", "*/Backups/*", "*/gradle.properties", "*/settings.xml", "*/.android/avd*",
                        "*/.android/*key*", "*/.ssh*", "*/.gnupg*", "*/Keychains*", "*/.aws", "*/.aws/*", "*/.kube", "*/.kube/*", "*/.netrc",
                        "*/.config", "*/.config/*", "*/.claude", "*/.claude/*", "*/org.sparkle-project.Sparkle", "*/org.sparkle-project.Sparkle/*",
                        "*.ShipIt", "*.ShipIt/*"]

    public func aiPath(_ path: String) -> Bool {
        if Bash.holds(path, "/../") || Bash.ends(path, "/..") || Bash.holds(path, "/./") || Bash.ends(path, "/.") { return false }
        func after(_ prefix: String) -> String { String(decoding: path.utf8.dropFirst(prefix.utf8.count), as: UTF8.self) }
        let history = home + "/.claude/file-history/"
        if Bash.starts(path, history) {
            let rest = after(history)
            return !rest.isEmpty && SafePaths.isIdentifier(rest)
        }
        let support = home + "/Library/Application Support/"
        guard Bash.starts(path, support) else { return false }
        let rest = after(support)
        guard Bash.holds(rest, "/User/workspaceStorage/"), rest.utf8.filter({ $0 == UInt8(ascii: "/") }).count < 4, !Bash.holds(rest, "//"),
              !Bash.starts(rest, "/") else { return false }
        let name = SafePaths.lastName(rest)
        return !name.isEmpty && !Bash.starts(name, ".") && SafePaths.isIdentifier(name)
    }

    /// `${path##*/}`, by scalars.
    static func lastName(_ path: String) -> String {
        guard let slash = path.unicodeScalars.lastIndex(of: "/") else { return path }
        return String(path.unicodeScalars[path.unicodeScalars.index(after: slash)...])
    }

    static func isIdentifier(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy { ("0"..."9").contains($0) || ("A"..."Z").contains($0) || ("a"..."z").contains($0) || $0 == "-" }
    }

    public static func artifactOK(_ path: String) -> Bool {
        let folder = Measure.parent(path)
        func has(_ name: String) -> Bool { access("\(folder)/\(name)", F_OK) == 0 }
        switch lastName(path) {
        case "node_modules": return true
        case "Pods": return has("Podfile")
        case ".build": return has("Package.swift")
        case ".dart_tool": return has("pubspec.yaml")
        case ".next": return has("package.json")
        case "target": return has("Cargo.toml") || has("pom.xml")
        case "build": return has("build.gradle") || has("build.gradle.kts")
        default: return false
        }
    }

    static func inCacheFolder(_ path: String) -> Bool {
        CacheTables.electronCaches.contains { Bash.holds(path + "/", "/\($0)/") }
    }

    public func projectRoots() -> [String] {
        let paths = Paths(home: home)
        return projectDirs.split(separator: ",", omittingEmptySubsequences: false).compactMap { entry -> String? in
            var folder = paths.expand(entry.trimmingCharacters(in: .whitespacesAndNewlines))
            if Bash.ends(folder, "/") { folder.unicodeScalars.removeLast() }
            guard !folder.isEmpty, !folder.utf8.elementsEqual(home.utf8), !Bash.starts(home + "/", folder + "/"), Run.isDirectory(folder) else { return nil }
            return folder
        }
    }

    public func inProjects(_ path: String) -> Bool {
        projectRoots().contains { Bash.starts(path, $0 + "/") }
    }
}

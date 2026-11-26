import Darwin

public struct SafePaths {
    public let home: String
    public let projectDirs: String

    public func allows(_ path: String) -> Bool {
        if aiPath(path) { return true }
        if !(path.hasPrefix(home + "/Library/") || path.hasPrefix(home + "/.")) {
            guard inProjects(path), SafePaths.artifactOK(path) else { return false }
        }
        if SafePaths.never.contains(where: { fnmatch($0, path, 0) == 0 }) { return false }
        let support = home + "/Library/Application Support"
        if path.hasPrefix(support + "/") { return SafePaths.inCacheFolder(String(path.dropFirst(support.count))) }
        return true
    }

    /// Updaters keep downloaded updates in Sparkle and ShipIt folders until they are installed.
    static let never = ["*/../*", "*/..", "*/.codex/sessions*", "*/.codex/archived_sessions*", "*/deno/location_data", "*/deno/location_data/*",
                        "*.sqlite", "*/User", "*/User/*", "*/Backups", "*/Backups/*", "*/gradle.properties", "*/settings.xml", "*/.android/avd*",
                        "*/.android/*key*", "*/.ssh*", "*/.gnupg*", "*/Keychains*", "*/.aws", "*/.aws/*", "*/.kube", "*/.kube/*", "*/.netrc",
                        "*/.config", "*/.config/*", "*/.claude", "*/.claude/*", "*/org.sparkle-project.Sparkle", "*/org.sparkle-project.Sparkle/*",
                        "*.ShipIt", "*.ShipIt/*"]

    public func aiPath(_ path: String) -> Bool {
        if path.contains("/../") || path.hasSuffix("/..") || path.contains("/./") || path.hasSuffix("/.") { return false }
        let history = home + "/.claude/file-history/"
        if path.hasPrefix(history) {
            let rest = String(path.dropFirst(history.count))
            return !rest.isEmpty && SafePaths.isIdentifier(rest)
        }
        let support = home + "/Library/Application Support/"
        guard path.hasPrefix(support) else { return false }
        let rest = String(path.dropFirst(support.count))
        guard rest.contains("/User/workspaceStorage/"), rest.filter({ $0 == "/" }).count < 4, !rest.contains("//"), !rest.hasPrefix("/") else { return false }
        let name = String(rest[rest.index(after: rest.lastIndex(of: "/")!)...])
        return !name.isEmpty && !name.hasPrefix(".") && SafePaths.isIdentifier(name)
    }

    static func isIdentifier(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy { ("0"..."9").contains($0) || ("A"..."Z").contains($0) || ("a"..."z").contains($0) || $0 == "-" }
    }

    public static func artifactOK(_ path: String) -> Bool {
        let folder = Measure.parent(path)
        func has(_ name: String) -> Bool { access("\(folder)/\(name)", F_OK) == 0 }
        switch path.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? path {
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
        CacheTables.electronCaches.contains { (path + "/").contains("/\($0)/") }
    }

    public func projectRoots() -> [String] {
        let paths = Paths(home: home)
        return projectDirs.split(separator: ",", omittingEmptySubsequences: false).compactMap { entry -> String? in
            var folder = paths.expand(entry.trimmingCharacters(in: .whitespacesAndNewlines))
            if folder.hasSuffix("/") { folder.removeLast() }
            guard !folder.isEmpty, folder != home, !(home + "/").hasPrefix(folder + "/"), Run.isDirectory(folder) else { return nil }
            return folder
        }
    }

    public func inProjects(_ path: String) -> Bool {
        projectRoots().contains { path.hasPrefix($0 + "/") }
    }
}

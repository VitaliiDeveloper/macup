public enum CacheTables {
    public struct Folder {
        public let task: String
        public let level: Int
        public let label: String
        public let folder: String
        public let busy: String
        public let tool: String
    }

    public static let folders: [Folder] = [
        Folder(task: "clean.derived_data", level: 1, label: "Xcode DerivedData", folder: "~/Library/Developer/Xcode/DerivedData", busy: "xcode", tool: ""),
        Folder(task: "clean.xcode_previews", level: 1, label: "SwiftUI previews", folder: "~/Library/Developer/Xcode/UserData/Previews", busy: "xcode", tool: ""),
        Folder(task: "clean.sim_caches", level: 1, label: "Simulator caches", folder: "~/Library/Developer/CoreSimulator/Caches", busy: "", tool: ""),
        Folder(task: "clean.spm", level: 1, label: "SwiftPM cache", folder: "~/Library/Caches/org.swift.swiftpm", busy: "", tool: ""),
        Folder(task: "clean.cocoapods", level: 1, label: "CocoaPods cache", folder: "~/Library/Caches/CocoaPods", busy: "", tool: ""),
        Folder(task: "clean.carthage", level: 1, label: "Carthage cache", folder: "~/Library/Caches/org.carthage.CarthageKit", busy: "", tool: ""),
        Folder(task: "clean.yarn", level: 1, label: "Yarn cache", folder: "~/Library/Caches/Yarn", busy: "", tool: "yarn"),
        Folder(task: "clean.pnpm", level: 1, label: "pnpm metadata cache", folder: "~/Library/Caches/pnpm", busy: "", tool: ""),
        Folder(task: "clean.npm", level: 1, label: "node-gyp headers", folder: "~/Library/Caches/node-gyp", busy: "", tool: ""),
        Folder(task: "clean.npm", level: 2, label: "npx cache", folder: "~/.npm/_npx", busy: "npx", tool: ""),
        Folder(task: "clean.bun", level: 1, label: "Bun install cache", folder: "~/.bun/install/cache", busy: "", tool: ""),
        Folder(task: "clean.poetry", level: 1, label: "Poetry cache", folder: "~/Library/Caches/pypoetry/cache", busy: "poetry", tool: ""),
        Folder(task: "clean.poetry", level: 1, label: "Poetry downloads", folder: "~/Library/Caches/pypoetry/artifacts", busy: "poetry", tool: ""),
        Folder(task: "clean.cargo", level: 2, label: "Cargo registry downloads", folder: "~/.cargo/registry/cache", busy: "cargo", tool: ""),
        Folder(task: "clean.cargo", level: 2, label: "Cargo registry sources", folder: "~/.cargo/registry/src", busy: "cargo", tool: ""),
        Folder(task: "clean.cargo", level: 2, label: "Cargo git checkouts", folder: "~/.cargo/git/checkouts", busy: "cargo", tool: ""),
        Folder(task: "clean.cargo", level: 2, label: "Cargo git sources", folder: "~/.cargo/git/db", busy: "cargo", tool: ""),
        Folder(task: "clean.gradle", level: 2, label: "Gradle caches", folder: "~/.gradle/caches", busy: "GradleDaemon", tool: ""),
        Folder(task: "clean.android", level: 2, label: "Android cache", folder: "~/.android/cache", busy: "", tool: ""),
    ]

    public struct ToolCache {
        public let task: String
        public let level: Int
        public let label: String
        public let tool: String
        public let key: String
        public let folder: String
    }

    public static let toolCaches: [ToolCache] = [
        ToolCache(task: "clean.npm", level: 1, label: "npm cache", tool: "npm", key: "npm", folder: "~/.npm/_cacache"),
        ToolCache(task: "clean.pnpm", level: 1, label: "pnpm store", tool: "pnpm", key: "pnpm", folder: "@pnpm"),
        ToolCache(task: "clean.pip", level: 1, label: "pip cache", tool: "pip3", key: "pip", folder: "~/Library/Caches/pip"),
        ToolCache(task: "clean.uv", level: 1, label: "uv cache", tool: "uv", key: "uv", folder: "@uv"),
        ToolCache(task: "clean.go", level: 1, label: "Go build cache", tool: "go", key: "go", folder: "@go"),
        ToolCache(task: "clean.go_mod", level: 2, label: "Go module cache", tool: "go", key: "gomod", folder: "@gomod"),
    ]

    public static let electronApps: [(folder: String, app: String)] = [
        ("Code", "Visual Studio Code"), ("Code - Insiders", "Visual Studio Code - Insiders"), ("Cursor", "Cursor"), ("Windsurf", "Windsurf"),
        ("Antigravity", "Antigravity"), ("VSCodium", "VSCodium"), ("Claude", "Claude"), ("Codex", "Codex"), ("Postman", "Postman"),
        ("Slack", "Slack"), ("discord", "Discord"), ("Notion", "Notion"), ("obsidian", "Obsidian"), ("Signal", "Signal"),
    ]

    public static let electronCaches = ["Cache", "CachedData", "Code Cache", "GPUCache", "CachedExtensionVSIXs", "logs", "DawnGraphiteCache",
                                        "DawnWebGPUCache", "GraphiteDawnCache", "GrShaderCache", "ShaderCache"]

    public static let browsers: [(name: String, app: String, folders: [String])] = [
        ("Arc", "Arc", ["Arc"]), ("Google Chrome", "Google Chrome", ["Google/Chrome"]), ("Firefox", "Firefox", ["Firefox"]),
        ("Microsoft Edge", "Microsoft Edge", ["Microsoft Edge"]), ("Brave", "Brave Browser", ["BraveSoftware"]),
        ("Opera", "Opera", ["com.operasoftware.Opera"]), ("Vivaldi", "Vivaldi", ["Vivaldi"]),
    ]
}

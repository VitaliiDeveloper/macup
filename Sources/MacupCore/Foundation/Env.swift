/// The environment macup runs in: the top of core.sh.
/// Reading it changes nothing; `apply()` makes the changes core.sh makes to the process (PATH, LC_CTYPE).
/// A run handed to the bash build must not be applied first: bash prepends to PATH itself and keeps the PATH it got as USER_PATH.
public struct Env {
    /// How install.sh and uninstall, 2.9 copies included, tell a macup from another file: a line "# macup" and a line that
    /// starts with MACUP_VERSION=, as in every bash copy. One literal, so the binary keeps it as is; tools/release.sh checks.
    public static let marker = "\n# macup\nMACUP_VERSION=\"2.9.2\"\n"
    public static let version = String(marker.split(separator: "\"")[1])
    public static let schedLabel = "com.vitaliideveloper.macup"

    public let vars: [String: String]
    /// From the environment, never `homeDirectoryForCurrentUser`: the tests run on fake homes.
    public let home: String
    /// PATH as the terminal has it: check.commands reports its folders that do not exist.
    public let userPath: String
    /// PATH for the tools macup runs: Homebrew and the usual user folders first, unless MACUP_PATH=keep (tests with fakes).
    public let path: String
    public let repo: String
    public let langHook: String?
    /// NO_COLOR set and not empty.
    public let noColor: Bool
    public let stepSecsHook: String?
    public let apps: String
    public let sysLib: String
    public let tmpDir: String

    public let confDir: String
    public let conf: String
    public let stateDir: String
    public let cacheDir: String
    public let history: String
    public let logDir: String
    public let dev: String
    public let schedPlist: String

    public enum Failure: Error, Equatable {
        /// core.sh: every path hangs off $HOME; with none, "$HOME/Library/Caches" would be the system's /Library/Caches.
        case noHome
        public var message: String { "macup: HOME is not set" }
    }

    public init(_ vars: [String: String]) throws {
        self.vars = vars
        let home = vars["HOME"] ?? ""
        guard home.hasPrefix("/"), home.count > 1 else { throw Failure.noHome }
        self.home = home
        userPath = vars["PATH"] ?? ""
        if vars["MACUP_PATH"] == "keep" {
            path = userPath
        } else {
            path = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:\(home)/.local/bin:\(home)/.npm-global/bin:\(home)/.cargo/bin:\(userPath)"
        }
        repo = Env.nonEmpty(vars, "MACUP_REPO") ?? "VitaliiDeveloper/macup"
        langHook = Env.nonEmpty(vars, "MACUP_LANG")
        noColor = !(vars["NO_COLOR"] ?? "").isEmpty
        stepSecsHook = Env.nonEmpty(vars, "MACUP_STEP_SECS")
        apps = Env.nonEmpty(vars, "MACUP_APPS") ?? "/Applications:\(home)/Applications"
        sysLib = Env.nonEmpty(vars, "MACUP_SYSLIB") ?? "/Library"
        tmpDir = Env.nonEmpty(vars, "TMPDIR") ?? "/tmp"
        confDir = (Env.nonEmpty(vars, "XDG_CONFIG_HOME") ?? "\(home)/.config") + "/macup"
        conf = confDir + "/config"
        stateDir = "\(home)/Library/Application Support/macup"
        cacheDir = "\(home)/Library/Caches/macup"
        history = stateDir + "/history.csv"
        logDir = "\(home)/Library/Logs/macup"
        dev = "\(home)/Library/Developer"
        schedPlist = "\(home)/Library/LaunchAgents/\(Env.schedLabel).plist"
    }

    /// `MACUP_RAW`: + /<branch or tag>/<file>.
    public var raw: String { "https://raw.githubusercontent.com/\(repo)" }

    public var paths: Paths { Paths(home: home) }

    /// core.sh exports LC_CTYPE=en_US.UTF-8 when the locale is not UTF-8, so tools count characters, not bytes.
    public var lcCtype: String? {
        let locale = Env.nonEmpty(vars, "LC_ALL") ?? Env.nonEmpty(vars, "LC_CTYPE") ?? vars["LANG"] ?? ""
        for marker in Env.utf8Markers where locale.contains(marker) { return nil }
        return "en_US.UTF-8"
    }

    /// The tools run in a UTF-8 locale: core.sh makes LC_CTYPE one, unless LC_ALL overrides it with another.
    public var utf8Locale: Bool {
        guard let all = Env.nonEmpty(vars, "LC_ALL") else { return true }
        return Env.utf8Markers.contains { all.contains($0) }
    }

    /// The variable when it is set and not empty, as bash's ${VAR:-default} reads it.
    public static func nonEmpty(_ vars: [String: String], _ key: String) -> String? {
        guard let value = vars[key], !value.isEmpty else { return nil }
        return value
    }

    private static let utf8Markers = ["UTF-8", "utf-8", "UTF8", "utf8"]

    /// The environment of the tools macup runs.
    public var childVars: [String: String] {
        var result = vars
        result["PATH"] = path
        if let ctype = lcCtype { result["LC_CTYPE"] = ctype }
        return result
    }

    /// Makes this process's environment the one core.sh leaves, for code that reads it directly.
    public func apply() {
        setenv("PATH", path, 1)
        if let ctype = lcCtype { setenv("LC_CTYPE", ctype, 1) }
    }

    /// Run under sudo by a user: the config, the reports and the history would become root's.
    /// help, version and uninstall still run.
    public var underSudo: Bool {
        getuid() == 0 && !(vars["SUDO_USER"] ?? "").isEmpty
    }
}

#if canImport(Darwin)
import Darwin
#endif

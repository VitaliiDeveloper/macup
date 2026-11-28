import CryptoKit
import Darwin
import Foundation

/// `macup self-update` (commands.sh `self_update`, `fetch_release`): main names the latest version, and that version's
/// release asset, checked as tools/bootstrap.sh checks it, replaces this binary by rename. A running macup keeps its file.
enum SelfUpdate {
    static func run(_ context: OneOff.Context) -> Int32 {
        let env = context.env, i18n = context.i18n
        let say = { (text: String) in context.out.write(text + "\n") }
        if env.repo.hasPrefix("__") { say(i18n.translate("This copy has no GitHub repo configured.")); return 1 }
        let target = SelfPath.executable()
        // Homebrew owns that file, and the next brew upgrade would put its own version back
        if !SelfPath.brewPrefix(SelfPath.current()).isEmpty || !SelfPath.brewPrefix(target).isEmpty {
            say(i18n.translate("macup was installed with Homebrew. Update it with: brew upgrade macup"))
            return 0
        }
        let main = env.raw + "/main/macup"
        let named = context.shell.capture(["curl", "-fsSL", "--max-time", "30", main])
        guard named.status == 0 else { say(i18n.format("Download failed: %s", main)); return 1 }
        guard let version = Bash.lines(named.output).lazy.compactMap(Version.versionLine).first, !version.isEmpty else {
            say(i18n.translate("The downloaded file looks broken; nothing changed."))
            return 1
        }
        guard Version.isNewer(version, than: Env.version) else { say(i18n.format("macup %s is already the latest.", Env.version)); return 0 }
        // next to the file it replaces, so the swap is a rename
        var template = Array("\(SelfPath.dirname(target))/.macup-update.XXXXXX".utf8CString)
        guard mkdtemp(&template) != nil else { say(i18n.format("Couldn't write %s", target)); return 1 }
        let work = String(cString: template)
        defer { try? FileManager.default.removeItem(atPath: work) }
        switch Release.fetch(version, repo: env.repo, into: work, shell: context.shell) {
        case .download(let url)?: say(i18n.format("Download failed: %s", url)); return 1
        case .checksum?: say(i18n.translate("The downloaded file does not match its published checksum; nothing changed.")); return 1
        case .broken?: say(i18n.translate("The downloaded file looks broken; nothing changed.")); return 1
        case nil: break
        }
        guard rename(work + "/macup", target) == 0 else { say(i18n.format("Couldn't write %s", target)); return 1 }
        say(i18n.format("macup updated: %s → %s", Env.version, version))
        return 0
    }
}

/// The release asset as tools/release.sh packs it, checked as tools/bootstrap.sh checks it.
enum Release {
    enum Failure: Equatable { case download(String), checksum, broken }

    static func assetURL(repo: String, version: String) -> String {
        "https://github.com/\(repo)/releases/download/v\(version)/macup-\(version)-macos-universal.tar.gz"
    }

    /// → `work`/macup: the binary of that release, which says it is that version; nil when it is there.
    static func fetch(_ version: String, repo: String, into work: String, shell: Shell) -> Failure? {
        let url = assetURL(repo: repo, version: version), archive = work + "/macup.tar.gz", binary = work + "/macup"
        let download = { (from: String, to: String) in shell.capture(["curl", "-fsSL", "--max-time", "600", from, "-o", to]).status == 0 }
        guard download(url + ".sha256", work + "/sum"), download(url, archive) else { return .download(url) }
        let published = String(decoding: FileManager.default.contents(atPath: work + "/sum") ?? Data(), as: UTF8.self)
            .split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
        guard let data = FileManager.default.contents(atPath: archive), !published.isEmpty,
              SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == published.lowercased() else { return .checksum }
        guard shell.capture(["tar", "-xzf", archive, "-C", work, "macup"]).status == 0, Files.isRegular(binary, followingLinks: false),
              !isBootstrap(binary), chmod(binary, 0o755) == 0 else { return .broken }
        return Bash.substitution(shell.capture([binary, "version"]).output) == "macup \(version)" ? nil : .broken
    }

    /// A line only the bootstrap has: never run or install it from here, or the two would hand over to each other forever.
    static func isBootstrap(_ path: String) -> Bool {
        guard let data = FileManager.default.contents(atPath: path) else { return false }
        let line = Data("LEGACY_VERSION=".utf8)
        return data.starts(with: line) || data.range(of: Data([0x0A]) + line) != nil
    }
}

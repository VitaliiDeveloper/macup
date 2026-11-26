import Darwin
import Foundation

/// The updaters that are one command each, then Grok and Antigravity, which say their own versions.
extension Updates {
    static func simple(_ run: Run, later: inout [String]) {
        let shell = run.shell, home = run.env.home, out = run.out
        func update(_ id: String, _ label: String, _ argv: [String]) {
            guard run.task(id) else { return }
            let name = Bash.substitution(out.i18n.translate(label))
            guard run.updates else { later.append(name); return }
            out.step("%s", name)
            if run.run(argv) == 0 { out.ok("%s: updated", name) } else { out.err("%s: update failed (see the report)", name) }
        }
        if shell.have("pipx") { update("update.pipx", "pipx tools", ["pipx", "upgrade-all"]) }
        if shell.have("uv") { update("update.uv", "uv tools", ["uv", "tool", "upgrade", "--all"]) }
        if shell.have("rustup") { update("update.rustup", "Rust toolchains", ["rustup", "update"]) }
        let ohMyZsh = Env.nonEmpty(run.env.vars, "ZSH") ?? home + "/.oh-my-zsh"
        if isFile(ohMyZsh + "/tools/upgrade.sh"), shell.have("zsh") {
            update("update.omz", "Oh My Zsh", ["env", "ZSH=\(ohMyZsh)", "zsh", ohMyZsh + "/tools/upgrade.sh"])
        }
        if shell.have("gh"), run.task("update.gh_ext"), !timedOutput(run, 30, ["gh", "extension", "list"]).text.isEmpty {
            update("update.gh_ext", "gh extensions", ["gh", "extension", "upgrade", "--all"])
        }
        // `tl … | grep -q` under pipefail: pnpm has to succeed too
        if shell.have("pnpm"), shell.have("node"), run.task("update.pnpm") {
            let globals = timedOutput(run, 30, ["pnpm", "ls", "-g", "--json"])
            if globals.status == 0, globals.text.contains("\"version\"") { update("update.pnpm", "pnpm globals", ["pnpm", "update", "-g"]) }
        }
        if homeBin(run, "bun") { update("update.bun", "Bun", ["bun", "upgrade"]) }
        if homeBin(run, "deno") { update("update.deno", "Deno", ["deno", "upgrade"]) }
        // cargo-update adds `cargo install-update`. Looked up as a file: starting cargo just to ask would make rustup set up a toolchain
        if shell.have("cargo"), shell.have("cargo-install-update") { update("update.cargo", "cargo programs", ["cargo", "install-update", "-a"]) }
        if shell.have("mise") { update("update.mise", "mise tools", ["mise", "upgrade"]) }
        if shell.have("asdf") { update("update.asdf", "asdf plugins", ["asdf", "plugin", "update", "--all"]) }
        for (tool, label) in [("code", "VS Code extensions"), ("cursor", "Cursor extensions"), ("windsurf", "Windsurf extensions"), ("codium", "VSCodium extensions")] where shell.have(tool) {
            update("update.editor_ext", label, [tool, "--update-extensions"])
        }
        // gcloud from Google's own installer updates its components itself; a Homebrew cask is brew's
        if homeBin(run, "gcloud") { update("update.gcloud", "Google Cloud SDK", ["gcloud", "components", "update", "--quiet"]) }
        // `dotnet tool update --all` exists since .NET 9; asked only when there are global tools
        if shell.have("dotnet"), run.task("update.dotnet"), listsSomething(home + "/.dotnet/tools") {
            let major = timedOutput(run, 20, ["dotnet", "--version"]).text.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
            if !major.isEmpty, major.allSatisfy({ ("0"..."9").contains($0) }), (Int(major) ?? 0) >= 9 {
                update("update.dotnet", ".NET global tools", ["dotnet", "tool", "update", "--global", "--all"])
            }
        }
        if [home + "/.composer/composer.json", home + "/.config/composer/composer.json"].contains(where: isFile), shell.have("composer") {
            update("update.composer", "Composer global packages", ["composer", "global", "update", "--no-interaction"])
        }
        // opt-in: updating every gem takes long; the system Ruby's gems belong to macOS and need sudo
        if shell.have("gem"), shell.which("gem") != "/usr/bin/gem" { update("update.gem", "Ruby gems", ["gem", "update"]) }
    }

    /// `[ -n "$(ls -A path 2>/dev/null)" ]`: a folder with something in it, or anything else that is there.
    private static func listsSomething(_ path: String) -> Bool {
        var info = stat()
        guard lstat(path, &info) == 0 else { return false }
        guard Run.isDirectory(path) else { return true }
        return !((try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []).isEmpty
    }

    static func grok(_ run: Run) {
        let out = run.out, label = "Grok CLI"
        let answer = timedOutput(run, 30, ["grok", "update", "--check", "--json"]).text
        let current = jsonText(answer, "currentVersion"), latest = jsonText(answer, "latestVersion")
        if latest.isEmpty {
            out.warn("%s: could not check for updates", label)
            return
        }
        guard jsonText(answer, "installer") == "internal" else { return }   // a brew or npm install is updated by that step
        if run.updates {
            if Version.isNewer(latest, than: current) {
                out.step("%s", label)
                if run.run(["grok", "update"]) != 0 { out.err("%s: update failed (see the report)", label) }
            }
            run.versionLine(label, current, field(run, ["grok", "--version"], 2))
        } else if Version.isNewer(latest, than: current) {
            out.warn("%s: %s → %s available", label, current, latest)
        } else {
            out.ok("%s %s", label, current)
        }
    }

    /// `sed -n 's/.*"key":"\([^"]*\)".*/\1/p'`: on each line, the value of the last `"key":"…"` on it.
    static func jsonText(_ text: String, _ key: String) -> String {
        let needle = Array("\"\(key)\":\"".unicodeScalars)
        var found: [String] = []
        for line in Bash.lines(text) {
            let scalars = Array(line.unicodeScalars)
            var start = scalars.count - needle.count
            while start >= 0 {
                if Array(scalars[start..<start + needle.count]) == needle,
                   let close = scalars[(start + needle.count)...].firstIndex(of: "\"") {
                    found.append(String(String.UnicodeScalarView(scalars[(start + needle.count)..<close])))
                    break
                }
                start -= 1
            }
        }
        return Bash.substitution(found.joined(separator: "\n"))
    }

    /// agy updates itself in ~/.local/bin and has no read-only check.
    static func agy(_ run: Run, later: inout [String]) {
        let label = "Antigravity CLI"
        guard run.updates else { later.append(label); return }
        let before = output(run, ["agy", "--version"])
        run.out.step("%s", label)
        if run.run(["agy", "update"]) != 0 { run.out.err("%s: update failed (see the report)", label) }
        run.versionLine(label, before, output(run, ["agy", "--version"]))
    }
}

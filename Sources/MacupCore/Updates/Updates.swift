import Darwin
import Foundation

/// updates.sh: every update.* task, in the order bash runs them, then check.macos_updates.
enum Updates {
    static func run(_ run: Run) {
        guard run.wantsUpdates else { return }
        let shell = run.shell
        run.out.beginSection(run.updates ? "Updates" : "Update status (check only, nothing installed)")
        if run.task("update.claude"), shell.have("claude") { claude(run) }
        if run.task("update.npm"), shell.have("npm"), nodeOK(run, "npm globals") { npm(run) }
        // the labels of what a check leaves to `macup update`
        var later: [String] = []
        let skillLock = run.env.home + "/.agents/.skill-lock.json"
        if run.task("update.skills"), isFile(skillLock), shell.have("npx"), nodeOK(run, "Agent skills") {
            if run.updates { skills(run, skillLock) } else { later.append(run.out.i18n.translate("Agent skills")) }
        }
        if run.task("update.brew"), shell.have("brew") { brew(run) }
        if run.task("update.mas") { appStore(run) }
        if run.task("update.apps"), shell.have("curl") { apps(run) }
        simple(run, later: &later)
        if run.task("update.grok"), shell.have("grok") { grok(run) }
        if run.task("update.agy"), shell.have("agy"), homeBin(run, "agy") { agy(run, later: &later) }
        if !later.isEmpty { run.out.info("Not checked in this mode, updated by macup update: %s", later.joined(separator: ", ")) }
        if run.task("check.macos_updates") { macOS(run) }
    }

    static func brew(_ run: Run) {
        let out = run.out
        if run.updates {
            out.step("brew update")
            run.run(["brew", "update"])
        } else {
            run.shell.vars["HOMEBREW_NO_AUTO_UPDATE"] = "1"   // brew update also updates Homebrew itself and its taps
        }
        let formulae = output(run, ["brew", "outdated", "--formula", "--verbose"])
        let casks = output(run, ["brew", "outdated", "--cask", "--verbose"])
        let formulaCount = String(Run.count(formulae)), caskCount = String(Run.count(casks))
        if Run.count(formulae) + Run.count(casks) == 0 {
            out.ok("Homebrew: up to date")
        } else {
            if run.updates {
                out.step("brew upgrade (formulae: %s, casks: %s)", formulaCount, caskCount)
                // a cask's installer may ask for the Mac password: the updaters that run next must not find sudo unlocked by it
                let sudoBefore = run.shell.sudoCached
                let status = run.run(["brew", "upgrade"])
                if !sudoBefore { run.shell.forgetSudo() }
                if status == 0 { out.ok("Homebrew: upgraded — formulae: %s, casks: %s", formulaCount, caskCount) } else { out.err("Homebrew: upgraded with errors (see the report)") }
                run.doneUpdate("Homebrew: formulae: %s, casks: %s", formulaCount, caskCount)
            } else {
                out.warn("Homebrew: outdated — formulae: %s, casks: %s", formulaCount, caskCount)
            }
            run.lines(formulae + "\n" + casks + "\n")
        }
        if !run.updates { listAge(run) }
        // in a check the casks brew upgrades anyway are already listed above; not --greedy: a :latest cask is always "outdated"
        var greedy = output(run, ["brew", "outdated", "--cask", "--greedy-auto-updates", "--quiet"])
        if !run.updates {
            let listed = Set(Bash.lines(casks).map { Awk.firstField($0) }.filter { !$0.isEmpty })
            greedy = Bash.substitution(Bash.lines(greedy).filter { !listed.contains($0) }.map { $0 + "\n" }.joined())
        }
        guard !greedy.isEmpty else { return }
        out.info("Casks that update themselves: %s. Force with: brew upgrade --cask --greedy-auto-updates", joined(Bash.lines(greedy), limit: 10))
    }

    private static func listAge(_ run: Run) {
        let repository = output(run, ["brew", "--repository"]), cache = output(run, ["brew", "--cache"])
        var newest: time_t = 0
        for file in ["\(repository)/.git/FETCH_HEAD", "\(cache)/api/formula.jws.json", "\(cache)/api/cask.jws.json"] {
            var info = stat()
            if lstat(file, &info) == 0, info.st_mtimespec.tv_sec > newest { newest = info.st_mtimespec.tv_sec }
        }
        if newest > 0, time(nil) - newest > 86400 {
            run.out.info("The Homebrew package list is from %s; macup update refreshes it", Run.date("%Y-%m-%d", newest))
        }
    }

    // MARK: helpers shared by the updaters

    /// `$(tool 2>/dev/null)`.
    static func output(_ run: Run, _ argv: [String]) -> String {
        Bash.substitution(run.shell.capture(argv, stdin: .inherit).output)
    }

    /// `$(tl seconds tool… 2>/dev/null)`, or `2>&1` with `errors`: what the tool printed before it ended or was stopped,
    /// and its status (124 when stopped).
    static func timedOutput(_ run: Run, _ seconds: Int, _ argv: [String], errors: Bool = false) -> (status: Int32, text: String) {
        var fds: [Int32] = [0, 0]
        guard pipe(&fds) == 0 else { return (127, "") }
        var data = Data()
        let drained = DispatchSemaphore(value: 0)
        // read while the tool runs: a full pipe would stop it before it ends
        Thread {
            data = FileHandle(fileDescriptor: fds[0], closeOnDealloc: true).readDataToEndOfFile()
            drained.signal()
        }.start()
        // .fd rather than .stdout: a missing tool's "command not found" goes into the capture, as with 2>&1
        let status = run.shell.tl(seconds, argv, stdout: .fd(fds[1]), stderr: errors ? .fd(fds[1]) : .null)
        close(fds[1])
        drained.wait()
        return (status, Bash.substitution(String(decoding: data.filter { $0 != 0 }, as: UTF8.self)))   // bash 3.2's $() drops NUL bytes
    }

    /// `$(tool 2>/dev/null | awk '{print $N}')`.
    static func field(_ run: Run, _ argv: [String], _ number: Int) -> String {
        Bash.substitution(Bash.lines(run.shell.capture(argv, stdin: .inherit).output).map { Awk.field($0, number) }.joined(separator: "\n"))
    }

    /// `(cd "$HOME" && run …)`: the step runs from the home folder (a project's settings in the current folder would apply),
    /// with PWD and OLDPWD as cd leaves them.
    static func inHome(_ run: Run, _ argv: [String]) -> Int32 {
        let shell = run.shell, saved = (pwd: shell.vars["PWD"], oldpwd: shell.vars["OLDPWD"])
        let here = open(".", O_RDONLY), herePath = FileManager.default.currentDirectoryPath
        defer {
            if here >= 0 { fchdir(here); close(here) } else { chdir(herePath) }
            shell.vars["PWD"] = saved.pwd
            shell.vars["OLDPWD"] = saved.oldpwd
        }
        // bash keeps the PWD it was given only when it names the folder it started in
        var given = stat(), current = stat()
        let pwdValid = saved.pwd.map { $0.hasPrefix("/") && stat($0, &given) == 0 && stat(".", &current) == 0 && given.st_dev == current.st_dev && given.st_ino == current.st_ino } ?? false
        shell.vars["OLDPWD"] = pwdValid ? saved.pwd : herePath
        guard chdir(run.env.home) == 0 else { return 1 }
        var parts: [Substring] = []   // cd's logical path: no "//", "." or ".."
        for part in run.env.home.split(separator: "/") where part != "." {
            if part == ".." { _ = parts.popLast() } else { parts.append(part) }
        }
        shell.vars["PWD"] = "/" + parts.joined(separator: "/")
        return run.run(argv)
    }

    /// `read -r first second … rest` with the default IFS: words, then the rest of the line without its outer blanks.
    static func read(_ line: String, _ count: Int) -> [String] {
        let scalars = Array(line.unicodeScalars)
        func isBlank(_ index: Int) -> Bool { scalars[index] == " " || scalars[index] == "\t" }
        var words: [String] = [], index = 0
        func text(_ range: Range<Int>) -> String { String(String.UnicodeScalarView(scalars[range])) }
        while words.count < count {
            while index < scalars.count, isBlank(index) { index += 1 }
            var end = index
            if words.count == count - 1 {
                end = scalars.count
                while end > index, isBlank(end - 1) { end -= 1 }
            } else {
                while end < scalars.count, !isBlank(end) { end += 1 }
            }
            words.append(text(index..<end))
            index = end
        }
        return words
    }

    /// `printf '%s\n' "$list" | awk -v n="$name" '$1==n{print $2}'`: the second field of the lines that start with that name.
    static func secondField(of name: String, in list: String) -> String {
        let wanted = Awk.unescape(name)
        // awk compares as numbers when both sides look like numbers
        func same(_ field: String) -> Bool {
            Awk.isNumber(field) && Awk.isNumber(wanted) ? Awk.number(field) == Awk.number(wanted) : field.unicodeScalars.elementsEqual(wanted.unicodeScalars)
        }
        return Bash.substitution(Bash.lines(list).filter { same(Awk.firstField($0)) }.map { Awk.field($0, 2) }.joined(separator: "\n"))
    }

    /// `head -N | paste -sd, - | sed 's/,/, /g'`, and "+M" for the lines left out.
    static func joined(_ lines: [String], limit: Int) -> String {
        var shown = lines.prefix(limit).joined(separator: ",").replacingOccurrences(of: ",", with: ", ")
        let count = lines.filter { !$0.isEmpty }.count
        if count > limit { shown += " +\(count - limit)" }
        return shown
    }

    /// `[ -f path ]`.
    static func isFile(_ path: String) -> Bool {
        var info = stat()
        return stat(path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFREG
    }

    /// The tool's own installer put it in the home folder; a Homebrew copy is updated by brew.
    static func homeBin(_ run: Run, _ name: String) -> Bool {
        run.shell.which(name)?.hasPrefix(run.env.home + "/") ?? false
    }

    /// Python's sort of str keys: by code point.
    static func codePointOrder(_ left: String, _ right: String) -> Bool {
        left.unicodeScalars.lexicographicallyPrecedes(right.unicodeScalars)
    }
}

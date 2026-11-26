import Darwin

/// The updates unit fills in the rest; until then the router keeps runs with its tasks on bash.
enum Updates {
    static func run(_ run: Run) {
        guard run.wantsUpdates else { return }
        run.out.beginSection(run.updates ? "Updates" : "Update status (check only, nothing installed)")
        if run.task("update.brew"), run.shell.have("brew") { brew(run) }
    }

    static func brew(_ run: Run) {
        let out = run.out
        if run.updates {
            out.step("brew update")
            run.run(["brew", "update"])
        } else {
            run.shell.vars["HOMEBREW_NO_AUTO_UPDATE"] = "1"   // brew update also updates Homebrew itself and its taps
        }
        let formulae = brewOutput(run, ["outdated", "--formula", "--verbose"])
        let casks = brewOutput(run, ["outdated", "--cask", "--verbose"])
        let formulaCount = String(Run.count(formulae)), caskCount = String(Run.count(casks))
        if Run.count(formulae) + Run.count(casks) == 0 {
            out.ok("Homebrew: up to date")
        } else {
            if run.updates {
                out.step("brew upgrade (formulae: %s, casks: %s)", formulaCount, caskCount)
                // a cask's installer may ask for the Mac password: the updaters that run next must not find sudo unlocked by it
                let sudoBefore = run.shell.tl(0, ["sudo", "-n", "true"], stderr: .null) == 0
                let status = run.run(["brew", "upgrade"])
                if !sudoBefore { _ = run.shell.tl(0, ["sudo", "-k"], stderr: .null) }
                if status == 0 { out.ok("Homebrew: upgraded — formulae: %s, casks: %s", formulaCount, caskCount) } else { out.err("Homebrew: upgraded with errors (see the report)") }
                run.doneUpdate("Homebrew: formulae: %s, casks: %s", formulaCount, caskCount)
            } else {
                out.warn("Homebrew: outdated — formulae: %s, casks: %s", formulaCount, caskCount)
            }
            run.lines(formulae + "\n" + casks + "\n")
        }
        if !run.updates { listAge(run) }
        // in a check the casks brew upgrades anyway are already listed above; not --greedy: a :latest cask is always "outdated"
        var greedy = brewOutput(run, ["outdated", "--cask", "--greedy-auto-updates", "--quiet"])
        if !run.updates {
            let listed = Set(Bash.lines(casks).map { Awk.firstField($0) }.filter { !$0.isEmpty })
            greedy = Bash.substitution(Bash.lines(greedy).filter { !listed.contains($0) }.map { $0 + "\n" }.joined())
        }
        guard !greedy.isEmpty else { return }
        let all = Bash.lines(greedy)
        var shown = all.prefix(10).joined(separator: ",").replacingOccurrences(of: ",", with: ", ")
        let count = Run.count(greedy)
        if count > 10 { shown += " +\(count - 10)" }
        out.info("Casks that update themselves: %s. Force with: brew upgrade --cask --greedy-auto-updates", shown)
    }

    private static func brewOutput(_ run: Run, _ arguments: [String]) -> String {
        Bash.substitution(run.shell.capture(["brew"] + arguments, stdin: .inherit).output)
    }

    private static func listAge(_ run: Run) {
        let repository = brewOutput(run, ["--repository"]), cache = brewOutput(run, ["--cache"])
        var newest: time_t = 0
        for file in ["\(repository)/.git/FETCH_HEAD", "\(cache)/api/formula.jws.json", "\(cache)/api/cask.jws.json"] {
            var info = stat()
            if lstat(file, &info) == 0, info.st_mtimespec.tv_sec > newest { newest = info.st_mtimespec.tv_sec }
        }
        if newest > 0, time(nil) - newest > 86400 {
            run.out.info("The Homebrew package list is from %s; macup update refreshes it", Run.date("%Y-%m-%d", newest))
        }
    }
}

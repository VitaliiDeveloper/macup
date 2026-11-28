import Darwin

/// The pick at the end of a check on a terminal (summary.sh), and --pick (cleaners.sh): a person chooses, macup cleans
/// exactly that.
enum Pick {
    /// After a check on a terminal with something to clean: numbers, ranges or a level; a yes for what is aggressive or
    /// opt-in; the Mac password for system items.
    static func afterCheck(_ run: Run) {
        guard run.arguments.dry, !run.candidates.list.isEmpty, isatty(0) == 1, isatty(1) == 1, run.potAuto + run.potMore + run.potTrash > 0 else { return }
        let out = run.out, i18n = out.i18n, list = run.candidates.list
        out.write("\n")
        var chosen = choose(Terminal.ask(i18n.translate("Clean now? Numbers (1,3 or 2-5), a level (safe, standard, aggressive), or Enter to skip: ")),
                            list, i18n)
        guard !chosen.isEmpty else { return }
        if chosen.contains(where: { list[$0].task == "clean.dev_containers" }) {
            Terminal.say(i18n.translate("The picked containers hold app data (documents, settings, databases): it goes to the Trash.") + "\n")
        }
        if chosen.contains(where: { list[$0].level == 3 || !list[$0].auto }) {
            let question = "This includes aggressive or opt-in items: apps may sign you out or rebuild caches slowly. Quit those apps first. Continue? [y/N] "
            if !Terminal.isYes(Terminal.ask(i18n.translate(question))) { chosen = [] }
        }
        let system = chosen.filter { list[$0].sudo }
        if !system.isEmpty {
            out.beginSection("Cleanup")
            out.info("These steps need your Mac password:")
            let orphans = Leftovers.state(run).orphans
            for index in system {
                guard let number = Int(list[index].paths.dropFirst(5)), orphans.indices.contains(number) else { continue }
                run.lines(Leftovers.sudoCommands(run, orphans[number]).joined(separator: "\n"))
            }
            out.write(out.colors.cl)
            if !run.shell.askSudo("  \(i18n.translate("Mac password to remove system leftovers:")) ") {
                out.warn("Password not accepted, system items skipped")
                chosen = chosen.filter { !list[$0].sudo }
            }
        }
        if !chosen.isEmpty {
            out.beginSection("Cleanup")
            for index in chosen { Cleanup.execute(run, index) }
        }
        if !system.isEmpty { run.shell.forgetSudo(errors: .inherit) }
    }

    /// `pick`: the indexes an answer names, ascending, once each. A level word takes every candidate a clean at that level
    /// would; leftovers of deleted apps and dev containers hold data, so only their own number takes them, never a range.
    static func choose(_ answer: String, _ list: [Candidate], _ i18n: I18n) -> [Int] {
        let visible = list.indices.filter { list[$0].visible }
        var chosen = Set<Int>()
        // $(echo "$ans" | tr ',' ' '), split as an unquoted expansion
        let words = Bash.echoed(answer).unicodeScalars.map { $0 == "," ? " " : $0 }.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" })
        for word in words.map({ String(String.UnicodeScalarView($0)) }) {
            if let level = (1...3).first(where: { Leftovers.same(word, Cleanup.levelName($0)) || Leftovers.same(word, Cleanup.levelWord($0, i18n)) }) {
                chosen.formUnion(list.indices.filter { list[$0].auto && list[$0].level <= level })
                continue
            }
            // ^[0-9]{1,4}(-[0-9]{1,4})?$; 08 is not octal, and 1-9999 stops at the number of candidates
            let ends = word.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
            guard ends.allSatisfy({ (1...4).contains($0.count) && $0.unicodeScalars.allSatisfy { ("0"..."9").contains($0) } }),
                  let first = Int(ends[0]), let given = Int(ends[ends.count - 1]) else { continue }
            let last = min(given, list.count), own = ends[0] == ends[ends.count - 1]
            guard first <= last else { continue }
            for number in first...last where number >= 1 && number <= visible.count {
                let index = visible[number - 1], task = list[index].task
                if own || !(task.hasPrefix("clean.orphan_") || task == "clean.dev_containers") { chosen.insert(index) }
            }
        }
        return chosen.sorted()
    }

    /// --pick: the keys a check gave, chosen by a person in another program; that choice is the confirmation.
    static func keys(_ run: Run) {
        run.out.beginSection("Cleanup")
        var pick = Array(run.arguments.pick.utf8)
        for index in run.candidates.list.indices {
            let wanted = Array(",\(run.candidates.list[index].key),".utf8)
            guard let start = pick.indices.first(where: { pick[$0...].starts(with: wanted) }) else { continue }
            Cleanup.execute(run, index)
            pick.replaceSubrange(start..<start + wanted.count, with: [UInt8(ascii: ",")])
        }
        let gone = Bash.lines(String(decoding: pick.map { $0 == UInt8(ascii: ",") ? 0x0A : $0 }, as: UTF8.self)).filter { !$0.isEmpty }
        if !gone.isEmpty { run.out.err("Not cleaned, no longer there: %s — run macup check again", Cleaners.commaList(gone)) }
    }
}

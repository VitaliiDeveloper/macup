import Darwin
import Foundation

/// report.sh's deep scan (--deep).
extension Checks {
    static func deep(_ run: Run) {
        guard run.arguments.deep else { return }
        let out = run.out, home = run.env.home, paths = run.env.paths
        out.beginSection("Deep scan")
        out.step("Measuring your home folder (can take a few minutes)")
        out.info("Largest folders in your home:")
        for (size, path) in largest(run, Names.glob(home, "*") + Names.glob(home, ".[!.]*"), 12) { out.sub("\(Size.hum(size))  \(paths.tildify(path))") }
        out.info("Largest folders in Application Support (mostly app data, not caches):")
        for (size, path) in largest(run, Names.glob(home + "/Library/Application Support", "*"), 10) {
            out.sub("\(Size.hum(size))  \(path.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? path)")
        }
        downloads(run)
        artifacts(run)
    }

    /// `du -sk <paths> | sort -rn | head -<count> | while read -r size path`.
    static func largest(_ run: Run, _ operands: [String], _ count: Int) -> [(String, String)] {
        guard !operands.isEmpty else { return [] }
        return sortedBySize(run, run.shell.capture(["du", "-sk"] + operands, stdin: .inherit).output).prefix(count).map(sizeAndPath)
    }

    static func downloads(_ run: Run) {
        let out = run.out, folder = run.env.home + "/Downloads"
        guard Run.isDirectory(folder) else { return }
        let old = records(run.shell.capture(["find", folder, "-mindepth", "1", "-maxdepth", "1", "-mtime", "+90"], stdin: .inherit).output)
        if !old.isEmpty {
            // what xargs leaves for paths: ARG_MAX less 4 KB, the environment and du's own words, each with its NUL and pointer
            let room = Int(sysconf(_SC_ARG_MAX)) - 4096 - (run.shell.vars.map { "\($0.key)=\($0.value)" } + ["du", "-sk"]).reduce(0) { $0 + $1.utf8.count + 9 }
            let total = batches(old, room: room).reduce(0.0) { sum, batch in
                records(run.shell.capture(["du", "-sk"] + batch, stdin: .null).output).reduce(sum) { $0 + Awk.number(Awk.firstField($1)) }
            }
            out.info("Downloads older than 90 days: %s items, %s — review and delete what you don't need", String(Run.count(old.joined(separator: "\n"))), Size.hum(awkNumber(total)))
        }
        let big = records(run.shell.capture(["find", folder, "-type", "f", "-size", "+1G"], stdin: .inherit).output).prefix(10)
        if !big.isEmpty {
            out.info("Files over 1 GB in Downloads:")
            for file in big { out.sub("\(Size.hum(run.kb(file)))  \(run.env.paths.tildify(file))") }
        }
    }

    /// The du runs of `xargs -0 du -sk`: BSD xargs gives a command at most 5000 paths, and fewer when they would not fit
    /// in `room` bytes (hard links count once per du).
    static func batches(_ paths: [String], room: Int) -> [[String]] {
        var all: [[String]] = [], batch: [String] = [], bytes = 0
        for path in paths {
            if batch.count == 5000 || (!batch.isEmpty && bytes + path.utf8.count + 1 > room) { all.append(batch); batch = []; bytes = 0 }
            batch.append(path)
            bytes += path.utf8.count + 1
        }
        return batch.isEmpty ? all : all + [batch]
    }

    static func artifacts(_ run: Run) {
        let out = run.out, paths = run.env.paths
        out.step("Scanning projects for build artifacts")
        let roots = run.safePaths.projectRoots()
        // target and build are common names: only next to the build file that makes them (Cargo, Maven, Gradle)
        let found = roots.flatMap { root in
            Bash.lines(run.shell.capture(["find", root, "-maxdepth", "6", "-type", "d", "(", "-name", "node_modules", "-o", "-name", "Pods", "-o", "-name", ".build",
                                          "-o", "-name", ".dart_tool", "-o", "-name", "DerivedData", "-o", "-name", ".next", "-o", "-name", ".venv",
                                          "-o", "(", "-name", "target", "-exec", "test", "-e", "{}/../Cargo.toml", "-o", "-e", "{}/../pom.xml", ";", ")",
                                          "-o", "(", "-name", "build", "-exec", "test", "-e", "{}/../build.gradle", "-o", "-e", "{}/../build.gradle.kts", ";", ")", ")",
                                          "-prune", "-print"], stdin: .inherit).output)
        }.filter { !$0.isEmpty }
        if !found.isEmpty {
            let top = sortedBySize(run, found.map { "\(run.kb($0)) \($0)\n" }.joined())
            let total = top.reduce(0.0) { $0 + Awk.number(Awk.firstField($1)) }
            out.info("Project build artifacts (node_modules, Pods, .build, .dart_tool, .next, .venv, Rust and Maven target, Gradle build): %s total; largest:",
                     Size.hum(awkNumber(total)))
            for (size, path) in top.prefix(8).map(sizeAndPath) { out.sub("\(Size.hum(size))  \(paths.tildify(path))") }
            if !run.task("clean.stale_node_modules") {
                out.info("Tip: enable clean.stale_node_modules in the config to remove node_modules from projects you haven't touched in %s days",
                         String(run.settings.staleProjectDays))
            }
        } else if roots.isEmpty {
            out.info("No project folders found. Set project_dirs in %s", paths.tildify(run.env.conf))
        } else {
            out.info("No build artifacts in: %s", roots.map(paths.tildify).joined(separator: ",").replacingOccurrences(of: ",", with: ", "))
        }
    }

    /// `… | sort -rn`, through the real sort: equal sizes come out in the order the locale gives, as in the bash build.
    static func sortedBySize(_ run: Run, _ text: String) -> [String] {
        var ends: [Int32] = [0, 0]
        guard pipe(&ends) == 0 else { return [] }
        _ = fcntl(ends[1], F_SETNOSIGPIPE, 1)   // a sort that is gone makes the write fail, not macup die
        let writer = FileHandle(fileDescriptor: ends[1], closeOnDealloc: true)
        // from another thread: sort reads everything before it writes, and a pipe holds only so much
        Thread { try? writer.write(contentsOf: Data(text.utf8)); try? writer.close() }.start()
        let sorted = run.shell.capture(["sort", "-rn"], stdin: .fd(ends[0])).output
        close(ends[0])
        return records(sorted)
    }

    /// `read -r size path`: the first word, and the rest without the blanks around it.
    static func sizeAndPath(_ line: String) -> (String, String) {
        let blank: (Unicode.Scalar) -> Bool = { $0 == " " || $0 == "\t" }
        let scalars = line.unicodeScalars.drop(while: blank)
        let size = scalars.prefix(while: { !blank($0) })
        var rest = scalars.dropFirst(size.count).drop(while: blank)
        while let last = rest.last, blank(last) { rest = rest.dropLast() }
        return (String(String.UnicodeScalarView(size)), String(String.UnicodeScalarView(rest)))
    }
}

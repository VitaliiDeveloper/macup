import Darwin
import Foundation

/// tools.sh: the tools and services checks, in the order bash runs them.
/// bash reads simulator runtimes, commands, certificates and crash reports with python3, and only `if have python3`;
/// here they are read on every Mac (an intended difference).
enum Tools {
    static func run(_ run: Run) {
        run.out.beginSection("Tools & services")
        let shell = run.shell
        if run.task("check.mcp"), shell.have("claude") { mcp(run) }
        if run.task("check.brew_doctor"), shell.have("brew") { brewDoctor(run) }
        if run.task("check.xcode") { xcode(run) }
        if run.task("check.devtools") { devtools(run) }
        if run.task("check.commands") { commands(run) }
        if run.task("check.docker"), shell.have("docker"), shell.tl(20, ["docker", "info"], stdout: .null, stderr: .null) == 0 { docker(run) }
        if run.task("check.gh"), shell.have("gh"), hasContent(ghHosts(run.env)) { gh(run) }
        if run.task("check.certs"), shell.have("security"), shell.have("openssl") { certs(run) }
        if run.task("check.crashes"), Run.isDirectory(run.env.home + "/Library/Logs/DiagnosticReports") { crashes(run) }
    }

    static func mcp(_ run: Run) {
        let out = run.out
        out.step("Checking MCP servers")
        // from $HOME: the list depends on the current folder (local-scope servers)
        let answer = inHome(run, orElse: (status: Int32(1), text: "", utf8: true)) { capture(run.shell, 120, ["claude", "mcp", "list"], stdin: .null) }
        let list = Bash.lines(Bash.substitution(noColor(answer.text)))
        let total = list.filter { matches(mcpLine, $0) }.count
        let bad = list.filter { matches(mcpBad, $0) }
        if answer.status == 124 {
            out.warn("%s: no answer in %s seconds, skipped", "claude mcp list", "120")
        } else if total == 0 {
            out.info("Claude Code MCP servers: none configured")
        } else if bad.isEmpty {
            out.ok("Claude Code MCP servers: all %s connected", String(total))
        } else {
            out.warn("Claude Code MCP servers: %s of %s not working", String(bad.count), String(total))
            run.lines(bad.joined(separator: "\n"))
        }
    }

    private static let mcpLine = try! NSRegularExpression(pattern: "✓|✔|✗|✘|⚠|Connected|Failed|[Aa]uth")
    private static let mcpBad = try! NSRegularExpression(pattern: "✗|✘|⚠|Failed|[Nn]eeds auth")
    private static let colorCode = try! NSRegularExpression(pattern: "\u{1B}\\[[0-9;?]*[A-Za-z]")

    /// core.sh `nocolor`.
    static func noColor(_ text: String) -> String {
        colorCode.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length), withTemplate: "")
    }

    static func brewDoctor(_ run: Run) {
        let out = run.out
        out.step("brew doctor")
        let doctor = capture(run.shell, 240, ["brew", "doctor"], stderr: .stdout)
        let text = Bash.substitution(doctor.text)
        run.log.append(Bash.echo(text))
        let warnings = Bash.lines(text).filter { starts($0, "Warning:") }.count
        if doctor.status == 124 {
            out.warn("%s: no answer in %s seconds, skipped", "brew doctor", "240")
        } else if warnings > 0 {
            out.warn("brew doctor: %s warnings (details in the report)", String(warnings))
        } else {
            out.ok("brew doctor: all good")
        }
    }

    static func xcode(_ run: Run) {
        let out = run.out
        let select = capture(run.shell, 0, ["xcode-select", "-p"])
        let developer = Bash.substitution(select.text)
        if select.status == 0, Run.isDirectory(developer) {
            let version = firstLine(capture(run.shell, 0, ["xcodebuild", "-version"]).text)
            out.ok("Developer tools: %s (%s)", version.isEmpty ? out.i18n.translate("Command Line Tools only") : version, run.env.paths.tildify(developer))
        } else {
            out.warn("Developer tools: not installed or broken — run: xcode-select --install")
        }
        guard run.shell.have("xcrun") else { return }
        let runtimes = simRuntimes(capture(run.shell, 0, ["xcrun", "simctl", "runtime", "list", "-j"]).text)
        guard !runtimes.isEmpty else { return }
        let lines = Bash.lines(runtimes), total = Updates.read(lines[0], 2)
        guard (Checks.integer(total[0]) ?? 0) > 0 else { return }
        out.info("Simulator runtimes: %s, %s — remove old ones in Xcode → Settings → Components", total[0], Size.hum(total[1]))
        lines.dropFirst().forEach(out.mdonly)
    }

    /// macup_helpers.py `sim-runtimes`: `simctl runtime list -j` → "count KB", then one line per runtime, by platform and version.
    /// Where Python stops with an error, what it printed before.
    static func simRuntimes(_ json: String) -> String {
        guard case .object(let entries)? = JSONValue.parse(Data(json.utf8)), entries.allSatisfy({ if case .object = $0.value { return true }; return false }) else { return "" }
        func text(_ runtime: JSONValue, _ key: String) -> String? { (runtime[key] ?? .string("")).string }
        var runtimes = entries.map(\.value)
        if runtimes.count > 1 {
            guard runtimes.allSatisfy({ text($0, "platformIdentifier") != nil && text($0, "version") != nil }) else { return "" }   // Python sorts only what it can compare
            runtimes = stableSorted(runtimes) { left, right in
                let leftPlatform = text(left, "platformIdentifier") ?? "", rightPlatform = text(right, "platformIdentifier") ?? ""
                if Updates.codePointOrder(leftPlatform, rightPlatform) { return true }
                if Updates.codePointOrder(rightPlatform, leftPlatform) { return false }
                return Updates.codePointOrder(text(left, "version") ?? "", text(right, "version") ?? "")
            }
        }
        let sizes = runtimes.map { $0["sizeBytes"] ?? .number("0") }
        guard sizes.allSatisfy({ bytes($0) != nil }) else { return "" }
        var total: String
        if sizes.allSatisfy({ whole($0) != nil }) {
            let sum = sizes.reduce(Int64(0)) { $0 + (whole($1) ?? 0) }
            total = String(sum >= 0 ? sum / 1024 : (sum - 1023) / 1024)
        } else {
            total = JSONValue.number(String((sizes.reduce(0.0) { $0 + (bytes($1) ?? 0) } / 1024).rounded(.down))).pythonString
        }
        var lines = [String(runtimes.count) + " " + total]
        for (runtime, size) in zip(runtimes, sizes) {
            guard let identifier = text(runtime, "platformIdentifier") else { break }
            let last = identifier.unicodeScalars.split(separator: ".", omittingEmptySubsequences: false).last.map { String(String.UnicodeScalarView($0)) } ?? ""
            let platform = last.replacingOccurrences(of: "platform", with: "", options: .literal)
            lines.append("\(platform) \((runtime["version"] ?? .string("?")).pythonString) · " + Awk.format("%.1f GB", (bytes(size) ?? 0) / 1e9))
        }
        return lines.joined(separator: "\n")
    }

    /// A JSON number or bool as Python adds it up.
    private static func bytes(_ value: JSONValue) -> Double? {
        switch value {
        case .number(let text): return Double(text)
        case .bool(let flag): return flag ? 1 : 0
        default: return nil
        }
    }

    /// The same, when it is a Python int.
    private static func whole(_ value: JSONValue) -> Int64? {
        switch value {
        case .number(let text): return Int64(text)
        case .bool(let flag): return flag ? 1 : 0
        default: return nil
        }
    }

    static func devtools(_ run: Run) {
        let shell = run.shell
        var tools = ""
        func tool(_ name: String, _ version: String) {
            if !version.isEmpty { tools += (tools.isEmpty ? "" : " · ") + "\(name) \(version)" }
        }
        func output(_ argv: [String], stderr: Shell.Out = .null) -> String { capture(shell, 0, argv, stderr: stderr).text }
        if shell.have("swift") { tool("Swift", swiftVersion(output(["swift", "--version"], stderr: .stdout))) }
        if shell.have("pod") { tool("CocoaPods", Bash.substitution(output(["pod", "--version"]))) }
        if shell.have("flutter") {
            var line = dropPrefix(firstLine(output(["flutter", "--version"])), "Flutter ")
            if let cut = line.range(of: " •", options: .literal) { line = String(line[..<cut.lowerBound]) }
            tool("Flutter", line)
        }
        if shell.have("node") { tool("Node", Bash.substitution(Bash.lines(output(["node", "--version"])).map { dropPrefix($0, "v") }.joined(separator: "\n"))) }
        if shell.have("ruby") { tool("Ruby", Bash.substitution(output(["ruby", "-e", "print RUBY_VERSION"]))) }
        if shell.have("python3") { tool("Python", Bash.substitution(output(["python3", "-c", "import platform; print(platform.python_version())"]))) }
        if shell.have("codex") {
            let fields = firstLine(output(["codex", "--version"])).unicodeScalars.split(whereSeparator: { $0 == " " || $0 == "\t" })
            tool("Codex", fields.last.map { String(String.UnicodeScalarView($0)) } ?? "")
        }
        if !tools.isEmpty { run.out.info("%s", tools) }
        if Run.isDirectory("/Applications/Claude.app") {
            run.out.info("Claude Desktop %s (updates itself)", Bash.substitution(output(["defaults", "read", "/Applications/Claude.app/Contents/Info.plist", "CFBundleShortVersionString"])))
        }
    }

    private static let swiftVersionPattern = try! NSRegularExpression(pattern: "Swift version ([0-9.]*)")

    /// `grep -o 'Swift version [0-9.]*' | head -1 | sed 's/Swift version //'`
    static func swiftVersion(_ text: String) -> String {
        guard let match = swiftVersionPattern.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) else { return "" }
        return (text as NSString).substring(with: match.range(at: 1))
    }

    static func docker(_ run: Run) {
        // the Reclaimable column has a space inside ("1.2GB (50%)"), so the columns are asked for by name
        let usage = capture(run.shell, 30, ["docker", "system", "df", "--format", "{{.Type}} {{.Size}}, {{.Reclaimable}} reclaimable"]).text
        let joined = Bash.substitution(pasted(usage, ";").replacingOccurrences(of: ";", with: "; ", options: .literal))
        if !joined.isEmpty { run.out.info("Docker: %s", joined) }
        let volumes = Run.count(capture(run.shell, 30, ["docker", "volume", "ls", "-qf", "dangling=true"]).text)
        if volumes > 0 {
            run.out.info("Docker volumes no container uses: %s — macup never deletes volumes; look: docker volume ls -f dangling=true", String(volumes))
        }
    }

    /// `paste -sd<separator> -`: the lines joined, the newline that ends the last one left out.
    static func pasted(_ text: String, _ separator: String) -> String {
        var scalars = Substring(text).unicodeScalars
        if scalars.last == "\n" { scalars.removeLast() }
        return scalars.isEmpty ? "" : Bash.lines(String(scalars)).joined(separator: separator)
    }

    static func ghHosts(_ env: Env) -> String {
        (Env.nonEmpty(env.vars, "GH_CONFIG_DIR") ?? ((Env.nonEmpty(env.vars, "XDG_CONFIG_HOME") ?? env.home + "/.config") + "/gh")) + "/hosts.yml"
    }

    /// `[ -s path ]`.
    static func hasContent(_ path: String) -> Bool {
        var info = stat()
        return stat(path, &info) == 0 && info.st_size > 0
    }

    // a token GitHub no longer accepts fails later, in the middle of a push or a release
    static func gh(_ run: Run) {
        let status = capture(run.shell, 20, ["gh", "auth", "status"], stdin: .null, stderr: .stdout).text
        if Bash.lines(status).contains(where: { matches(ghRefused, $0) }) {
            run.out.warn("GitHub CLI: the saved login no longer works — run: gh auth login")
        }
    }

    private static let ghRefused = try! NSRegularExpression(pattern: "token .* is (invalid|no longer valid)|authentication failed", options: .caseInsensitive)

    // MARK: helpers

    /// `$(tl seconds tool… 2>…)`: what the tool printed, trailing newlines kept, its status (124 when it was stopped,
    /// 127 when it is not there) and whether the output is UTF-8, which Python insists on; `input`, when given, is what it reads.
    static func capture(_ shell: Shell, _ seconds: Int, _ argv: [String], stdin: Shell.Input = .inherit, stderr: Shell.Out = .null,
                        input: String? = nil) -> (status: Int32, text: String, utf8: Bool) {
        var output: [Int32] = [0, 0], feed: [Int32] = [-1, -1]
        guard pipe(&output) == 0 else { return (127, "", true) }
        var source = stdin
        if let input {
            guard pipe(&feed) == 0 else { close(output[0]); close(output[1]); return (127, "", true) }
            source = .fd(feed[0])
            _ = fcntl(feed[1], F_SETNOSIGPIPE, 1)   // a tool that ends without reading all of it must not take macup along
            let writer = feed[1]
            Thread { Shell.writeText(input, to: writer); close(writer) }.start()
        }
        var data = Data()
        let drained = DispatchSemaphore(value: 0)
        // read while the tool runs: a full pipe would stop it before it ends
        Thread {
            data = FileHandle(fileDescriptor: output[0], closeOnDealloc: true).readDataToEndOfFile()
            drained.signal()
        }.start()
        let status = shell.tl(seconds, argv, stdin: source, stdout: .fd(output[1]), stderr: stderr)
        close(output[1])
        if feed[0] >= 0 { close(feed[0]) }
        drained.wait()
        return (status, String(decoding: data, as: UTF8.self), String(data: data, encoding: .utf8) != nil)
    }

    /// `(cd "$HOME" && …)`, as Updates.inHome has it for a step, around any work: PWD and OLDPWD as cd leaves them.
    static func inHome<Result>(_ run: Run, orElse failed: Result, _ body: () -> Result) -> Result {
        let shell = run.shell, saved = (pwd: shell.vars["PWD"], oldpwd: shell.vars["OLDPWD"])
        let here = open(".", O_RDONLY), herePath = FileManager.default.currentDirectoryPath
        defer {
            if here >= 0 { fchdir(here); close(here) } else { chdir(herePath) }
            shell.vars["PWD"] = saved.pwd
            shell.vars["OLDPWD"] = saved.oldpwd
        }
        var given = stat(), current = stat()
        let pwdValid = saved.pwd.map { $0.hasPrefix("/") && stat($0, &given) == 0 && stat(".", &current) == 0 && given.st_dev == current.st_dev && given.st_ino == current.st_ino } ?? false
        shell.vars["OLDPWD"] = pwdValid ? saved.pwd : herePath
        guard chdir(run.env.home) == 0 else { return failed }
        var parts: [Substring] = []
        for part in run.env.home.split(separator: "/") where part != "." {
            if part == ".." { _ = parts.popLast() } else { parts.append(part) }
        }
        shell.vars["PWD"] = "/" + parts.joined(separator: "/")
        return body()
    }

    /// `$(… | head -1)`.
    static func firstLine(_ text: String) -> String { Bash.lines(text)[0] }

    static func matches(_ expression: NSRegularExpression, _ line: String) -> Bool {
        expression.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) != nil
    }

    /// `[[ $text == prefix* ]]`, scalar by scalar (a Character can join a combining mark to the last one).
    static func starts(_ text: String, _ prefix: String) -> Bool {
        text.unicodeScalars.starts(with: prefix.unicodeScalars)
    }

    /// `sed 's/^prefix//'`
    static func dropPrefix(_ text: String, _ prefix: String) -> String {
        starts(text, prefix) ? String(String.UnicodeScalarView(text.unicodeScalars.dropFirst(prefix.unicodeScalars.count))) : text
    }

    /// Python's sorted(): stable.
    static func stableSorted<Element>(_ items: [Element], by less: (Element, Element) -> Bool) -> [Element] {
        items.enumerated().sorted { less($0.element, $1.element) || (!less($1.element, $0.element) && $0.offset < $1.offset) }.map(\.element)
    }
}

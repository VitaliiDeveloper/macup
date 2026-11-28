import Darwin
import Foundation

/// Leftovers of deleted apps (2.9's leftovers.sh). An updater lives outside its app (Application Support), so deleting the app
/// leaves it registered and its program intact. The owner is found by signing team, then by bundle-id vendor; a vendor
/// that does not match is a miss, not a removal.
extension Leftovers {
    static func scanApps(_ run: Run, _ state: State) {
        state.apps = run.env.apps.split(separator: ":", omittingEmptySubsequences: false).map(String.init).filter(Run.isDirectory).flatMap { root in
            find(run, [root, "-maxdepth", "3", "-type", "d", "-name", "*.app", "-prune"]).lines.compactMap { path -> App? in
                guard let id = raw(plist("\(path)/Contents/Info.plist"), "CFBundleIdentifier"), !id.isEmpty else { return nil }
                return App(id: lc(id), path: path)
            }
        }
        state.teamsRead = false
    }

    /// `apps_teams`: codesign is slow, so only once there is a suspect.
    static func readTeams(_ run: Run, _ state: State) {
        guard !state.teamsRead else { return }
        state.teamsRead = true
        for index in state.apps.indices { state.apps[index].team = teamOf(run, state.apps[index].path) }
    }

    static let sharedPrefixes: Set = ["uk.co", "uk.org", "au.com", "jp.co", "nz.co", "br.com", "cn.com", "io.github", "io.gitlab", "com.gitlab",
                                      "org.gitlab", "net.sourceforge", "com.googlecode", "app.netlify", "com.electron"]

    /// `vendor_of`: the first two id components; three under a shared prefix (io.github.<owner>), where two would mean many publishers.
    static func vendorOf(_ id: String) -> String {
        guard !id.isEmpty else { return "" }
        let parts = lc(id).split(separator: ".", omittingEmptySubsequences: false)
        let two = parts.count >= 2 && !parts[0].isEmpty && !parts[1].isEmpty ? "\(parts[0]).\(parts[1])" : ""
        guard sharedPrefixes.contains(two) else { return two }
        return parts.count >= 3 && !parts[2].isEmpty ? "\(two).\(parts[2])" : ""
    }

    static func vendorInstalled(_ state: State, _ vendor: String) -> Bool {
        !vendor.isEmpty && state.apps.contains { same($0.id, vendor) || Bash.starts($0.id, vendor + ".") }
    }

    static func teamInstalled(_ run: Run, _ state: State, _ team: String) -> Bool {
        guard !team.isEmpty else { return false }
        readTeams(run, state)
        return state.apps.contains { $0.team == team }
    }

    /// `in_owner_place`: places an app keeps its own helpers; /opt/homebrew, ~/.local and scripts are never judged by owner.
    static func inOwnerPlace(_ run: Run, program: String, label: String) -> Bool {
        let home = run.env.home
        if fnmatch("*/*.app/*", program, 0) == 0 || Bash.starts(program, "\(home)/Library/Application Support/")
            || Bash.starts(program, "\(run.env.sysLib)/Application Support/") { return true }
        guard Bash.starts(program, "\(home)/Library/") else { return false }
        let rest = String(decoding: program.utf8.dropFirst(home.utf8.count + 9), as: UTF8.self)
        let folder = lc(String(rest.prefix { $0 != "/" }))
        return lc(label).split(separator: ".", omittingEmptySubsequences: false).contains { same(String($0), folder) }
    }

    static func startupFiles(_ run: Run) -> [String] {
        let sys = run.env.sysLib
        return glob("\(run.env.home)/Library/LaunchAgents", "*.plist") + glob("\(sys)/LaunchAgents", "*.plist") + glob("\(sys)/LaunchDaemons", "*.plist")
    }

    static func plistName(_ file: String) -> String {
        let name = basename(file)
        return name.hasSuffix(".plist") ? String(name.dropLast(6)) : name
    }

    static func scan(_ run: Run, _ state: State) {
        guard !state.scanned else { return }
        state.scanned = true
        scanApps(run, state)
        for file in startupFiles(run) {
            guard isFile(file), !Run.isSymlink(file) else { continue }
            let base = plistName(file)
            if Bash.starts(base, "com.apple.") || base == Env.schedLabel { continue }
            let system = Bash.starts(file, run.env.sysLib + "/")
            func add(_ label: String, _ program: String, _ reason: Orphan.Reason, _ vendor: String, _ signer: String = "") {
                state.orphans.append(Orphan(plist: file, label: label, program: program, reason: reason, system: system, vendor: vendor,
                                            name: signer.isEmpty ? capitalized(lastComponent(vendor)) : signer))
            }
            guard access(file, R_OK) == 0 else { continue }   // root-only: macup cannot judge it, which is not the same as broken
            guard let root = plist(file) else { add("", "", .broken, vendorOf(base)); continue }
            let label = raw(root, "Label") ?? ""
            if Bash.starts(label, "com.apple.") || label == Env.schedLabel { continue }
            let program = raw(root, "Program") ?? raw(root, "ProgramArguments.0") ?? ""
            if label.isEmpty, program.isEmpty {
                guard (root as? [String: Any])?.isEmpty == true, !locked(file) else { continue }   // locked: some tools block an updater this way
                add("", "", .empty, vendorOf(base))
                continue
            }
            let ids = associatedIDs(root)
            var vendor = vendorOf(ids.first ?? "")
            if vendor.isEmpty { vendor = vendorOf(label.isEmpty ? base : label) }
            guard program.hasPrefix("/"), !vendor.isEmpty else { continue }   // a label like "mybackup" names no vendor: never judged
            if !exists(program) { add(label, program, .missing, vendor, signerOf(run, program)); continue }
            guard inOwnerPlace(run, program: program, label: label) else { continue }
            if (ids + [label]).contains(where: { !$0.isEmpty && vendorInstalled(state, vendorOf($0)) }) { continue }
            if teamInstalled(run, state, teamOf(run, program)) { continue }
            add(label, program, .gone, vendor, signerOf(run, program))
        }
        // an empty plist has no signer: name it like its vendor's other items
        for index in state.orphans.indices {
            let vendor = state.orphans[index].vendor
            if let named = state.orphans.first(where: { $0.vendor == vendor && exists($0.program) }) { state.orphans[index].name = named.name }
        }
    }

    /// `cap`: awk's toupper on the first character. awk's substr cuts bytes, so a name that starts with a letter beyond ASCII
    /// is an illegal byte sequence to awk in a UTF-8 locale, and it prints nothing.
    static func capitalized(_ text: String) -> String {
        guard let first = text.unicodeScalars.first, first.isASCII else { return "" }
        return Awk.upper(String(first)) + String(String.UnicodeScalarView(text.unicodeScalars.dropFirst()))
    }

    static func locked(_ file: String) -> Bool {
        var info = stat()
        return lstat(file, &info) == 0 && info.st_flags & UInt32(UF_IMMUTABLE) != 0
    }
}

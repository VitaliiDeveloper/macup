import Darwin
import Foundation

/// Data of a deleted app: only for vendors whose agent was found orphaned, so SDK ids and test bundles are never guessed at.
extension Leftovers {
    static let libraryWords: Set = ["accounts", "assistants", "audio", "autosave", "biome", "caches", "calendars", "colorsync", "colors", "compositions",
                                    "containers", "contacts", "cookies", "developer", "favorites", "fileprovider", "fonts", "frontboard", "gamekit",
                                    "homekit", "intents", "keyboard", "keychains", "logs", "mail", "maps", "messages", "metadata", "news", "passes",
                                    "photos", "preferences", "printers", "reminders", "safari", "scripts", "services", "sharing", "shortcuts", "sounds",
                                    "spelling", "spotlight", "suggestions", "translation", "trial", "weather", "webkit"]
    static let genericWords: Set = ["app", "mac", "helper", "helpers", "agent", "code", "updater", "update", "service", "services", "daemon", "data",
                                    "cache", "caches", "support", "shared", "common"]

    /// What a folder name is checked against: the installed apps' names and Apple's own.
    struct Names {
        let apps: Set<String>
        let apple: Set<String>
    }

    /// `data_cands`.
    static func registerData(_ run: Run, _ state: State) {
        let names = Names(apps: appNames(state), apple: appleNames(run))
        let vendors = sortedUnique(state.orphans.filter { $0.reason != .broken && !$0.vendor.isEmpty }.map { ($0.vendor, $0.name) }, key: \.0)
        let i18n = run.out.i18n
        for (vendor, name) in vendors where !vendorInstalled(state, vendor) {
            var seen = Set<String>()
            let found = dataPaths(run, state, names, vendor).filter { seen.insert($0).inserted }
            guard !found.isEmpty else { continue }
            let paths = found.joined(separator: "\n")
            let index = state.data.count
            state.data.append(AppData(vendor: vendor, name: name, paths: paths))
            state.allow += paths + "\n"
            var note = [i18n.format("What: settings, history, saved passwords and cookies of %s.", args: [name]),
                        i18n.format("Why: no app from %s is installed anymore.", args: [name])]
            if found.contains(where: { !find(run, [$0, "-maxdepth", "4", "(", "-name", "Login Data", "-o", "-name", "History", "-o", "-name", "Cookies", ")"]).lines.isEmpty }) {
                note.append(i18n.translate("Note: move your passwords to another browser first if you need them."))
            }
            if found.contains(where: { $0.contains("/Containers/") || $0.contains("/Group Containers/") }) {
                note.append(i18n.translate("Note: macOS may ask once for access."))
            }
            note.append(i18n.translate("Safe: yes, it goes to the Trash."))
            note += found.map { "@" + run.env.paths.tildify($0) }
            run.register(task: "clean.orphan_data", level: 3, label: "⚠ \(name) · \(i18n.translate("data of a deleted app"))", kb: run.kbl(outer(paths)),
                         kind: .cmd, paths: "odata:\(index)", info: note.joined(separator: "\n"), manual: true)
            run.candidates.list[run.candidates.list.count - 1].leftoverPaths = paths
        }
    }

    /// `data_paths`.
    static func dataPaths(_ run: Run, _ state: State, _ names: Names, _ vendor: String) -> [String] {
        let library = "\(run.env.home)/Library", support = "\(library)/Application Support"
        var paths: [String] = [], ids: [String] = []
        for folder in ["Preferences", "Caches", "HTTPStorages", "Saved Application State", "WebKit", "Logs"] {
            for entry in glob("\(library)/\(folder)", "*") where exists(entry) && !Run.isSymlink(entry) {
                let name = lc(basename(entry))
                guard name.hasPrefix(vendor + ".") else { continue }
                paths.append(entry)
                var id = name
                for suffix in [".plist", ".savedstate", ".binarycookies"] where id.hasSuffix(suffix) { id = String(id.dropLast(suffix.count)) }
                ids.append(id)
            }
        }
        for id in sortedUnique(ids, key: { $0 }) where id.split(separator: ".", omittingEmptySubsequences: false).count >= 3 && nameOK(names, lastComponent(id)) {
            paths += byName(run, state, names, support, lastComponent(id))
        }
        let short = lastComponent(vendor)
        if nameOK(names, short) { paths += byName(run, state, names, support, short) + byName(run, state, names, library, short) }
        guard state.interactive else { return paths }
        for entry in glob("\(library)/Containers", prefix: vendor + ".", "*") + glob("\(library)/Group Containers", prefix: "group.\(vendor).", "*")
            where exists(entry) && !Run.isSymlink(entry) && !devContainer(run, entry) {   // dev builds' containers are clean.dev_containers' own
            paths.append(entry)
        }
        for orphan in state.orphans where orphan.vendor == vendor && exists(orphan.program) {
            let team = teamOf(run, orphan.program)
            guard !team.isEmpty else { continue }
            paths += glob("\(library)/Group Containers", prefix: team + ".", "*").filter { exists($0) && !Run.isSymlink($0) }
        }
        return paths
    }

    /// `app_names`.
    static func appNames(_ state: State) -> Set<String> {
        Set(state.apps.flatMap { app -> [String] in
            let file = basename(app.path)
            return [lastComponent(app.id), lc(file.hasSuffix(".app") ? String(file.dropLast(4)) : file)]
        }.filter { !$0.isEmpty })
    }

    /// `apple_names`: Apple's own app and folder names, so ~/Library/Mail or Application Support/AddressBook are never taken.
    static func appleNames(_ run: Run) -> Set<String> {
        var names = libraryWords
        for folder in ["/System/Applications", "/System/Applications/Utilities", "/System/Library/CoreServices"] {
            for app in glob(folder, "*.app") where exists(app) { names.insert(lc(String(basename(app).dropLast(4)))) }
        }
        for file in glob("\(run.env.home)/Library/Preferences", "com.apple.*") where exists(file) {
            names.insert(String(lc(String(basename(file).dropFirst(10))).prefix { $0 != "." }))
        }
        names.remove("")
        return names
    }

    /// `name_ok`: a folder named like this may belong to the deleted app, not to another app or to macOS.
    static func nameOK(_ names: Names, _ name: String) -> Bool {
        !name.isEmpty && !genericWords.contains(name) && !names.apps.contains(name) && !names.apple.contains(name)
    }

    /// `by_name`: entries of a folder named like this, ignoring case, unless an installed app keeps files there.
    static func byName(_ run: Run, _ state: State, _ names: Names, _ folder: String, _ name: String) -> [String] {
        glob(folder, "*").filter { exists($0) && !Run.isSymlink($0) && lc(basename($0)) == name && !held(run, state, names, $0) }
    }

    /// `held`: a name inside the folder is an installed app's bundle id or app name, or the folder cannot all be read.
    static func held(_ run: Run, _ state: State, _ names: Names, _ folder: String) -> Bool {
        let listing = find(run, [folder, "-maxdepth", "3"])
        guard listing.status == 0 else { return true }
        let ids = state.apps.map(\.id)
        guard !ids.isEmpty else { return false }
        return listing.lines.dropFirst().contains { line in
            let name = lc(basename(line))
            return names.apps.contains(name) || ids.contains { name.contains($0) }
        }
    }
}

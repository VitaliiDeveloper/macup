import Darwin

/// 2.9's report.sh's sizes of what macup never deletes, and Video & photo (measured only).
extension Checks {
    static func sizes(_ run: Run) {
        if run.task("check.sizes") { notTouched(run) }
        if run.task("check.creative") { creative(run) }
    }

    static func mention(_ run: Run, _ size: Int64, atLeast: Int64, _ fmt: String) {
        if size >= atLeast { run.out.info(fmt, Size.hum(size)) }
    }

    static func notTouched(_ run: Run) {
        let out = run.out, home = run.env.home, dev = run.env.dev
        func list(_ paths: [String]) -> Int64 { run.kbl(paths.joined(separator: "\n")) }
        out.beginSection("Not touched by macup")
        let archives = run.measure.get(dev + "/Xcode/Archives")
        if archives > 5_242_880 {
            out.warn("Xcode Archives: %s — delete old builds in Xcode → Organizer (keep ones you need to symbolicate crashes)", Size.hum(archives))
        } else {
            mention(run, archives, atLeast: 1, "Xcode Archives: %s")
        }
        mention(run, run.measure.get(dev + "/CoreSimulator/Devices"), atLeast: 1, "Simulator devices: %s (Xcode → Window → Devices and Simulators)")
        mention(run, run.kb(home + "/.pub-cache"), atLeast: 1, "Flutter pub-cache: %s (full reset: dart pub cache clean)")
        let codex = home + "/.codex"
        mention(run, list([codex + "/sessions", codex + "/archived_sessions"] + Names.glob(codex, "*.sqlite") + [codex + "/sqlite"]), atLeast: 102_400,
                "Codex chat history: %s (not a cache; delete old chats in Codex itself)")
        mention(run, run.kb(home + "/.claude/projects"), atLeast: 102_400,
                "Claude Code chat history: %s (not a cache; Claude Code deletes transcripts older than cleanupPeriodDays, 30 days by default)")
        // the virtual machine Cowork runs in: a whole disk that Claude.app downloads again when it is gone
        mention(run, run.kb(home + "/Library/Application Support/Claude/vm_bundles"), atLeast: 1_048_576,
                "Claude Cowork virtual machine: %s (not a cache; Claude.app downloads it again if it is removed)")
        mention(run, list([home + "/.cache/huggingface", home + "/.ollama/models", home + "/.lmstudio/models"]), atLeast: 102_400,
                "AI models (Hugging Face, Ollama, LM Studio): %s")
        mention(run, list([home + "/Library/Android/sdk", home + "/.android/avd"]), atLeast: 102_400,
                "Android SDK and emulators: %s (Android Studio → SDK Manager, Device Manager)")
        mention(run, run.measure.get(home + "/Library/Caches"), atLeast: 1, "App caches (~/Library/Caches): %s — macOS trims these itself when space is low")
        mention(run, run.kb(home + "/Library/Application Support/MobileSync/Backup"), atLeast: 102_400,
                "iPhone and iPad backups: %s (Finder → your device → Manage Backups)")
        let machines = Names.glob(home + "/Library/Containers/com.docker.docker/Data/vms", "*").map { $0 + "/data/Docker.raw" }.filter(exists)
        mention(run, list(machines), atLeast: 102_400, "Docker disk image: %s (Docker Desktop → Settings → Resources; it shrinks after: docker system prune)")
        // virtual machines are whole disks: only their app knows which one is still needed
        mention(run, list([".colima", ".lima", ".local/share/containers/podman/machine", ".minikube", "Parallels", "Virtual Machines.localized"].map { home + "/" + $0 }),
                atLeast: 102_400, "Virtual machines (Colima, Lima, Podman, minikube, Parallels, VMware): %s — delete the ones you no longer use in their own app")
        // a crashed program can leave a copy of its memory in /cores, gigabytes each, and nothing ever removes them
        let cores = run.kb("/cores")
        if cores >= 102_400 { out.warn("Core dumps in /cores: %s — leftovers of crashed programs; remove them with: sudo rm /cores/core.*", Size.hum(cores)) }
        let trash = home + "/.Trash"
        if Run.isDirectory(trash), !readable(trash) {
            if !run.task("clean.trash") { out.info("Trash: cannot be read — give your terminal Full Disk Access (System Settings → Privacy & Security)") }
        } else if !run.task("clean.trash") {
            let size = run.kb(trash)
            if size > 2_097_152 { out.warn("Trash: %s — empty it", Size.hum(size)) } else { mention(run, size, atLeast: 1, "Trash: %s") }
        }
    }

    /// Their caches are rebuilt only by re-rendering, which can take hours, so macup only shows where the space is and the
    /// app's own button to clear it. Folders are read only if the app is installed.
    static func creative(_ run: Run) {
        let home = run.env.home
        func found(_ argv: [String]) -> Int64 { run.kbl(output(run, ["find"] + argv)) }
        run.out.beginSection("Video & photo")
        if Run.isDirectory("/Applications/Final Cut Pro.app"), Run.isDirectory(home + "/Movies") {
            mention(run, found([home + "/Movies", "-maxdepth", "4", "-type", "d", "-name", "Render Files", "-path", "*.fcpbundle/*", "-prune"]), atLeast: 102_400,
                    "Final Cut Pro render files: %s — Final Cut: File → Delete Generated Library Files")
        }
        let common = home + "/Library/Application Support/Adobe/Common"
        mention(run, run.kbl(common + "/Media Cache Files\n" + common + "/Media Cache"), atLeast: 102_400,
                "Adobe media cache (Premiere, After Effects): %s — Premiere: Settings → Media Cache → Delete")
        if Run.isDirectory("/Applications/DaVinci Resolve") {
            mention(run, run.kb(home + "/Movies/CacheClip"), atLeast: 102_400, "DaVinci Resolve render cache: %s — Resolve: Playback → Delete Render Cache")
        }
        if !Names.glob("/Applications", "Adobe Lightroom Classic*").isEmpty, Run.isDirectory(home + "/Pictures") {
            mention(run, found([home + "/Pictures", "-maxdepth", "4", "-type", "d", "-name", "*Previews.lrdata", "-prune"]), atLeast: 102_400,
                    "Lightroom Classic previews: %s — Lightroom: Library → Previews → Discard 1:1 Previews")
        }
        mention(run, run.kbl(Names.glob(home + "/Library/Caches", "Adobe Camera Raw*").joined(separator: "\n")), atLeast: 102_400,
                "Camera Raw cache: %s — Photoshop: Settings → Camera Raw → Performance → Purge Cache")
    }

    /// `[ -e ]` without following the last link, as bash's glob tests a name it does not match against a pattern.
    static func exists(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0
    }

    static func readable(_ folder: String) -> Bool {
        guard let handle = opendir(folder) else { return false }
        closedir(handle)
        return true
    }
}

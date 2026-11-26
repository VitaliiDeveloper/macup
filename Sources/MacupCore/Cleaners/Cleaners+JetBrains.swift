import Foundation

/// JetBrains IDEs keep one cache folder per product and version, and re-index after it is emptied. The app names differ
/// (IntelliJ IDEA, PyCharm, …), so an open IDE is found by its open files.
extension Cleaners {
    static func jetbrains(_ run: Run) {
        guard run.taskAllowed("clean.jetbrains") else { return }
        for folder in Checks.glob(run.env.home + "/Library/Caches/JetBrains", "*") where Run.isDirectory(folder) && !Run.isSymlink(folder) {
            let size = run.kb(folder)
            if size < 5120 { continue }
            run.register(task: "clean.jetbrains", level: 2, label: run.out.i18n.format("JetBrains cache (%s)", args: [(folder as NSString).lastPathComponent]),
                         kb: size, kind: .empty, paths: folder, open: folder)
        }
    }
}

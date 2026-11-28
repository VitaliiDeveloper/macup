import Darwin
import Foundation

public final class Measure {
    private struct Walk {
        let path: String
        let eachFolder: Bool
        let file: String
        var pid: pid_t?
    }

    private let shell: Shell
    private let body: String
    private var walks: [Walk] = []
    private var forgotten: [pid_t] = []
    private var started = 0

    init(shell: Shell, body: String) {
        self.shell = shell
        self.body = body
    }

    public func start(_ path: String, eachFolder: Bool = false) {
        guard Run.isDirectory(path), !Run.isSymlink(path), !has(path) else { return }
        let file = "\(body).du.\(started)"
        started += 1
        let pid = shell.spawn(eachFolder ? ["du", "-k", "-d", "1", path] : ["du", "-sk", path], stdin: .null, stdout: .file(file), stderr: .null)
        walks.append(Walk(path: path, eachFolder: eachFolder, file: file, pid: pid))
    }

    public func has(_ path: String) -> Bool {
        walks.contains { $0.path == path || ($0.eachFolder && $0.path == Measure.parent(path)) }
    }

    public func get(_ path: String) -> Int64 {
        for index in walks.indices {
            let walk = walks[index]
            let value: String
            if walk.path == path {
                finish(index)
                value = Awk.firstField(Measure.lines(walk.file).last ?? "")
            } else if walk.eachFolder, walk.path == Measure.parent(path) {
                finish(index)
                value = Measure.lines(walk.file).lazy.compactMap { line -> String? in
                    let fields = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
                    return fields.count == 2 && fields[1] == path ? String(fields[0]) : nil
                }.first ?? ""
            } else {
                continue
            }
            if !value.isEmpty, value.unicodeScalars.allSatisfy({ ("0"..."9").contains($0) }), let size = Int64(value) { return size }
        }
        return Size.kb(path, shell: shell)
    }

    public func forget() {
        forgotten += walks.compactMap(\.pid)
        walks = []
    }

    /// The pids are never reaped before this, so none can belong to another process yet.
    func stop() {
        for pid in forgotten + walks.compactMap(\.pid) { kill(pid, SIGTERM) }
    }

    private func finish(_ index: Int) {
        guard let pid = walks[index].pid else { return }
        _ = Shell.wait(pid)
        walks[index].pid = nil
    }

    /// `${path%/*}`, by scalars: a combining mark after a slash stays a name of its own, as bash sees bytes.
    static func parent(_ path: String) -> String {
        guard let slash = path.unicodeScalars.lastIndex(of: "/") else { return path }
        return String(path.unicodeScalars[..<slash])
    }

    private static func lines(_ file: String) -> [String] {
        Bash.lines(Bash.substitution(String(decoding: FileManager.default.contents(atPath: file) ?? Data(), as: UTF8.self)))
    }
}

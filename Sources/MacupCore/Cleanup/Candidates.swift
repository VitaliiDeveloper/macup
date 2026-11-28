public struct Candidate {
    public enum Kind: String { case empty, rm, trash, cmd }

    public var task: String
    public var level: Int
    public var auto: Bool
    public var label: String
    /// nil while its du still runs in the background, until settle.
    public var kb: Int64?
    public var kind: Kind
    public var paths: String
    public var proc: String
    public var measureDir: String
    public var open: String
    public var info: String
    public var key: String
    public var sudo = false
    public var leftoverPaths = ""
    public var busy = false

    public var visible: Bool {
        if task == "clean.ai_tools" || task == "clean.editor_workspaces" { return true }
        return (kb ?? 0) >= 1024 || (kind == .cmd && !auto) || task == "clean.profiles" || task == "clean.dev_containers"
    }
}

public final class Candidates {
    public var list: [Candidate] = []
    public private(set) var covered = ""

    public func cover(_ paths: String) { covered += paths + "\n" }

    /// The same item gets the same key on the next run, so --pick can name it.
    static func key(task: String, source: String) -> String {
        "\(task):\(cksum(Array(source.utf8)))"
    }

    static func cksum(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0
        func feed(_ byte: UInt8) {
            crc ^= UInt32(byte) << 24
            for _ in 0..<8 { crc = crc & 0x8000_0000 != 0 ? (crc << 1) ^ 0x04C1_1DB7 : crc << 1 }
        }
        bytes.forEach(feed)
        var length = bytes.count
        while length > 0 { feed(UInt8(length & 0xFF)); length >>= 8 }
        return ~crc
    }
}

public extension Run {
    func register(task: String, level: Int, label: String, kb: Int64?, kind: Candidate.Kind, paths: String, proc: String = "",
                  measureDir: String = "", open: String = "", info: String = "", keySource: String = "", manual: Bool = false) {
        guard taskAllowed(task) else { return }
        let source = keySource.isEmpty ? "\(kind.rawValue)|\(paths)" : keySource
        candidates.list.append(Candidate(task: task, level: level, auto: self.task(task) && !manual, label: label, kb: kb, kind: kind,
                                         paths: paths, proc: proc, measureDir: measureDir, open: open, info: info,
                                         key: Candidates.key(task: task, source: source)))
        if kind != .cmd { candidates.cover(paths) }
    }

    func registerMore(label: String, level: Int, kb: Int64, paths: String, open: String) -> Bool {
        guard let index = candidates.list.firstIndex(where: { $0.label == label && $0.level == level && $0.kind == .empty && $0.kb != nil }) else { return false }
        candidates.list[index].kb! += kb
        candidates.list[index].paths += "\n" + paths
        let before = candidates.list[index].open
        candidates.list[index].open = before + (before.isEmpty ? "" : "\n") + open
        candidates.cover(paths)
        return true
    }

    func settle() {
        candidates.list = candidates.list.compactMap { candidate in
            guard candidate.kb == nil else { return candidate }
            var sized = candidate
            let size = measure.get(candidate.kind == .cmd ? candidate.measureDir : candidate.paths)
            sized.kb = size
            return candidate.kind == .empty && size < 5120 ? nil : sized
        }
    }
}

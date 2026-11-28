@testable import MacupCore
import XCTest

/// cleanup.sh `pick`: which candidates an answer at the end of a check takes.
final class PickTests: XCTestCase {
    func testChooseIsBashPick() throws {
        // task, level, picked by a clean, KB, kind
        let rows: [(String, Int, Bool, Int64, Candidate.Kind)] = [
            ("clean.a", 1, true, 2048, .empty), ("clean.b", 2, true, 10, .empty), ("clean.orphan_agents", 3, false, 0, .cmd), ("clean.c", 3, true, 5000, .rm),
            ("clean.dev_containers", 3, false, 0, .cmd), ("clean.d", 2, false, 3000, .rm), ("clean.profiles", 1, true, 1, .rm), ("clean.orphan_data", 3, false, 4096, .cmd),
            ("clean.e", 2, true, 1024, .trash),
        ]
        let list = rows.map { Candidate(task: $0.0, level: $0.1, auto: $0.2, label: $0.0, kb: $0.3, kind: $0.4, paths: "", proc: "", measureDir: "", open: "", info: "", key: "") }
        let answers = ["", "1", "1,3", "2-5", "1-9999", "08", "0", "5-2", "safe", "standard", "aggressive", "2-2", "02-2", "3", "3-3", "zzz, 999",
                       " 1 , 4 ", "1-2-3", "-n", "12345", "4-", "1\t3", "7", "6-8", "safe,7", "Safe", "0001-0003", "10000", "8-9"]
        var prelude = BashOracle.function("visible", in: "src/cleanup.sh") + BashOracle.function("vis_index", in: "src/cleanup.sh")
            + BashOracle.function("pick", in: "src/cleanup.sh") + "ask(){ printf '%s\\n' \"$ANSWER\"; }\nC_N=\(rows.count)\n"
        for (index, row) in rows.enumerated() {
            prelude += "C_TASK[\(index)]=\(row.0); C_LVL[\(index)]=\(row.1); C_AUTO[\(index)]=\(row.2 ? 1 : 0); C_KB[\(index)]=\(row.3); C_KIND[\(index)]=\(row.4.rawValue)\n"
        }
        let bash = try BashOracle.run(answers.map { "ANSWER=\(BashOracle.quoted($0)) pick" }, prelude: prelude)
        XCTAssertEqual(bash[3], "3\n5", "2-5: the visible 2nd to 5th, without the leftover and the dev container, which only their own number takes")
        let i18n = I18n(lang: .en, translations: [:])
        for (answer, picked) in zip(answers, bash) {
            XCTAssertEqual(Pick.choose(answer, list, i18n).map(String.init).joined(separator: "\n"), picked, answer.debugDescription)
        }
    }
}

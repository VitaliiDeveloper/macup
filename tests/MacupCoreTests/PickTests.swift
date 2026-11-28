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
        // the indexes 2.9's bash pick printed for each answer
        let answers: [(String, [Int])] = [
            ("", []), ("1", [0]), ("1,3", [0, 3]), ("1-9999", [0, 3, 5, 6, 8]), ("08", [8]), ("0", []), ("5-2", []), ("safe", [0, 6]),
            ("standard", [0, 1, 6, 8]), ("aggressive", [0, 1, 3, 6, 8]), ("2-2", [2]), ("02-2", []), ("3", [3]), ("3-3", [3]), ("zzz, 999", []),
            (" 1 , 4 ", [0, 4]), ("1-2-3", []), ("-n", []), ("12345", []), ("4-", []), ("1\t3", [0, 3]), ("7", [7]), ("6-8", [6, 8]),
            ("safe,7", [0, 6, 7]), ("Safe", []), ("0001-0003", [0, 3]), ("10000", []), ("8-9", [8]),
        ]
        let i18n = I18n(lang: .en, translations: [:])
        XCTAssertEqual(Pick.choose("2-5", list, i18n), [3, 5], "2-5: the visible 2nd to 5th, without the leftover and the dev container, which only their own number takes")
        for (answer, picked) in answers {
            XCTAssertEqual(Pick.choose(answer, list, i18n), picked, answer.debugDescription)
        }
    }
}

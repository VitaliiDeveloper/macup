# AI chats and memory: implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task by task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** macup shows what AI tools keep, flags stale memory, and offers old or orphaned Claude Code chats for the
Trash, only when the user picks them.

**Architecture:**

- A new folder, `Sources/MacupCore/AIChats/`, holds one scan of Claude Code's data: the projects with their folder
  and class, the sessions with their size and age, Claude.app's records, and the memory hints.
- Two new cleaners turn that scan into manual-pick candidates.
- One new report block, plus the `check.ai_memory` task, prints it.
- Codex is size-only until the manual checks in Task 8 pass.

**Tech stack:** Swift 5.9, Foundation only, XCTest (`tests/MacupCoreTests`), shell cases (`tests/cases`, run by
`tests/run.sh`).

**Spec:** `docs/superpowers/specs/2026-11-28-ai-chats-and-memory-design.md`. Read it first; this plan does not repeat
its reasons.

## Global constraints

- **Start only after 3.0.0 is tagged** (`docs/swift-port-plan.md`, rule 7). Base the branch on what `main` is then.
- **Swift only.** `src/*.sh` is not changed. If `tests/diff.sh` still runs, the three new task ids join its list of
  tasks the bash build does not have, so a case with them is not diffed.
- **Port plan code rules:** every file under 500 lines, tests included; no single-letter names (`$0` and `_` are
  fine); KISS and DRY; no third-party packages.
- **Nothing is ever moved or deleted inside** any `memory/` folder, `MEMORY.md`, `~/.codex/memories*`, `CLAUDE.md`,
  `AGENTS.md` or `GEMINI.md`.
- **Trash only** (kind `.trash`), through the existing `Cleanup.moveToTrash`. Restoring is not supported.
- **Both cleaners register with `manual: true`, level 3.** Nothing goes without a pick, in any run.
- **Config defaults, verbatim:** `ai_chat_days = 14`, `memory_days = 60`.
- **Thresholds, verbatim:**
  - a session is busy if modified in the last 24 hours or if lsof shows a file of it open;
  - report lines appear only at 100 MB or more (`atLeast: 102_400` KB);
  - cwd lines are capped at 1 MB;
  - format guard: 7 days and one half.
- **Every user-facing English string** gets uk and ru in `src/i18n/translations.json`, then `./build.sh` regenerates
  `Sources/macup/Generated`.

## Review focus

Inputs the spec implies that no happy-path test meets, most likely to bite first. Each one gets a test in the task
named in brackets.

1. **Claude.app changed its record keys.** Records parse, but none has `cliSessionId`/`isArchived`, so nothing
   matches. Expected: no Claude Code session is offered by either task. [Task 2]
2. **A session in use while the user is picking.** It was idle at scan time, and the user resumes it before
   confirming. Expected: that path is skipped at execute time, and the rest of the candidate still goes. [Task 5]
3. **A dir whose transcripts are all gone and which holds only `memory/`, from a project that was renamed.**
   Expected: the folder is resolved through the app records, the memory is flagged "gone or moved", and nothing in it
   is offered. [Tasks 1 and 7]
4. **A dir name that differs from the `cwd` only by characters that encode to `-`.** For example, `/a.b` and `/a-b`
   both encode to `-a-b`. Expected: whichever folder exists makes the dir live. The dir is never treated as gone
   while one of its encoded `cwd`s exists. [Task 1]
5. **Symlinked `~/.claude`, `~/.claude/projects`, or a symlinked session dir.** Expected: nothing is scanned through
   the symlink, and nothing is offered from it. [Tasks 1 and 4]

---

### Task 1: Claude Code projects and sessions scan

**Files:**
- Create: `Sources/MacupCore/AIChats/ClaudeProjects.swift`
- Test: `tests/MacupCoreTests/AIChatsScanTests.swift`

**Interfaces:**
- Consumes: `AppRecords` from Task 2, only for the `cwd` fallback. Pass `fallbackCwds: [String]` so this task builds
  first.
- Produces:
  - `enum ProjectClass { case live, worktree, temporary, project, unknown }`
  - `struct ChatSession { let id: String; let dir: String; let paths: [String]; let kb: Int64; let newest: Date; let orphaned: Bool }`
    - `paths` holds `<dir>/<id>.jsonl` if present, `<dir>/<id>/` if present, and `~/.claude/file-history/<id>/` if
      present.
  - `struct ChatProject { let dir: String; let folder: String?; let kind: ProjectClass; let sessions: [ChatSession]; let memory: String? }`
    - `memory` is the `memory/` path when it holds at least one file.
  - `enum ClaudeProjects { static func encode(_ path: String) -> String; static func scan(home: String, fallbackCwds: [String]) -> [ChatProject] }`

- [ ] **Step 1: Write the failing tests.**
  - `testEncodeReplacesEveryNonAlphanumeric`: `encode("/Users/me/a.b/.claude/worktrees/x-1") == "-Users-me-a-b--claude-worktrees-x-1"`.
  - `testClassFromTranscriptCwd`: four dirs with one transcript each, whose matching `cwd` is:
    - an existing folder → `.live`;
    - a missing `…/.claude/worktrees/w` → `.worktree`;
    - a missing `/private/tmp/…/scratchpad/p` → `.temporary`;
    - a missing `$home/Projects/Gone` → `.project`.
    The first line of every transcript carries a non-matching scratchpad `cwd`, which must be ignored.
  - `testNoMatchingCwdIsUnknown`: one dir whose only `cwd` does not encode to its name → `.unknown`.
  - `testFallbackCwdResolvesMemoryOnlyDir`: one dir with only `memory/a.md`, plus a `fallbackCwds` entry that encodes
    to it and is missing → `.project`, with `memory` set.
  - `testAmbiguousEncodingPrefersExistingFolder`: the `cwd`s are `$home/a.b` (missing) and `$home/a-b` (existing),
    both in one dir → `.live`.
  - `testOutsideHomeAndTmpIsNotGone`: the matching `cwd` is `/Volumes/Ext/p`, which is missing → `.unknown`.
  - `testSessionPathsSizeAndAge`:
    - session `s1` has `s1.jsonl`, `s1/subagents/a.jsonl` and `file-history/s1/x`; `paths.count == 3`;
    - `newest` equals the newest mtime among them (set with `FileManager.setAttributes`);
    - `s2/` with no `s2.jsonl` has `orphaned == true`.
  - `testEmptyMemoryIsNil`: `memory/` exists with no files → `memory == nil`.
  - `testSymlinkedProjectsFolderScansNothing`: `~/.claude/projects` is a symlink → `[]`.
  - `testLongLineIsCapped`: a 3 MB first line with no newline, followed by a matching `cwd` line → still resolved, and
    the 3 MB line is not read whole (assert via a `maxLine` parameter of 1 MB).

- [ ] **Step 2: Run them; expect failures.**
  `swift test --filter AIChatsScanTests`. Expected: FAIL, `ClaudeProjects` not found.

- [ ] **Step 3: Implement `ClaudeProjects` in `ClaudeProjects.swift`.**
  - **Resolver:**
    1. Read transcripts newest first, then `*/subagents/*.jsonl`.
    2. Read lines with a 1 MB cap (`FileHandle`, chunked).
    3. Find every `"cwd":"…"`. A `cwd` counts if `encode(cwd) == dir`. Stop at the first one whose folder exists. If
       none exists, keep the first that matched.
    4. Then try `fallbackCwds` under the same rule.
  - **Gone counts only under** `home + "/"`, `/private/tmp/`, `/tmp/` or `/var/folders/`. Anything else that is
    missing is `.unknown`.
  - **Symlinks:** skip any symlinked dir, session dir or file.

- [ ] **Step 4: Run them; expect a pass.**
  `swift test --filter AIChatsScanTests`. Expected: PASS.

- [ ] **Step 5: Time the scan on a real home folder; it must stay near 0.2 s.**
  Run it in a throwaway test, kept out of the commit: `ClaudeProjects.scan(home: NSHomeDirectory(), fallbackCwds: [])`.
  The spec measured 0.16 s.

- [ ] **Step 6: Commit.**
  Message: "AI chats: scan Claude Code projects and sessions".

### Task 2: Claude.app records and the format guard

**Files:**
- Create: `Sources/MacupCore/AIChats/AppRecords.swift`
- Test: `tests/MacupCoreTests/AIChatsScanTests.swift` (same file; keep it under 500 lines, or split to
  `AIChatsRecordsTests.swift`)

**Interfaces:**
- Produces:
  - `struct AppSession { let ids: [String]; let archived: Bool; let title: String; let cwd: String?; let originCwd: String?; let lastActivity: Date? }`
    - `ids` holds `cliSessionId` and `lastAssistantCliSessionId`, without nils.
  - `enum AppRecords { case absent; case unreadable; case loaded([AppSession]) }`
  - `static func load(home: String, recentTranscriptIDs: Set<String>, now: Date) -> AppRecords`
    - reads `~/Library/Application Support/Claude/claude-code-sessions/*/*/*.json`.
  - `func visibleIDs() -> Set<String>`: every id of every non-archived session; empty for `.absent`.
  - `func cwds() -> [String]`: all `cwd` and `originCwd` values.

- [ ] **Step 1: Write the failing tests.**
  - `testAbsentFolder` → `.absent`.
  - `testArchivedAndVisible`: two records, one with `isArchived: true` → `visibleIDs()` holds only the other's ids.
  - `testNonObjectFileSkipped`: a file holding `[]` sits beside a valid record → `.loaded` with one session.
  - `testUnparsableFileMakesUnreadable`: a file holding `{` → `.unreadable`.
  - `testRenamedKeysMakeUnreadable`: records hold `sessionId`/`archived` but no `cliSessionId`/`isArchived` →
    `.unreadable`.
  - `testRecentTranscriptsMostlyUnmatchedMakeUnreadable`:
    - there are 4 recent transcript ids, 1 of which maps to a record;
    - one record has `lastActivityAt` within 7 days;
    - expect `.unreadable`.
  - `testRecentGuardNeedsRecentRecords`: the same transcripts, but no record active in the last 7 days → `.loaded`.

- [ ] **Step 2: Run them; expect failures.**
  `swift test --filter AIChats`. Expected: FAIL.

- [ ] **Step 3: Implement `AppRecords` in `AppRecords.swift`.**
  - Parse with the existing `JSONValue.parse(file:)`.
  - `lastActivityAt` is epoch milliseconds or ISO-8601; accept both.
  - The guard follows the spec's section "Claude.app rules apply to both tasks".

- [ ] **Step 4: Run them; expect a pass.**
  `swift test --filter AIChats`. Expected: PASS.

- [ ] **Step 5: Commit.**
  Message: "AI chats: read Claude.app session records, refuse an unknown format".

### Task 3: Tasks and config

**Files:**
- Modify: `Sources/MacupCore/Foundation/Tasks.swift`
  - after `clean.editor_workspaces`, add the two clean tasks;
  - after `check.sizes`, add `check.ai_memory`.
- Modify: `Sources/MacupCore/Foundation/Config.swift`
  - template: add after `simulator_days`;
  - `Settings`: add `aiChatDays`, `memoryDays`.
- Test: `tests/MacupCoreTests/ConfigTasksTests.swift`

**Interfaces:**
- Produces:
  - `Settings.aiChatDays: Int` (default 14);
  - `Settings.memoryDays: Int` (default 60);
  - task ids `clean.ai_chats_gone`, `clean.ai_chats_old`, `check.ai_memory`, all `on: true`.

Task texts, verbatim:

- `clean.ai_chats_gone`: "Claude Code chats of folders that are gone: worktrees, temporary folders, deleted projects (only when you pick them, to the Trash; memory stays)"
- `clean.ai_chats_old`: "AI chats older than ai_chat_days: Claude Code sessions archived in Claude.app or never opened in it (only when you pick them, to the Trash)"
- `check.ai_memory`: "AI tools: retention advice and memory that looks stale (report only)"

Template lines:

- `# Offer AI chats older than this many days (clean.ai_chats_old)` followed by `ai_chat_days = 14`;
- `# A memory file counts as untouched after this many days (check.ai_memory)` followed by `memory_days = 60`.

- [ ] **Step 1: Write the failing tests.**
  - `testAIChatSettingsDefaults`: an empty config → `aiChatDays == 14`, `memoryDays == 60`.
  - `testAIChatSettingsRead`: `ai_chat_days = 7` → 7.
  - `testNewTasksListed`: the three ids are in `Tasks.all` with the texts above.

- [ ] **Step 2: Run them; expect failures.**
  `swift test --filter ConfigTasksTests`. Expected: FAIL.

- [ ] **Step 3: Implement.**
  Parse like `simulatorDays` (`Config.num`).

- [ ] **Step 4: Run them and the whole suite.**
  `swift test --filter ConfigTasksTests`, then `tests/run.sh`. Expected: PASS. If a test compares the full task list
  or the template, update its expected text.

- [ ] **Step 5: Commit.**
  Message: "AI chats: task ids and ai_chat_days, memory_days".

### Task 4: Allowlist for chat paths

**Files:**
- Modify: `Sources/MacupCore/Cleanup/SafePaths.swift` (`aiPath`)
- Test: `tests/MacupCoreTests/CleanupTests.swift`

**Interfaces:**
- Produces: `SafePaths.aiPath` additionally allows exactly these paths:
  - `home/.claude/projects/<dir>/<uuid>.jsonl`
  - `home/.claude/projects/<dir>/<uuid>`
  - `<dir>` is `[A-Za-z0-9-]+`, `<uuid>` passes `isIdentifier`, and `<uuid>` is never `memory`.
  - Codex paths are **not** added here; Task 8 adds them.

- [ ] **Step 1: Write the failing test `testChatPathsAllowed`.**
  - Allowed:
    - `…/projects/-Users-me-app/1a2b-3c.jsonl`
    - `…/projects/-Users-me-app/1a2b-3c`
  - Refused:
    - `…/projects/-Users-me-app/memory`
    - `…/projects/-Users-me-app/memory/a.md`
    - `…/projects/-Users-me-app/1a2b-3c/subagents/x.jsonl` (too deep)
    - `…/projects/-Users-me-app`
    - `…/projects/../x.jsonl`
    - `…/projects/-Users-me-app/a.b.jsonl`
    - `…/.claude/settings.json`
    - `…/.codex/sessions/2026/01/01/rollout-x.jsonl`

- [ ] **Step 2: Run it; expect a failure.**
  `swift test --filter CleanupTests/testChatPathsAllowed`. Expected: FAIL.

- [ ] **Step 3: Implement it in `aiPath`, next to the file-history rule.**

- [ ] **Step 4: Run it; expect a pass.**
  `swift test --filter CleanupTests`. Expected: PASS.

- [ ] **Step 5: Commit.**
  Message: "AI chats: allow exactly a session's transcript and folder".

### Task 5: Per-path busy guard at execute time

**Files:**
- Modify: `Sources/MacupCore/Cleanup/Candidates.swift`
  - add the `perPathBusy` field;
  - add a `register(…, perPathBusy: Bool = false)` parameter;
  - add both tasks to `visible`.
- Modify: `Sources/MacupCore/Cleanup/Execute.swift` (in the `.rm, .trash` branch)
- Create: `Sources/MacupCore/AIChats/SessionBusy.swift`
- Test: `tests/MacupCoreTests/ExecTests.swift`

**Interfaces:**
- Produces:
  - `enum SessionBusy { static func busy(_ path: String, openFiles: [String]?, now: Date) -> Bool }`. It returns true
    when any of these holds:
    - the path, or any file under it, has an mtime newer than `now - 24h`;
    - `openFiles` is nil (lsof cannot tell);
    - a line of it equals `n<path>` or starts with `n<path>/`.
  - `Candidate.perPathBusy: Bool`. When true, Execute takes one `Cleanup.openFiles` snapshot and skips each busy path,
    counting it as skipped rather than refused.

- [ ] **Step 1: Write the failing tests.**
  - `testBusyByMtime`, `testBusyByOpenFile`, `testBusyWhenLsofUnknown`, `testIdleOldPath`: unit tests of
    `SessionBusy.busy`.
  - `testExecuteSkipsOnlyTheBusySession`:
    - a candidate with `perPathBusy: true` and two old session paths;
    - one path is touched to now just before execute;
    - expect the idle one in the Trash, the busy one in place, and no "nothing removed" error.

- [ ] **Step 2: Run them; expect failures.**
  `swift test --filter ExecTests`. Expected: FAIL.

- [ ] **Step 3: Implement.**
  - Execute filters the paths before the move loop.
  - The final "could not remove all" check must ignore the paths skipped as busy.

- [ ] **Step 4: Run them, and run `tests/run.sh`.**
  Expected: PASS, with no change for other candidates.

- [ ] **Step 5: Commit.**
  Message: "Execute: per-path busy guard for chat sessions".

### Task 6: The two cleaners

**Files:**
- Create: `Sources/MacupCore/Cleaners/Cleaners+AIChats.swift`
- Modify: `Sources/MacupCore/Cleaners/Cleaners.swift` (call after `editorWorkspaces(run)`)
- Test: `tests/MacupCoreTests/AIChatsCleanersTests.swift`
- Test: `tests/cases/ai_chats.sh`, sourced by `tests/run.sh` like the other cases

**Interfaces:**
- Consumes:
  - `ClaudeProjects.scan` and `ChatProject`/`ChatSession` (Task 1);
  - `AppRecords.load` and `visibleIDs()` (Task 2);
  - `Settings.aiChatDays` (Task 3);
  - `register(…, manual: true, perPathBusy: true)` (Task 5).
- Produces:
  - `Cleaners.aiChatsGone(_ run: Run)` and `Cleaners.aiChatsOld(_ run: Run)`;
  - `enum AIChatScan { static func load(_ run: Run) -> (records: AppRecords, projects: [ChatProject]) }`, memoized
    on `run` so the report reuses it. A cache stored on `Run` is fine.

Rules (from the spec):

- If records are `.unreadable`, register nothing for Claude Code.
- Drop any session whose id is in `visibleIDs()`.
- Drop any session where `SessionBusy.busy` holds at scan time (one lsof snapshot).

`aiChatsGone` registers up to four candidates. Each is `.trash`, level 3, `manual: true`, `perPathBusy: true`.

| Candidate | Key | Label |
|---|---|---|
| worktree | `chats_gone_worktree` | "Claude Code chats of deleted worktrees (%s)" |
| temporary | `chats_gone_tmp` | "Claude Code chats of temporary folders (%s)" |
| project | `chats_gone_project` | "Claude Code chats of folders that are gone: %s (%s)" |
| orphaned sessions, any class | `chats_orphaned` | "Claude Code session folders without their chat (%s)" |

- The project label lists the folders with `~`, comma-separated.
- Each candidate's paths are all paths of its sessions.

`aiChatsOld` registers one candidate:

- Key `chats_old`. Label "Claude Code chats older than %s days (%s)".
- It takes sessions of `.live` projects, not orphaned, with `newest` older than `aiChatDays`.

- [ ] **Step 1: Write the failing unit tests** (fake home, `makeRun` as in `LeftoversTests`).
  - `testGoneClassesBecomeSeparateCandidates`: one dir of each class → three candidates with the keys above, all
    `auto == false`.
  - `testMemoryNeverInPaths`: a gone project with `memory/a.md` → no candidate path contains `/memory`.
  - `testVisibleAppSessionNotOffered`: a gone worktree session whose id is a non-archived record → not offered.
  - `testUnreadableRecordsOfferNothing`: records hold `{` → no candidate from either task.
  - `testOldOffersOnlyArchivedOrUnknownSessions`: a live project with three sessions, all 20 days old:
    - one archived in the app;
    - one in no record;
    - one visible.
    Expect a single candidate with the first two.
  - `testOldRespectsThreshold`: `ai_chat_days = 30`, sessions 20 days old → nothing.
  - `testOrphanInUnknownDirOffered`: an unknown dir with an orphaned `<id>/` → in `chats_orphaned`.
  - `testRecentSessionNotOffered`: a gone worktree session modified 1 hour ago → not offered.

- [ ] **Step 2: Run them; expect failures.**
  `swift test --filter AIChatsCleanersTests`. Expected: FAIL.

- [ ] **Step 3: Implement.**
  - Register under the task ids from Task 3.
  - Every string goes through `format`/`translate`.

- [ ] **Step 4: Run them; expect a pass.**
  `swift test --filter AIChatsCleanersTests`. Expected: PASS.

- [ ] **Step 5: Write the black-box case `tests/cases/ai_chats.sh`.** On a fake home:
  - `macup check --only clean.ai_chats_gone,clean.ai_chats_old` lists the candidates and deletes nothing;
  - picking them (as `pick_simulators.sh` does) moves the transcripts to `$home/.Trash`;
  - `memory/a.md` and a visible session's transcript are still in place.

- [ ] **Step 6: Run the case.**
  `tests/run.sh`. Expected: the new case passes, and all others pass.

- [ ] **Step 7: Commit.**
  Message: "AI chats: offer chats of gone folders and old archived chats, on a pick".

### Task 7: Report, recommendations, memory

**Files:**
- Create: `Sources/MacupCore/AIChats/MemoryScan.swift`
- Create: `Sources/MacupCore/Checks/AIReport.swift`
- Modify: `Sources/MacupCore/Checks/Sizes.swift`
  - in `notTouched`, replace the two chat `mention` lines with `AIReport.sizes(run)`;
  - keep the Cowork VM line.
- Modify: `Sources/MacupCore/Run/MainPass.swift` (after `Checks.sizes(run)`, call `AIReport.memory(run)` when
  `run.task("check.ai_memory")`)
- Test: `tests/MacupCoreTests/AIReportTests.swift`

**Interfaces:**
- Consumes: `AIChatScan.load` (Task 6) and `Settings.memoryDays` (Task 3).
- Produces:
  - `struct MemoryHint { let file: String; let reason: Reason }`, where
    `enum Reason { case missingPath(String), untouched(days: Int), brokenIndexLink(String) }`;
  - `enum MemoryScan { static func hints(memory: String, home: String, untouchedDays: Int, now: Date) -> [MemoryHint]; static func indexChars(memory: String) -> Int }`;
  - `enum AIReport { static func sizes(_ run: Run); static func memory(_ run: Run) }`.

Lines, verbatim. Each `%s` size line is shown only at `atLeast: 102_400`.

**Under `check.sizes`:**

- "Claude Code chats: %s, of which %s in sessions archived in Claude.app and %s of folders that are gone"
- "Claude Code chats older than 7, 14, 30 days: %s, %s, %s (ai_chat_days = %s frees %s)"
- "Codex chats: %s, archive %s (oldest %s days); Codex does not delete old chats"
- "Codex generated images: %s; Codex logs: %s"

**Under `check.ai_memory`:**

- "Claude Code deletes chats older than %s days when it starts (cleanupPeriodDays), including sessions still shown in Claude.app"
  - Read `cleanupPeriodDays` from `~/.claude/settings.json`; use 30 when it is absent.
  - Before writing this line, confirm the setting's current behaviour in the Claude Code docs. If it differs, fix the
    text, not the logic.
- For each visible session older than `ai_chat_days`: "Still shown in Claude.app, %s days old: %s (%s) — archive it there; macup offers archived chats on the next run"
- For each `.project`-class project with memory: "Memory of a folder that is gone: %s — if the project was renamed or moved, move %s into the new project's folder in ~/.claude/projects"
- For each project with hints: "Memory that may be stale in %s: %s — ask the agent there to review its memory, or edit it with /memory". The second `%s` is the hint list, for example `a.md (path gone: ~/x), b.md (untouched 90 days)`.
- For each memory index over 2000 characters: "Memory index of %s: %s characters, about %s tokens in every session"
- If `~/.codex/memories*` totals more than 0: "Codex memory: %s (Codex consolidates it itself)"

- [ ] **Step 1: Write the failing tests.**
  - `testMissingPathHint`: a memory file mentions `~/nope/file` and `/Users/x/also-nope` → two `missingPath` hints;
    an existing path → no hint.
  - `testUntouchedHint`: a file with an mtime 61 days ago and `untouchedDays: 60` → `untouched(days: 61)`.
  - `testBrokenIndexLink`: `MEMORY.md` links `[x](gone.md)` → `brokenIndexLink("gone.md")`.
  - `testSizesLineCountsArchivedAndGone`: a fake home with 150 MB of transcripts, split between archived, gone and
    visible sessions → the line shows the right three sizes. Create the bytes with sparse files, or lower the
    threshold through a parameter.
  - `testGoneProjectMemoryFlaggedOnlyForProjectClass`: worktree and temporary dirs with memory produce no "gone"
    line; a project-class dir does.
  - `testVisibleOldSessionListed`: a visible session 20 days old with `ai_chat_days = 14` → its title appears in the
    line.

- [ ] **Step 2: Run them; expect failures.**
  `swift test --filter AIReportTests`. Expected: FAIL.

- [ ] **Step 3: Implement.**
  - The path regex: `(~|/Users/[^/\s]+)/[\w./-]+`, with trailing `.,)` stripped.
  - Write the lines with `run.out.info`.

- [ ] **Step 4: Run them, then the whole suite.**
  `swift test`, then `tests/run.sh`. Expected: PASS. Expected texts that held the two old chat lines are updated.

- [ ] **Step 5: Add uk and ru for every new string, from Tasks 3, 6 and 7.**
  Edit `src/i18n/translations.json`, then run `./build.sh`. `tests/translations.py` must pass, and so must
  `./build.sh --check`.

- [ ] **Step 6: Commit.**
  Message: "AI chats: sizes, retention facts and stale memory in the report".

### Task 8: Manual checks, then decide what Codex offers

The tool's own behaviour can't be tested on fake data. Steps 1 to 3 are done by hand on a real Mac and recorded in
the spec.

**Files:**
- Modify: `docs/superpowers/specs/2026-11-28-ai-chats-and-memory-design.md` (record the results)
- Modify, only if Step 2 or 3 passes:
  - `Sources/MacupCore/Cleanup/SafePaths.swift`
  - `Sources/MacupCore/Cleaners/Cleaners+AIChats.swift`
  - `tests/MacupCoreTests/AIChatsCleanersTests.swift`
  - `Sources/MacupCore/Foundation/Tasks.swift` (the `clean.ai_chats_old` text)

- [ ] **Step 1: Claude.app.**
  1. Archive a throwaway session in Claude.app.
  2. Move its transcript to the Trash with macup.
  3. Unarchive the session.

  Pass: the app does not crash, and other sessions still open. Fail: narrow `aiChatsOld` and `aiChatsGone` to
  sessions in no record, add a test for that, and note it in the spec.

- [ ] **Step 2: Codex `archived_sessions`.**
  1. Move one old archived rollout file away.
  2. Open Codex's archive list and two other threads.

  Pass: everything opens.

- [ ] **Step 3: Codex `sessions/`.**
  Same as Step 2, using a file in `sessions/YYYY/MM/DD/` and the thread list.

- [ ] **Step 4: For each folder that passed, wire it in.** Follow the spec's Codex rules.
  - Add its exact path to `aiPath` with a test, as in Task 4.
  - Remove its glob from `SafePaths.never`, for that exact shape only.
  - Add a key (`codex_archive_old` or `codex_sessions_old`) to `aiChatsOld`, older than `aiChatDays`.
  - Append "and Codex chats" to the task text, plus uk and ru.
  - Change the report line to "macup offers them under clean.ai_chats_old".

- [ ] **Step 5: Run everything.**
  `swift test`, `tests/run.sh`, `./build.sh --check`. Expected: PASS.

- [ ] **Step 6: Commit.**
  Message: "AI chats: results of the manual checks; Codex <folders> offered" (or "kept report-only").

### Task 9: Docs

**Files:**
- Modify: `README.md` (the task list and config keys, wherever existing tasks are listed)
- Modify: `CHANGELOG.md` (an entry for the next release after 3.0.0)

- [ ] **Step 1: Document the three tasks and two keys, with one sentence on what is never touched.**
  Use the texts from Task 3.

- [ ] **Step 2: Check the build and the docs.**
  `./build.sh --check`. Expected: PASS.

- [ ] **Step 3: Commit.**
  Message: "Docs: AI chats and memory".

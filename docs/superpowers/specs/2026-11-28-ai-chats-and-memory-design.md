# AI chats and memory: show, recommend, clean

Size: a project. Targets the Swift build after 3.0.0: the port plan freezes features until then
(`docs/swift-port-plan.md` on `swift/main`, rule 7). The bash build does not get it.

## Why

Chats of AI coding tools fill the disk faster than anything macup cleans today, and the tools do not clean them
reliably. Measured on the author's Mac, 2026-11-28:

| Where | Total | Older than 7 d | 14 d | 30 d |
|---|---|---|---|---|
| `~/.claude/projects` (Claude Code) | 4.87 GB | 4.14 GB | 0.70 GB | 0.33 GB |
| `~/.codex/sessions` | 0.25 GB | 0.21 GB | 0.21 GB | 0.09 GB |
| `~/.codex/archived_sessions` | 1.18 GB | | | 1.17 GB (older than 90 d) |

- **Claude Code prunes only when it starts** (`cleanupPeriodDays`, 30 days by default). No main transcript here is
  older than 30 days. The 245 older files are subagent transcripts of 34 sessions whose main transcript is recent
  (resumed sessions), so they go with their session. If Claude Code is not launched for a while, nothing is pruned.
- **Codex never prunes** its archive.
- **4.28 GB of the 4.87 GB belong to sessions already archived in Claude.app.** Only 0.57 GB belong to sessions still
  shown in its sidebar. Claude.app keeps one JSON per session in
  `~/Library/Application Support/Claude/claude-code-sessions/<account>/<org>/local_<id>.json` with `isArchived`,
  `cliSessionId`, `lastAssistantCliSessionId`, `lastActivityAt`.
- 212 project folders in `~/.claude/projects` (1.8 GB) belong to a folder that no longer exists: 187 deleted
  worktrees (1.2 GB, none with memory), 23 temporary folders (20 MB), 2 real projects (557 MB, both with memory). One of
  them, IsThatRight, was not deleted but renamed to Akurat: its memory is now attached to nothing.
- In a sample of the largest transcripts, about half the bytes are base64 screenshots.

The owner also wants memory kept useful. Stale memory costs few tokens (the largest `MEMORY.md` index is 2.5 K
characters, about 600 tokens per session), but it makes the agent act on facts that are no longer true.

## Goals

1. **Show** what AI tools keep, per tool and kind, with what a chat age threshold would free.
2. **Recommend** what to change in the tools themselves, and which memories look stale.
3. **Offer** chats for removal, only when the user picks them, to the Trash, with a user-set age threshold. This
   works whether or not the tool would prune them later.

## Non-goals

- Compressing chats into an archive. The owner chose the Trash: old chats are not reread (Claude Code already deletes
  them after 30 days), and a compressed chat cannot be resumed anyway.
- Rewriting transcripts in place, for example stripping screenshots. The format is internal and undocumented, and the
  change loses data.
- Cursor and VS Code chats inside `state.vscdb`. Those of gone workspaces are already covered by
  `clean.editor_workspaces`.
- Editing memory, or reviewing it with an LLM. That may come later if the report shows it is needed.
- Changing tool settings. macup only says which setting to change.
- Restoring a chat from the Trash to its place.

## Anti-goals

- **Losing memory.** Nothing under any `memory/` folder is ever moved, deleted or edited. Neither is `MEMORY.md`,
  `~/.codex/memories*`, `CLAUDE.md`, `AGENTS.md` or `GEMINI.md`.
- **Deleting a chat the user still sees.** Transcripts of a Claude.app session that is not archived are never offered,
  whatever their age.
- **Deleting a running session.** Claude Code is almost always running on the owner's Mac. Skipping the whole cleaner
  while any `claude` process runs, as the other AI cleaners do (`claudeBusy`), would mean it never runs. Busy is
  therefore decided per session (see Safety).
- **Removing anything without a pick**, including in unattended runs: schedule, `--quiet`, `--json`, no terminal.

## Approaches

- **A. Report and recommendations only.** Zero risk, but it frees nothing.
- **B. Report, recommendations, and opt-in Trash for safe classes of chats, with a user age threshold (picked).** The
  owner asked for B, then for the age threshold so space can be freed before the tools do it, or when they never do.
- **C. B plus an LLM review of memory** (`claude -p` over suspect memories, changes shown before they are applied).
  Deferred: it costs tokens, depends on the CLI, and edits files the agents own.

Owner's choice for old chats of live projects: **Trash**, not a compressed archive.

## Design

### Unit: a session

A Claude Code session is:

- `~/.claude/projects/<dir>/<id>.jsonl`;
- `~/.claude/projects/<dir>/<id>/` (holds `subagents/`, `tool-results/`, `workflows/`);
- `~/.claude/file-history/<id>/`, when present. Already a candidate of `clean.ai_tools` once the transcript is gone.
  Taking it with the session means one pick frees it all.

A session's age is the newest mtime of any file in it.

A session is **orphaned** when `<id>/` exists without `<id>.jsonl`.

A Codex session is one rollout file:

- `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`;
- `~/.codex/archived_sessions/rollout-*.jsonl.zst`.

### Project folder of a Claude Code dir

Read the `cwd` values from the dir's `.jsonl` files (subagent ones included). Take the first `cwd` whose encoding
equals the dir name. The encoding replaces every character outside `[A-Za-z0-9]` with `-`. The dir name alone cannot
be decoded, and the first `cwd` of a session is often a scratchpad.

When no transcript gives one, fall back to the Claude.app records: their `cwd` and `originCwd`, under the same
encoding rule. App records outlive the transcripts. Without this fallback, a dir left with only `memory/` would
become unknown for good, and the "gone or moved project" memory flag could never fire for it. `~/.claude.json` is no
help: it drops projects that are gone.

**Bound:** read the newest transcripts first, then the subagent ones. Lines are capped at 1 MB, and reading stops at
the first match. On the owner's Mac this resolves 291 of 295 dirs in 0.16 s, reading 4 MB. `check.sizes` runs in
every scheduled check, so the resolver must stay within this bound.

A dir still without a match is **unknown**, and its chats are never offered. Orphaned sessions are the one exception
(see New tasks).

The project is **gone** when that folder does not exist. As in `clean.editor_workspaces`, only folders in the home
folder or under `/private/tmp` (and `/tmp`, `/var/folders`) count. A folder elsewhere may be on a disk that is not
mounted.

Each gone project falls into one class:

- **worktree:** the path contains `/.claude/worktrees/`;
- **temporary:** the path is under `/private/tmp`, `/tmp` or `/var/folders`;
- **project:** anything else.

### New tasks

Both are opt-in by pick (`manual: true`), level 3, kind `.trash`, on by default, like `clean.editor_workspaces`.

| Task id | Text |
|---|---|
| `clean.ai_chats_gone` | Claude Code chats of folders that are gone: worktrees, temporary folders, deleted projects (only when you pick them, to the Trash; memory stays) |
| `clean.ai_chats_old` | AI chats older than `ai_chat_days`: Claude Code sessions archived in Claude.app or never opened in it, archived Codex chats (only when you pick them, to the Trash) |

**Claude.app rules apply to both tasks.** The app records are read once, before either task runs:

- A session that belongs to a Claude.app session that is not archived is never offered, by either task.
- If the records folder exists but cannot be read, neither task offers any Claude Code session. Codex is not affected.
- **Format guard.** "In no app record" fails open: if Claude.app renamed its keys, every record would still parse,
  no transcript would match one, and visible sessions would be offered by age. So treat the records as unreadable
  when either holds:
  - the folder holds session records but none has `cliSessionId` and `isArchived`;
  - fewer than half of the transcripts modified in the last 7 days map to a record, while records exist that were
    active in those 7 days (`lastActivityAt`).

Example: on the owner's Mac, 2 sessions still shown in the sidebar have a `cwd` that is gone. They stay.

`clean.ai_chats_gone` offers up to four candidates: one for each class of gone project, plus orphaned sessions. Each
is labelled with its count and size. An orphaned session (`<id>/` with no `<id>.jsonl`) cannot be resumed, so it is
offered even when its dir is unknown. It is still subject to the app and busy rules. For the **project** class, the label names the folders, so a renamed project is
noticed before the pick. Its memory stays in place, and the report flags it (see Memory).

`clean.ai_chats_old` offers:

- **Claude Code sessions older than `ai_chat_days`** in projects that still exist. A session counts only if its id
  (`cliSessionId` or `lastAssistantCliSessionId`) belongs to an archived Claude.app session, or to none.
  - No `claude-code-sessions` folder (Claude.app never used): every session is in no app record.
  - The folder exists but any file in it cannot be read or parsed as a session: offer no Claude Code session. Never
    guess. Files that parse to something other than an object are skipped, not errors.
- **Codex `archived_sessions` and `sessions/` files older than `ai_chat_days`.** Each one is offered only after the
  builder confirms that Codex handles a missing rollout file in it (see "Left to the builder"). Until then it is
  report-only. Codex keeps its own index of threads (`session_index.jsonl`, `state_5.sqlite`,
  `thread_history_1.sqlite`), so a missing file may leave a broken entry in it.

A session that is gone already belongs to `clean.ai_chats_gone` and is not offered twice.

### Config

| Key | Meaning |
|---|---|
| `ai_chat_days = 14` | Age threshold for `clean.ai_chats_old`. Parsed like `simulator_days` (`Config.swift`). |
| `memory_days = 60` | When a memory file counts as untouched (report only). |

The 14-day default is a design call, not the owner's. On the owner's Mac it frees 0.70 GB today and most of
the 4.1 GB a week later. Setting it to 7 frees 4.14 GB now.

### Safety

- **Allowlist** in `SafePaths.swift`, exactly one entry deep, like the file-history rule (`cleanup.sh:26-31` in bash).
  Any symlink on the way is refused. `memory` never matches.
  - `~/.claude/projects/<dir>/<uuid>.jsonl`
  - `~/.claude/projects/<dir>/<uuid>/`
  - `~/.claude/file-history/<uuid>/`
  - `~/.codex/archived_sessions/rollout-*`
  - `~/.codex/sessions/<yyyy>/<mm>/<dd>/rollout-*`

  The existing deny rules for `*/.claude/*` and `*/.codex/sessions*` stay for everything else.
- **Per-session busy:** a session modified in the last 24 hours, or with any file open by a process (`lsof +D` on
  candidates only), is skipped. The whole-tool `proc:` pattern is not used for these two tasks.
- **Trash only**, through the existing mover. The Trash total is already reported apart.
  - The owner decided, 2026-11-28, that the Trash is only there to be emptied: restoring a chat is not supported.
  - Pieces of one session land in the Trash under their own names (`<id>.jsonl`, `<id>`, `<id> 2`), and Finder's
    "Put Back" will not work. That is accepted.

### Report (`check.sizes`)

Replace the two chat lines in "Not touched by macup" with an **AI tools** block. Each line is shown only above
100 MB, as today.

- **Claude Code:**
  - chats total;
  - of that, sessions archived in Claude.app;
  - of projects that are gone;
  - what `ai_chat_days` frees now, plus the 7, 14 and 30 day figures.
- **Codex:** sessions, archive (with its age), `generated_images`, `logs_*.sqlite`.
- **Claude Cowork VM:** existing line, unchanged.

### Recommendations

These and the memory report run under a new task, `check.ai_memory`. It is on by default, with the text "AI tools:
retention advice and memory that looks stale (report only)". Users can turn it off without losing the size lines
from `check.sizes`. This is a design call.

They are printed as `info` lines with the exact place to change:

- **Old sessions still shown in Claude.app.** These are sessions that are not archived and are older than
  `ai_chat_days`. Show each one's title and size, then: "archive them in Claude.app; macup offers archived chats on
  the next run". macup never sets `isArchived` itself, because that file is the app's internal data. Added on the
  owner's approval, 2026-11-28.

- **Claude Code retention, as information, not advice.** State Claude Code's `cleanupPeriodDays` (from
  `~/.claude/settings.json`, 30 when absent), and that Claude Code deletes chats older than that at its own start.
  It does not know about Claude.app's archive, so sessions still shown in the sidebar go too.
  - macup does not suggest lowering it to `ai_chat_days`: that would do exactly what the anti-goal forbids macup to
    do.
  - The builder confirms the setting's current behaviour in the Claude Code docs before writing the text.
- **Codex.** "Codex does not delete old chats." Once a Codex folder is offered (see above), add "macup offers them
  under `clean.ai_chats_old`".

### Memory (report only)

For each `~/.claude/projects/<dir>/memory/` that holds at least one file. On the owner's Mac, 24 of 39 are empty.

- **Gone or moved project:** the project folder is gone (see above), so this memory is no longer loaded. This covers
  the **project** class only; worktrees and temporary folders are not flagged. Show the old
  path and: "if the project was renamed or moved, move this folder to the new project's folder in
  `~/.claude/projects`".
- **Stale hints**, per file:
  - absolute or `~/` paths in the text that no longer exist;
  - not modified for `memory_days`;
  - index lines in `MEMORY.md` that point to a missing file.
- **Index size** in characters, with a rough token count (characters ÷ 4).
- **Recommendation:** when a project has any stale hint, suggest asking the agent in that project to review its
  memory, or editing it through `/memory`. `/consolidate-memory` is a plugin skill and not part of every install, so
  it is not named.

Codex: show the size of `~/.codex/memories*`. Codex consolidates on its own, so there is no advice.

Gemini: none. `GEMINI.md` is one file the user writes.

## Left to the builder

- **Verify Claude.app** with an archived session whose transcript was moved to the Trash: unarchiving it must not
  crash the app or lose other sessions. If it misbehaves, narrow `clean.ai_chats_old` to sessions in no app record and
  say so in the doc.
- **Verify Codex** separately for `sessions/` and for `archived_sessions`. Remove a rollout file from each, then check
  that the thread list and the archive list still open, and that other threads still work. Each result decides whether
  that folder is offered or stays report-only.
- **Tests** for each rule, on fake home folders, as in the existing suite. In particular:
  - memory untouched;
  - non-archived app session kept;
  - app records with renamed keys: nothing offered (format guard);
  - busy session kept;
  - unknown `cwd` kept;
  - renamed project flagged, not silently taken with its memory.
- **i18n strings** for uk and ru.
- **Exact wording, and the order of lines in the report.**

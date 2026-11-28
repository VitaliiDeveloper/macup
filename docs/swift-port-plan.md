# Porting macup to Swift

Status: in progress. Phases 0 to 2 are merged; phase 3 and the phase 5 parts that do not wait for phase 4 are under way. Integration branch: `swift/main`. Everything for the port lands there. `swift/main` reaches `main` in one final pull request and ships as 3.0.0.

## Why

macup is about 3,100 lines of bash 3.2 in `src/*.sh`, built into one `macup` file. It works, and `tests/run.sh` (211 black-box tests on throwaway home folders) proves it. But the code is hard to read, and it has whole classes of bugs a compiler would stop:

- global variables clobbering each other (a cleaner's `G` overwrote the green colour);
- nested heredocs breaking the build;
- `grep -q` under `pipefail` reading a match as "no".

Swift fits this tool:

- A prebuilt universal binary runs on a fresh Mac with no Command Line Tools: the Swift runtime ships with macOS since 10.14.4.
- Native APIs replace text parsing: `FileManager`, `PropertyListSerialization`, `Process`.
- Strict types and one owner per piece of state.

Non-goals: new features, changed task ids or config keys. 3.0.0 behaves like 2.9.x, apart from the changes listed under "Intended differences".

## Ground rules

1. **Behaviour is the spec.** Two tests define it:
   - `tests/run.sh`, adapted so it runs either build;
   - a differential harness that runs bash and Swift on the same fixture and diffs the output.

   Both pass at every merge into `swift/main`.
2. **The bash build is the oracle and stays whole.** On `swift/main`, `src/*.sh` changes only by bash fixes merged from `main`. Swift never calls into pieces of it.
3. **Whole runs are routed, never split.** The Swift binary runs a command or a run itself only when every task it would touch is ported. Otherwise it hands the whole run to the embedded bash build (see "Routing"). Nothing ships half and half: the hybrid exists only on `swift/main`, for testing.
4. **Nothing is ported blind.** A unit counts as done when the runs that cover its tasks go through Swift and pass both tests.
5. **Sequential where pieces depend on each other, parallel where they do not.** A parallel wave starts only after the work it builds on is merged into `swift/main`.
6. **Foundation only:** Swift 5.9 tools, macOS 13 deployment target, no third-party packages.
7. **`main` is frozen for features** until 3.0.0. Critical fixes still go to `main`. Each fix is merged into `swift/main` and adds a line to "Bash fixes to carry over". A unit that ports the touched code ticks its line. This list is a checklist item on every merge (see "Every pull request").
8. **Code rules (owner, 2026-11-26).** KISS and DRY come first: the plainest code that does the job, no copy-paste, no layer added for later. Every file stays under 500 lines, test files included. No single-letter names, whether variables, loop indices, closure or function parameters, or struct fields; `$0` and `_` are fine. These rules cover everything written for the port: Swift, tests and the shell harness. `src/*.sh` is exempt because it is the oracle (rule 2) and is deleted in phase 4.

## Routing

From phase 0 on, the Swift binary is the `macup` entry point. It carries the built bash script.

**Routing rule.** The binary resolves the command and the task selection (`--only`, `--skip`, `--enable`, the config, the defaults). It runs itself only if the command is ported and every selected task is in the ported set. Otherwise it runs bash for the entire invocation. The suite's 94 `--only` runs give per-unit granularity for free. Full runs switch to Swift when the last unit lands.

**How bash runs.** Through `execve`, not `Process`, so the process keeps its pid and its terminal:

1. Write the script to a temporary file.
2. Open it on a spare descriptor (not 3 or 4, which the script itself uses).
3. Unlink the file.
4. `exec /bin/bash /dev/fd/N args…`

This keeps `$$` for the lock and the watchdogs, signal delivery (the suite kills the pid it started), the terminal for questions and the pick, and exit codes. It leaves no temporary file behind.

**Self path.** `MACUP_SELF=<real path of the binary>` is exported before the exec, and the bash build reads it wherever it uses `$0`. That covers `resolve_self` → `brew_prefix`, `update_cmd`, `self_update`, `schedule` and `uninstall`. This is the only change to `src/*.sh` that the port itself makes, and it lands in phase 0.

**Self-update and schedule stay off under the hybrid.** Until phase 5, `self-update` and `schedule` go through bash only on the bash build. On the Swift build they print "not available in this build". The bash `self_update` would install a script over the binary, and the bash `schedule` writes `/bin/bash <binary>` into the LaunchAgent.

## Parity

The differential harness lives in `tests/diff.sh` (phase 0). For every case it runs both builds on identical fixtures and fakes, in all three languages, with and without a terminal (through `script`). It diffs:

- stdout and stderr, captured together on one descriptor as macup writes them;
- the report file;
- `--json`;
- the exit status;
- the files left in the fake home.

**Normalised before diffing:** dates and times, "took Xm Ys", `seconds`, report file names, temporary paths and pids. The transient `step` and `tick` lines on a terminal are dropped.

**Must match exactly.** Each of these gets an XCTest against values captured from bash:

- **JSON.** Written by hand: fixed key order, control characters deleted, no `\/` (core.sh `jstr`, summary.sh). `JSONEncoder` is not used for output.
- **Candidate keys.** `cksum` of the paths in the order `find` gives (cleanup.sh `cand`). Port `cksum` (the POSIX CRC) and keep the order.
- **Widths.** `pad` and `ulen` count Unicode scalars, not grapheme clusters.
- **Sizes.** `hum`, `tokb` and `tokb10` follow awk's number parsing and `%.1f`.
- **Sorting.** It follows the locale where bash uses plain `sort` (for example `data_cands`) and `LC_ALL=C` where bash says so.
- **Sizes on disk and file ages.** They come from `du -k` and `find -mtime`, called as tools, not re-implemented.

**Intended differences** are listed here and nowhere else. Each one is a deliberate change, has a test, and goes into the 3.0.0 CHANGELOG:

- Sections that bash runs only `if have python3` (npm globals, skills, plugins, simulators, outdated apps, the Electron layout scan, editor workspaces) run on every Mac in Swift.
- Found in phase 1 (PR #10), accepted as they are:
  - a run killed by a signal it does not trap (SIGKILL from the watchdog, a crash) prints `Killed: 9`, not bash's long job line;
  - a malformed line in history.csv reads as 0 instead of aborting the run;
  - when no temporary file can be made, the run exits 1 instead of going on without a report body;
  - tools no longer inherit `MACUP_SELF`, `SHLVL`, `_` or fds 3 and 4;
  - `sw_vers` and `xcode-select -p` run only when something uses them.
- Found in wave A, checks unit (PR #11):
  - where bash leaves a tool's stderr alone (uptime, the second `pmset -g batt`, `date -j`), it is dropped;
  - a `[ x -lt n ]` on a non-integer takes the same branch without bash's `integer expression expected` line;
  - an empty `sysctl -n hw.memsize` reads as 0 GB instead of ending the run with a syntax error;
  - `stale_project_days` written with leading zeros ("007") shows as 7 in the `--deep` tip;
  - a `grep -q` under pipefail that SIGPIPE could turn into "no" gives the intended answer;
  - xargs batch sizes for the old Downloads follow BSD xargs approximately, which decides only how du counts a hard link shared across batches.
- Found in wave A, updates unit (PR #12): a step-timeout warning in a step run from the home folder (agent skills, each Claude Code plugin update) counts once in the summary, `--json` and history, and the section header prints once; bash runs those steps in a subshell, loses the warning from the counts and can print the header twice.
- Found in wave A, `check.macos_updates` (PR #14): `softwareupdate -l` output that is not UTF-8 is read on where bash's sed stops at that line, and output past about 64 KiB with no labels cannot turn into a SIGPIPE status.
- Found in wave B, cleaners unit (PR #18):
  - `clean.profiles` also runs without python3 (the python3 gate above);
  - the Claude Code edit-backup and Grok checks (`printf … | grep -qxF` under pipefail) give the intended answer past about 1,770 sessions, where SIGPIPE makes bash offer live sessions' backups for the Trash. Worth a fix on `main` too: `grep -xF … >/dev/null`, as cleaners.sh:464 does.
- Found in wave B, tools unit (PR #17):
  - the python3 gate above also covers simulator runtimes, the commands check, signing certificates and crash reports;
  - tool output that is not UTF-8 shows U+FFFD where bash prints the raw bytes; counts and the report's command output are the same;
  - `| head -1` on `flutter`, `codex` and `xcodebuild`: Swift reads the tool to its end instead of stopping it with SIGPIPE, same text;
  - the Python version comes from `python3 -c "import platform; …"`, so it differs only on a python3 older than 3.6.

## Layout

```
Package.swift
Sources/macup/                  main.swift: routing, the bash exec
Sources/MacupCore/
  Foundation/                   Env, Shell, Output, I18n, Config, Tasks, Paths, Size, Lock, Report, JSON
  Run/                          the main pass, the summary, trends, --json, signals, sudo
  Cleanup/                      candidate model, safe_path, measuring, settle; later exec and pick
  Checks/ Updates/ Tools/ Cleaners/ Leftovers/ Commands/
  Ported.swift                  the ported set, assembled from one list file per module (no shared edits)
Sources/macup/Generated/        LegacyScript.swift, Translations.swift (written by build.sh, not committed)
Tests/MacupCoreTests/           XCTest
tests/run.sh, tests/diff.sh     black-box suite and differential harness
```

**Built files are not committed on `swift/main`.** `macup` and `macup.sha256` are untracked there and built in CI, so parallel pull requests do not conflict on a 300 KB generated file. When `main` is merged in, a change to them on `main` is resolved by keeping them deleted, and the `src/` change comes in as usual. Phase 5 puts the root `macup` back as the bootstrap.

## Foundation (phase 0)

| Piece | Replaces | Must get right |
|---|---|---|
| `Env` | top of `core.sh` | `HOME` from the environment, never `homeDirectoryForCurrentUser` (it ignores `HOME` and would break every fake-home test); `PATH` with Homebrew prepended unless `MACUP_PATH=keep`; every hook: `MACUP_REPO`, `MACUP_LANG`, `NO_COLOR`, `MACUP_STEP_SECS`, `MACUP_APPS`, `MACUP_SYSLIB`, `XDG_CONFIG_HOME`; the `LC_CTYPE` export; refusing to run without `HOME` or under sudo |
| `Shell` | `run`, `tl`, `have`, `tick` | tools found through `PATH`, never fixed paths, so the fakes win; output of a command on one descriptor; `tl` semantics exactly: the command stays in the terminal's foreground group, a watchdog stops it and its descendants (found through `ps`) after `step_timeout_minutes`, 124 when stopped. A new process group would take Ctrl-C and sudo prompts away from it |
| `Output` | `ok`, `info`, `warn`, `err`, `step`, `section`, `md`, `detail`, colours | byte-identical lines; the lazy section header (`PENDING`, `SEC`); `IT_N` numbering of items and of `.det` lines; colours only on a terminal and without `--no-color` |
| `I18n` | `_`, `_f`, `translations.json` | `printf` semantics for `%s`, `%d` and `%%`, and the same fallback to English |
| `Config`, `Tasks` | `load_conf`, `conf`, `conf_set`, the task table, `task_allowed`, `task`, groups, unknown ids | same file, same keys, same errors |
| `Paths`, `Size` | `expand`, `tildify`, `kb`, `hum`, `tokb`, `tokb10` | as under "Parity" |
| `Lock`, `Report` | `unlock`, `tidy_own`, report naming | the same lock protocol (a folder and a pid file), so a 2.9 scheduled run and a 3.0 run still exclude each other |
| `JSON` | `jstr`, `jlines`, `jarr` | byte-identical to bash |

Only the data types are frozen after phase 1's vertical slice. `Shell` keeps evolving until `updates` has used its sudo and timeout paths.

## Phases

Each unit is one session working in its own worktree, on a branch `swift/<unit>` cut from `swift/main`, with one pull request into `swift/main`. The coordinator (the session that wrote this plan) starts the sessions, reviews, merges and keeps this file current. Sessions never merge into `swift/main` themselves.

### Phase 0: foundation and test harness (one session)

- **`Package.swift` and `build.sh`.** `build.sh` keeps building the bash script, then runs `swift build`. `./build.sh --check` covers both.
- **The bash exec and `MACUP_SELF`** as under "Routing", plus the routing rule with an empty ported set.
- **The foundation pieces** above, with XCTest for the pure parts.
- **`tests/run.sh` runs either build.**
  - Replace the 108 `/bin/bash "$M"` calls and the 7 `/bin/bash "$H/…/macup"` calls with one `macup_run` helper. It runs `/bin/bash macup` for the bash build and the binary directly for the Swift build.
  - Tag the tests that only make sense for the script and skip them on the Swift build: `build.sh --check`, `bash -n`, shellcheck, the self-update `sed`/`cmp` test, the installer.
  - Add the version and remote hooks the Swift build needs for the update-check tests.
- **`tests/diff.sh`** as under "Parity", starting with `help`, `version` and `tasks`.
- **Proof.** `help` (three languages), `version` and `tasks` with and without `--json`, ported and identical.
- **CI.**
  - `push` also on `swift/**`, so merges into `swift/main` are tested as merged.
  - Separate jobs: lint, XCTest plus the universal build, `run.sh` on bash, `run.sh` on Swift, and `diff.sh`. Each job has its own timeout; the old single 30-minute job cannot hold two 12-minute suites.
  - Lint stops naming files that phase 4 deletes.
- **Gate.** All jobs green, and a reviewed diff.

### Phase 1: the run skeleton and a vertical slice (one session, sequential)

- **The main pass:**
  - argument parsing (`arguments.sh`) and the section order;
  - the lock, the report lifecycle, `--quiet`, `--json`, `--deep`, exit status;
  - SIGINT, SIGTERM and SIGHUP writing the report;
  - the sudo keep-alive and its cleanup;
  - `HOMEBREW_NO_AUTO_UPDATE` set once for the whole run;
  - the summary and trends (`summary.sh` without the pick).

  Shared scalars become typed run state: free space before, disk total, memory, swap, battery, freed, candidate totals.
- **Candidate registration**, which every cleaner and leftover depends on:
  - the candidate model with all its fields, `C_SUDO`, `C_LOP` and `C_BUSY` included;
  - keys;
  - `cover`, `safe_path`, `ai_path`, `artifact_ok`;
  - the cache tables (`ELECTRON_CACHES` and friends; `safe_path` reads them);
  - background measuring (`kb_bg`, `kb_get`, `settle`), owned by the run so any section can read a measurement started earlier.
- **One vertical slice through all of it:** one check (`check.disk`), one updater (`update.brew`, which exercises `Shell` timeouts) and one cleaner (`clean.derived_data`). Runs with `--only` on these route to Swift and pass both tests.
- **Shared integration points as stubs**, so phase 2 units never edit the same file:
  - the startup section's call into leftovers;
  - the cleaners' call to leftovers' candidates;
  - `ver_gt` and `update_cmd`, which the summary uses.
- **Gate.** Merged and green. The data types are frozen.

### Phase 2: sections, in parallel (two waves of three sessions)

Units are grouped by tasks, not by bash file. Each unit owns its tasks end to end and adds them to its own ported list.

Wave A:

| Unit | Tasks | Bash it reads |
|---|---|---|
| `checks` | `check.*` system, security, sizes, video and photo, deep (not startup items) | `checks.sh`, `report.sh` except the startup section |
| `updates` | `update.*` | `updates.sh`; the riskiest unit (sudo, `mas`, casks, long downloads); it finishes `Shell`'s sudo path |
| `commands` | one-off commands: `history`, `last`, `reports`, `config`, `lang`, the menu, `uninstall` | `commands.sh`; `uninstall` must still find 2.9 bash copies (it recognises them by `^MACUP_VERSION=`) and recognise 3.0 binaries by the rule decided in phase 5 |

Wave B (started alongside the last wave A merges, 2026-11-26; each unit rebases before its final checks):

| Unit | Tasks | Bash it reads |
|---|---|---|
| `tools` | tools and services checks: npm globals, MCP servers, skills, plugins, the commands check, outdated apps | `tools.sh` |
| `cleaners` | every `clean.*` task registered in `cleaners.sh`, registration only | `cleaners.sh` up to `leftovers_cands` |
| `leftovers` | `clean.orphan_*`, `clean.dev_containers`, the startup section, the Trash moves and the sudo commands they show | `leftovers.sh`, `report.sh` startup section; it fills the stubs from phase 1 |

Within a wave, a unit that needs a foundation change stops and asks the coordinator, who merges that change first.

### Phase 3: exec and pick (one session)

- Phase 1 already ported, for `clean.derived_data`: `exec_cand` for the `empty` kind, `del`, `running`, the process part of `mark_busy`, `visible`, `list_cands`, `json_cands`.
- **The code that deletes files:**
  - `exec_cand` for the `rm`, `trash` and `cmd` kinds, and `run_key` (with the `orph:`, `odata:` and `devc:` keys that point into the leftovers state);
  - `del`, `to_trash_path`, the leftovers `to_trash` with its allow list;
  - busy detection (`running`, `lsof_snap`, `open_in`, `mark_busy`);
  - `visible`, `list_cands`, the pick, confirmations, `--pick`.
- **Gate:**
  - full `check`, `clean` and `all` runs route to Swift and pass both tests;
  - `safe_path`, `artifact_ok` and `to_trash` get table-driven XCTest with every protected path the suite knows;
  - the strictest review of the port.

### Phase 4: Swift only (one session)

- **The bash exec and the embedded script are removed from the binary,** and so is the routing (every task is ported).
- **The bash build stays in `src/`** for one more phase as the oracle for `tests/diff.sh`.
- **`self-update` and `schedule` are ported for the binary.**
  - `self-update` replaces the binary by rename, not by writing into it.
  - `schedule` writes `ProgramArguments` with the binary itself, not `/bin/bash`.

### Phase 5: shipping (one session)

**Releases.** On a tag that has already passed CI on `main`, a workflow (`.github/workflows/release.yml`; everything but the upload is `tools/release.sh`, which CI runs on every pull request):

- builds the universal binary and strips it;
- runs `codesign -v` on both slices (arm64 refuses unsigned code; ad hoc is the minimum);
- attaches `macup-<version>-macos-universal.tar.gz` and its SHA-256 to the GitHub release.

**`install.sh`.** Downloads that archive, checks it and installs `~/.local/bin/macup`. Running it from a checkout installs the locally built binary instead (CI's install step uses that).

**Old installs.** A 2.9.x copy updates itself like this (`fetch_release`, `self_update` in `src/commands.sh`):

1. reads `MACUP_VERSION="…"` from `main/macup`;
2. fetches `v<version>/macup.sha256`, then `v<version>/macup`;
3. checks them with `bash -n`;
4. installs that file over itself.

So the repository root keeps a bash `macup` with that exact version line, and its `macup.sha256`: a bootstrap. The bootstrap:

- downloads and checks the release binary and replaces itself by rename;
- leaves itself working and says so if the release asset is not there yet (the minutes between the merge and the upload);
- refuses to run from a Homebrew Cellar path and says `brew upgrade macup`;
- on a macOS older than the deployment target, installs the last 2.9.x instead of a binary that cannot start;
- rewrites an existing LaunchAgent. 2.9.x wrote `/bin/bash <path> check --quiet --notify`, and with a binary at that path launchd would fail with exit 126 silently forever. The 3.0 binary also checks and rewrites it on its first run, which covers Homebrew installs.

It lives in `tools/bootstrap.sh` until the cleanup moves it to the root. Started by the LaunchAgent itself (`PPID` 1 or `XPC_SERVICE_NAME`), it runs that check from the download and changes nothing: `launchctl bootout` from inside the job would stop it before it could load the job again, so the swap and the reload wait for a run from a terminal. `install.sh` installs the bootstrap and runs it, so the download, the checks and the macOS 13 rule live in one place.

The suite gets tests for each of these, including a 2.9.2 `self-update` against a fake release.

**Recognising macup.**

- 2.9 copies keep being found by `^MACUP_VERSION=` and `^# macup`.
- A 3.0 binary is found by a fixed marker string, not by running it with `version` (decided in phase 5). The marker is `Env.marker`: a line `# macup` and a line `MACUP_VERSION="<version>"`, one literal that `Env.version` is read from. So the 2.9 rules (`grep -q '^MACUP_VERSION='` in 2.9's `uninstall`, that and `'^# macup'` in its `install.sh`) and `SelfPath.isMacup` find a 3.0 binary unchanged, and running an unknown file named macup is never needed. `tools/release.sh` checks that each stripped slice holds both lines together, which the embedded bash build does not, so the check cannot pass on the bash text alone.
- `install.sh` and `uninstall` use the same rule.

**Homebrew.** The formula installs the release asset. `tools/bump-formula.sh` learns the asset URL and checks that the asset exists. `brew audit --strict --online` is run in the tap before relying on it.

**Cleanup.**

- `src/*.sh`, `src/py`, `tests/test_helpers.py` and `tests/diff.sh` are deleted.
- `tests/run.sh` stays, minus the bash-only tests.
- `install.sh` and the bootstrap stay bash.
- The swap: `git mv tools/bootstrap.sh macup` with `MACUP_VERSION` set to the release, `macup.sha256` written for it and both committed; `/macup` and `/macup.sha256` leave `.gitignore`; `build.sh` stops writing them and `--check` compares `macup.sha256` with the committed `macup`; `tests/shipping.sh` reads the bootstrap from `macup` and takes 2.9.2 from the `v2.9.2` tag (CI then needs tags). `tools/release.sh` already checks the committed root `macup`.

**Docs.** README requirements and install options (curl and Homebrew only; see "Decisions"), CHANGELOG 3.0.0 with the intended differences.

### Phase 6: final review and release (coordinator)

1. The whole `swift/main` diff against `main` gets a reviewer subagent (Opus, high effort) and a code review, and every finding is fixed or answered.
2. `main` is merged in one last time, and the carry-over list must be fully ticked.
3. The suite runs.
4. One pull request goes from `swift/main` into `main`.

Merging it and tagging 3.0.0 happen only when the owner says so.

## Every pull request into `swift/main`

1. **The session runs and reports the numbers:** `./build.sh`, `swift build -c release`, XCTest, `tests/run.sh` on both builds and `tests/diff.sh`, in the background (about 12 minutes per suite).
2. **A reviewer subagent on Opus at high effort** (Fable only where a review really needs it: it costs much more, owner 2026-11-26) reads the diff together with the bash it replaces, looking for changed behaviour. The session fixes or answers each finding.
3. **A code review** (`/code-review` at high) reads the same diff. The session fixes or answers each finding.
4. **CI** is green.
5. **Code rules** (ground rule 8) hold for every file the PR adds or changes.
6. **The coordinator** reads the result and verifies a claim or two itself. It checks that no carry-over line touching the unit's code is left unticked, then merges.

**Waiting for CI.** Many sessions share one GitHub account and its 5000 API calls an hour; on 2026-11-26 polling used them all up. Never `gh pr checks --watch`, `gh run watch` or `gh` in a loop. Use the app's PR status, or one `gh pr view <n> --json statusCheckRollup` every 3 minutes at most. `gh event listen` is not enabled on this account (HTTP 403 at once), so it cannot wait. On a 403 rate limit, wait for the reset.

## Known traps

- **`HOME`, `PATH` and the hooks.** See `Env`.
- **Timeouts and the foreground.** See `Shell`.
- **`du`, `find`, `cksum`, `sort`.** See "Parity".
- **Terminals.** Questions read `/dev/tty`. The suite drives the pick through `script`. `ask` must keep working under `curl | bash`.
- **sudo.** The keep-alive dies with macup, and nothing asks for sudo under `--quiet` or a schedule.
- **State that bash shares through globals and the environment.** It becomes typed run state, never a re-read file. For example, `HOMEBREW_NO_AUTO_UPDATE` must still hold for `brew doctor` and `brew cleanup -n` later in the run.
- **Regex literals need macOS 13.** Below that, use `NSRegularExpression`.

## Decisions (taken 2026-11-26)

1. **Deployment target: macOS 13.** Regex literals are available; newer targets add nothing a CLI needs. CI tests 15 and 26; 13 and 14 are built for but untested, and the README says so. The bootstrap keeps Macs older than 13 on the last 2.9.x.
2. **Shipping: curl and Homebrew only for 3.0.0.** Neither sets the quarantine attribute, so no notarization is needed. The binary is ad hoc signed and `codesign -v` checks both slices. The README offers no browser download. Notarization (an Apple Developer account exists) can come later if a browser download is ever wanted.
3. **Authority.** The owner lets the coordinator run every phase and merge each reviewed, green pull request into `swift/main` without asking. The final pull request into `main` and the 3.0.0 tag still wait for the owner's word.

## Bash fixes to carry over

(empty)

## Bash bugs the port reproduces until phase 4

Not worth a release from `main`: the Swift port copies them so `diff.sh` stays exact, and phase 4 fixes them in Swift, each with a test and a line in the 3.0.0 CHANGELOG.

- [ ] `show_history`: awk's `h()` assigns the global `b`, which is also the bold colour (`-v b="$B"`), so "Free space trend:" starts with the last freed value in bytes and is never bold (found by the commands unit, PR #13).
- [ ] Time Machine's backup age (`src/checks.sh` and `Security.timeMachine`): `date -j -f %Y-%m-%d` gives the backup's date the current time of day, so when a second ticks between `date +%s` and that call the age comes out a day short, and an 8-day-old backup passes the 7-day check. Phase 4 parses the date in Swift. Until then `diff.sh`'s fake `date` reads that date as its midnight, since the two builds hit the race on different runs (found on #16's CI, run 45897078448). That pin never matched until #23: it tested 4 arguments, and the call has 5 (#20's pull_request run).
- [ ] `app_names` / `apple_names` (leftovers): bash merges installed names with `sort -u`, which drops names that strcoll ties at the same length (Cyrillic or CJK id parts), so such an app's leftovers can be reported as orphaned. Found by the leftovers unit (#15).

## Follow-ups queued

- [x] After wave A (#19): move `Checks.glob` (fnmatch, strcoll in the locale) into Foundation and use it in `Report.swift`'s tidy, which sorts by bytes where bash's `ls -r` uses the locale; two reports from the same second can make `keep_reports` keep a different one. Also set LC_CTYPE with LC_COLLATE (from `Env.lcCtype`'s decision): with LC_CTYPE "C" strcoll orders `a é b B e` where bash's glob and `sort` give `a b B e é` (found by the leftovers unit). Owner: the commands unit's session; it blocks the leftovers unit's non-ASCII sort test.
- [ ] CI's `diff` job hit its 20-minute limit at 819 runs (the PR run took 18.5 minutes); the limit is now 60. If it keeps growing, split `diff.sh` by unit block into parallel jobs.
- [x] Phase 3: move `Terminal.ask` and `Terminal.isYes` from the commands unit into Foundation for the pick and confirmations (#20).
- [ ] Wave B, cleaners unit: cleaners.sh starts `kb_bg` for `~/Library/Caches`, `CoreSimulator/Devices` and `Xcode/Archives` when `check.sizes` runs; until those starts are ported, `measure.get` measures them in the foreground.
- [x] `check.macos_updates`: owned by the updates unit, a small PR after #12 (#14).
- [x] Terminal runs in `diff.sh` were vacuous on macOS 27: `script` refused a fifo on stdin, both builds printed the same error and compared SAME (found by the commands and leftovers units). #13 feeds a pipe instead. After #13 merges: run the full `diff.sh` locally and check that CI's macOS 26 run is real too; any tty difference in the merged checks and updates units goes back to them. Add a guard so a run whose output is only a harness error fails instead of counting as SAME. Done: #13's pipe and #19's guard; swift/main CI on 2b04ae9 passed with real tty runs.
- [x] `diff.sh` flake (#19): the Time Machine day count (`chk-security-off`) differs by one when a second passes between a build's `now` and its `date -j -f %Y-%m-%d` call; the fixture date is exactly N days back and BSD date keeps the time of day (#16 push run). Fix in the test fakes: pin that `date` form to midnight. Owner: the commands unit, in the sorted-glob PR. The pin only took effect with #23 (it tested 4 arguments; the call has 5).
- [x] `diff.sh` flake: the `tmutil` fake wrote `destinationinfo` with `printf` in pieces, and bash's `grep -q` under pipefail closed the pipe between them in about 1% of runs ("no backup destination" in bash only). The fake writes once, as the real `tmutil` does (#18). Fakes that a `grep -q` reads should write in one piece.
- [x] Foundation: make `Config.isSpace` static (`Config.isSpace(_:utf8:)`); `Updates.macOS` (#14) builds a `Config` on `/dev/null` only to reach it (#20).
- [ ] Move `Updates.codePointOrder` (Python's `sorted()` order) into Foundation beside `Names`: the cleaners unit (#18) calls it, and units should not depend on each other. Owner: the phase 3 session, after #18.

## Progress

| Phase | Unit | Branch | PR | State |
|---|---|---|---|---|
| 0 | foundation and harness | `swift/foundation` | #9 | merged (0ee1899) |
| 1 | run skeleton, candidates, vertical slice | `swift/run-skeleton` | #10 | merged (d4b13c9) |
| 2A | checks | `swift/checks` | #11 | merged (cbe2a53) |
| 2A | updates | `swift/updates` | #12 | merged (1dcd8b2) |
| 2A | commands | `swift/commands` | #13 | merged (cac5a4d) |
| 2A | `check.macos_updates` | `swift/macos-updates` | #14 | merged (2b04ae9) |
| 2A | names in the locale's order, `diff.sh` split | `swift/sorted-glob` | #19 | merged (78835fe) |
| 2B | tools | `swift/tools` | #17 | merged (a7a08b1) |
| 2B | busy folders (`lsof_snap`, `open_in`) | `swift/lsof-busy` | #16 | merged (3e1703c) |
| 2B | cleaners (registration) | `swift/cleaners` | #18 | merged (b8193f9) |
| 2B | leftovers (registration, startup) | `swift/leftovers` | #15 | merged (85dc350) |
| 3 | Foundation moves for the pick (`Terminal`, `Config.isSpace`) | `swift/foundation-followups` | #20 | merged (d5fb784) |
| 3 | exec of every kind, `run_key`, the leftovers' moves, the dev container scan | `swift/exec` | #24 | merged (374f630) |
| 3 | the pick, confirmations, `--pick` | | | in progress |
| 5 | release asset, macup marker, formula bump | `swift/release-asset` | #21 | merged (84f4222) |
| 5 | 2.9 bootstrap, `install.sh` on the release binary | `swift/bootstrap` | #22 | merged (4f16158) |
| - | `diff.sh` fakes: the Time Machine `date` pin matches | `swift/date-pin` | #23 | merged (cd848fc) |

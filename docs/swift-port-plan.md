# Porting macup to Swift

Status: plan, not started. Integration branch: `swift/main`. Everything for the port lands there; `swift/main` reaches `main` in one final pull request and ships as 3.0.0.

## Why

macup is about 3,100 lines of bash 3.2 in `src/*.sh`, built into one `macup` file. It works, and `tests/run.sh` (211 black-box tests on throwaway home folders) proves it, but the code is hard to read and has whole classes of bugs a compiler would stop: global variables clobbering each other (a cleaner's `G` overwrote the green colour), nested heredocs breaking the build, `grep -q` under `pipefail` reading a match as "no".

Swift fits this tool:

- A prebuilt universal binary runs on a fresh Mac with no Command Line Tools: the Swift runtime ships with macOS since 10.14.4. bash gave the same, Python would not.
- Native APIs replace text parsing: `FileManager`, `PropertyListSerialization`, `Codable`, `Process`.
- Strict types and one owner per piece of state.

Non-goals: new features, changed output, changed task ids or config keys. 3.0.0 behaves like 2.9.x; only the implementation and the way it is shipped change.

## Ground rules

1. **Behaviour is the spec.** `tests/run.sh` must pass against the Swift build at every merge into `swift/main`. Terminal output, the report, `--json`, exit codes and the files macup writes stay byte-identical, except timings.
2. **Nothing is ported blind.** Bash and Swift run side by side until the last bash line is gone: each step replaces one piece and the full suite runs on the result. A step that cannot be tested end to end is not merged.
3. **Sequential where pieces depend on each other, parallel where they do not.** A parallel phase starts only after the phase it builds on is merged into `swift/main`.
4. **Foundation only.** Swift 5.9 tools, macOS 12 deployment target, no third-party packages.
5. **`main` is frozen for features** until 3.0.0. Critical fixes still go to `main`. Each one adds a line to "Bash fixes to carry over" at the end of this file, and `main` is merged into `swift/main` after each fix.

## How the two languages coexist

### One-off commands: the binary decides

From phase 0 on, the Swift binary is the `macup` entry point. It holds the built bash script, generated into a Swift source at build time. A command Swift does not handle yet runs that script with the same argv, environment, stdin, stdout, stderr and exit status. `MACUP_SELF=<path of the binary>` tells the script who it is: `resolve_self` decides the Homebrew and uninstall paths from it. One-off commands (`help`, `version`, `tasks`, `history`, `reports`, `last`, `config`, `lang`, `schedule`, `uninstall`, `self-update`, the menu) switch to Swift one by one.

### The main run: a section bridge

`check`, `update`, `clean` and `all` are one pass through every section (system, security, updates, tools, sizes, cleaners, leftovers, pick, summary). The sections share state: warnings, updated items, skipped apps, cleanup candidates and the report body. A command-level switch cannot move one section at a time, so until phase 3 the bash script keeps orchestrating the main run and calls Swift for each section already ported:

```
macup __section <name>     # run by the bash orchestrator, never by users
```

The bridge contract:

- **Input** comes from the environment the orchestrator exports: `HOME`, `PATH`, language, colour or no colour, level, dry run, the allowed task list (`--only`/`--skip`/`--enable` resolved), `BODY`, `RAW` and the report paths.
- **Terminal output** goes to stdout and stderr. The orchestrator passes it through unchanged.
- **Report text** is appended to `$BODY` and its `.det` file, the same as bash sections do.
- **State** is written as tab-separated records to `$BODY.state.<name>` and read back by one bash function `bridge_import`. Records: `WARN`, `ITEM`, `UPDATED`, `SKIPPED`, `ERR`, `CAND` (all candidate fields, matching `cand()` in `src/cleanup.sh`) and `COVER`. Fields escape tab and newline as `\t` and `\n`.
- **Exit status** 0 means the section ran. Anything else is a failed step, reported the way bash reports one.

Phase 0 writes this contract down as a Swift type and a bash function and tests it in both directions. After that it is frozen: changing it needs a pull request to `swift/main` that the coordinator approves, merged before anything that uses the change.

In phase 3 Swift takes over orchestration, the bridge and the bash orchestrator are deleted, and the sections call each other directly.

## Layout

```
Package.swift
Sources/macup/                 main.swift: entry, legacy fallback
Sources/MacupCore/             everything else, one folder per module
  Foundation/                  Env, Shell, Output, I18n, Config, Tasks, Paths, Size, Lock, Report, Bridge
  Commands/  Checks/  Report/  Tools/  Updates/  Cleaners/  Leftovers/  Cleanup/  Summary/
Sources/macup/Generated/       LegacyScript.swift, Translations.swift (written by build.sh; not committed)
Tests/MacupCoreTests/          XCTest for pure logic
tests/run.sh                   unchanged black-box suite; M=<binary> chooses what it runs
```

`build.sh` keeps building the bash `macup` from `src/` and then runs `swift build`. `./build.sh --check` covers both.

## Foundation interfaces (phase 0, frozen afterwards)

| Piece | Replaces | Must get right |
|---|---|---|
| `Env` | top of `core.sh` | `HOME` from the environment, never `FileManager.homeDirectoryForCurrentUser`, which ignores `HOME` and would break every fake-home test; `PATH` with Homebrew prepended unless `MACUP_PATH=keep`; refusing to run without `HOME` or under sudo |
| `Shell` | `run`, `tl`, `have`, `tick` | tools found through `PATH`, never fixed paths, so the tests' fake `pgrep`, `lsof`, `brew` and `xcrun` win; `step_timeout_minutes` kills the whole process group; output teed to the report's raw section; `/dev/tty` for questions; sudo with `sudo -v`, the keep-alive and `stop_sudo_keep` as today |
| `Output` | `ok`, `info`, `warn`, `err`, `step`, `section`, `md`, `detail`, colours | byte-identical lines, colours only on a terminal and without `--no-color`, the same Markdown in the report, items recorded for `--json` |
| `I18n` | `_`, `_f`, `translations.json` | `printf` semantics for `%s`, `%d` and `%%`, and the same fallback to English |
| `Config`, `Tasks` | `load_conf`, `conf`, `conf_set`, the task table, `task_allowed`, `task`, groups | the same file format and keys, and the same unknown-id errors |
| `Paths`, `Size` | `expand`, `tildify`, `kb`, `hum`, `tokb` | `du -k` numbers (call `du`, do not re-implement it), the same rounding in `hum` |
| `Lock`, `Report` | `unlock`, `tidy_own`, report naming, `interrupted` | one run at a time; SIGINT, SIGTERM and SIGHUP still write the report |
| `Bridge` | new | as specified above |

## Phases

Each unit below is one session working in its own worktree, on a branch `swift/<unit>` cut from `swift/main`, and one pull request into `swift/main`. The coordinator, the session that wrote this plan, starts the sessions, reviews, merges and keeps this file up to date.

### Phase 0: foundation (one session)

- **Package and build.** `Package.swift`, `build.sh` integration, the generated sources, the legacy fallback with `MACUP_SELF`.
- **Foundation.** All the interfaces above, with XCTest for the pure parts: `hum`, `tokb`, `expand`, `tildify`, config parsing, task matching, `_f`.
- **Bridge.** The Swift side, `bridge_import` in bash, and a round-trip test for every record type with tabs, newlines, Cyrillic and `%` in the fields.
- **Proof commands.** `help` in all three languages, `version`, and `tasks` with and without `--json`, ported in Swift and byte-identical to bash.
- **Tests and CI.** `tests/run.sh` gets `M=` to run either build. CI builds the universal binary (`--arch arm64 --arch x86_64`) on macos-26 and macos-15, runs XCTest, and runs `tests/run.sh` against the bash build and the Swift build.
- **Gate.** Both builds ALL PASS and a reviewed diff. The interfaces are then frozen.

### Phase 1: sections and commands (two waves of three parallel sessions)

Every unit ports one file, as a section behind the bridge or as one-off commands behind the fallback, and deletes its bash code from the orchestrated path. The bash code itself stays in `src/` until phase 3.

Wave A, read-mostly and low-risk:

| Unit | Bash source | Notes |
|---|---|---|
| `checks` | `checks.sh`, `report.sh` | system, security, sizes, video and photo, startup, deep; fakes of `sysctl`, `profiles`, `tmutil` and friends already exist in `run.sh` |
| `cleaners` | `cleaners.sh` | emits `CAND` and `COVER` records; includes the AI tools, editors and the Electron layout scan (from `src/py/macup_helpers.py`) |
| `commands` | `commands.sh` | `history`, `last`, `reports`, `config`, `lang`, `schedule`, `uninstall`, the menu; `self-update` is ported as it is, and its redesign belongs to phase 4 |

Wave B, starts after wave A is merged:

| Unit | Bash source | Notes |
|---|---|---|
| `tools` | `tools.sh` | npm globals, MCP servers, skills, plugins, the commands check, outdated apps |
| `updates` | `updates.sh` | brew, mas with sudo, npm, Claude, editors, Grok, Antigravity; the riskiest unit because of passwords and long commands, so it reviews the `Shell` sudo path first |
| `leftovers` | `leftovers.sh` | leftovers of deleted apps, dev containers, the Trash moves, the sudo commands shown before they run |

Two units of a wave never edit the same file outside their own module folder. If one needs a change to a foundation piece, it stops and asks the coordinator, who merges that change first.

### Phase 2: the cleanup engine and the summary (one session)

`cleanup.sh` (candidates, `settle`, `safe_path`, `ai_path`, busy detection, `lsof`, background `du`, deletion and the Trash, `exec_cand`) and `summary.sh` (pick, confirmations, totals, history, `--json`, `--pick`). This is the code that deletes files, so it runs alone and gets the strictest review. `safe_path` and `artifact_ok` get table-driven XCTest with every protected path the suite knows.

### Phase 3: Swift orchestrates (one session)

Swift runs the main pass itself: argument parsing (`arguments.sh`), the order of sections, `--quiet`, `--json`, `--deep`, exit status, the lock and the signals. The bridge, the bash orchestrator and the legacy fallback are deleted, then `src/*.sh`, `src/py` and `tests/test_helpers.py`, once their logic has a Swift home and XCTest. `tests/run.sh` stays as the black-box suite. `install.sh` stays bash.

### Phase 4: shipping (one session)

- **Releases.** On a tag, a workflow builds the universal binary, strips it, and attaches `macup-<version>-macos-universal.tar.gz` and its SHA-256 to the GitHub release. The tag must already have passed CI on `main`.
- **`install.sh`.** Downloads that archive, checks the SHA-256 and installs `~/.local/bin/macup`. Downloads by curl carry no quarantine attribute, so no notarization is needed; signing is still worth doing (ad hoc at least) and decided here.
- **`self-update`.** Downloads the release archive and checks it the same way.
- **Old installs.** Every 2.9.x copy updates itself by fetching the file `macup` at the new tag and checking it against `macup.sha256` from the same tag (`fetch_release` in `src/commands.sh`). So the repository root keeps a small bash `macup` and its `macup.sha256`: a bootstrap that downloads the binary, checks it and replaces itself. Without that file every curl install stays on 2.9.x forever. The suite gets a test that runs a 2.9.2 `self-update` against a fake release.
- **Homebrew.** The formula installs the prebuilt binary (allowed in a personal tap); `tools/bump-formula.sh` learns the new URL and checksum; `brew test` and `brew audit` pass.
- **Docs.** README requirements (no bash requirement for running; bash 3.2 only for `install.sh`), CHANGELOG 3.0.0, `uninstall` paths.

### Phase 5: final review and release (coordinator)

The whole `swift/main` diff against `main` gets a Fable review and a code review, both run on the full diff; every finding is fixed or answered. `main` is merged in one last time and the suite runs. Then one pull request `swift/main` into `main`. Merging it and tagging 3.0.0 happen only when the user says so.

## Every pull request into `swift/main`

1. The session runs `./build.sh`, `swift build -c release`, XCTest and `tests/run.sh` against both builds (in the background, about 12 minutes each). It reports the numbers.
2. A Fable reviewer subagent reads the diff and the bash it replaces, looking for behaviour that changed. The session fixes or answers each finding.
3. A code review (`/code-review` at high) reads the same diff. The session fixes or answers each finding.
4. CI is green on both macOS versions.
5. The coordinator reads the result, checks one or two claims itself, and merges. Sessions never merge into `swift/main` themselves.

## Known traps

- **`HOME`.** Read it from `ProcessInfo.environment`, never from `homeDirectoryForCurrentUser` or `NSHomeDirectory()`.
- **`PATH`.** Look tools up in `PATH`, keep `MACUP_PATH=keep`, and never call `/usr/bin/<tool>` directly unless bash does today.
- **Sorting and locale.** Bash sorts with `sort` in the user's locale or with `LC_ALL=C` where the code says so; Swift must sort the same way in each place.
- **`du` and `find`.** Their numbers and `-mtime` rounding are part of the behaviour. Call them, or match them exactly and test it.
- **Terminals.** Questions read `/dev/tty`; the suite drives the pick through `script`; `ask` must work under `curl | bash` as today.
- **Signals and children.** A timeout kills the process group. Ctrl-C, SIGTERM and SIGHUP keep the report and name it.
- **sudo.** The keep-alive must die with macup, and no `sudo` runs under `--quiet` or a schedule.
- **Text.** `_f` is `printf`: Ukrainian and Russian strings carry the same placeholders, and widths count characters (`ulen`, `pad`), not bytes.
- **Self path.** Homebrew detection and uninstall read the real path of the binary, not of a temporary script.

## Bash fixes to carry over

(empty)

## Progress

| Phase | Unit | Branch | PR | State |
|---|---|---|---|---|
| 0 | foundation | `swift/foundation` | | not started |

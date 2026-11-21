# Changelog

## Unreleased

Fixes:

- **`macup check` no longer opens a hidden password dialog.** 2.9.0 read Background Task Management with `sfltool dumpbtm` to report login items of deleted apps; macOS asks for an administrator password for that (SecurityAgent), so every check in a terminal waited 10 seconds behind a dialog and then gave up. That report is gone: macOS removes the records of a deleted app itself, and the launch agents an app leaves behind are still found from their files.

## 2.9.0 — 2026-11-20

Fixes:

- **A removal that macOS refuses is a failure.** It was reported as cleaned when `rm` could not delete the files.
- **Deno's cleanup keeps `location_data`.** `clean.deno` emptied the whole of `~/Library/Caches/deno`, and Deno keeps `localStorage` and the default `Deno.openKv()` databases there, in `location_data`. That folder now stays; the caches next to it are cleaned as before.
- **A mistyped task id is said.** `macup check --only chek.disk` ran no task and reported that nothing needs attention. An unknown id in `--only`, `--skip` or `--enable` now stops the run with exit status 2; one in the config's `skip` or `enable` is a warning.
- **`sudo macup` refuses to run.** Its reports, history and config became root's, and the next plain run could not write them. macup also does not start without `HOME`: its paths pointed at the system's `/Library`.
- **A command that hangs is stopped together with what it started.** Only the command itself was stopped; brew's downloads went on.
- **Caches are left alone while their tool runs:** Cargo's while `cargo` or `rustc` runs, Maven's while `mvn` runs, Poetry's and Deno's the same.
- **sudo forgets a password that a cask's installer asked for** during `brew upgrade`, as it already did after the App Store updates.
- **`macup self-update` exits with 1 when it cannot write the new file.** It exited with 0.
- **Picking after a check:** `08` is read as 8, and a range like `1-9999` no longer loops for minutes.
- **Growing swap is no longer "something is filling the disk".** "Since last run" compared free space only, and swap files take disk space until macOS removes them on restart. The swap that grew since the last run is now taken off the drop before it warns, and the line says how much of it is swap.
- **Stale `node_modules` are judged by the whole project.** Only the top three folder levels were looked at, so a project edited only in `src/app/components/…` counted as untouched and lost its `node_modules`. Every level is looked at now, except `.git` and build folders, and the search stops at the first recent file.
- **What is in use is said by the check.** The npx cache was listed and counted in "Could free" while MCP servers ran from it, and the cleanup then skipped it. A check now marks anything whose tool or app is running ("in use now") and leaves it out of the totals; the cleanup still asks again right before it cleans. Folders that only macOS's own watchers (UserEventAgent, Spotlight, fseventsd) hold open do not count as in use.
- **A uv tool whose Python was removed gets the right fix:** `uv tool install --reinstall <tool>`, not a `brew link` that changes nothing.
- **A faster check.** The big folders (DerivedData, the pnpm store, `~/Library/Caches`, simulators) are measured side by side, and `brew cleanup -n` runs alongside; `~/Library/Caches` is walked once, not twice. `--only` and `--skip` now skip the measuring of the cleaners they leave out.

macup's own files:

- **One file per run.** What the commands printed went to a `.log` next to each report; it is now at the end of the report, under "Command output". `macup last` stops before that part and says where it is. "(see log)" messages and a Ctrl-C point to the report, and a run stopped with Ctrl-C still writes it, with what the commands printed so far. In `--json`, `log` names the report, the same path as `report`.
- **Old reports go on every run, a check too.** This reverses the earlier rule that a check deletes nothing: reports are macup's own files, and a Mac that only ran `macup check` (the schedule does) kept every report for ever. Reports are kept for `keep_reports_days`, now 30 by default (a value in your config stays), and for at most `keep_reports` runs, 20 by default (it was a fixed 60). The `.log` files of earlier versions go with their reports, and those without a report after `keep_reports_days`.
- **`macup reports`** says how many reports there are, their size, the folder, the oldest and the newest. `macup reports clean` removes them all after asking (`--yes` does not ask), `macup reports --json` lists them for other programs. It used to open the folder in Finder; that is now `macup reports open`.
- **The history keeps its last 500 runs, the schedule's log its last 200 lines,** and temp files that a killed run left behind are removed after a day.
- **`macup check` no longer changes Homebrew.** It ran `brew update`, which also updates Homebrew itself and its taps. A check now calls `brew` with `HOMEBREW_NO_AUTO_UPDATE=1` and leaves `brew update` to `macup update`. When the package list is more than a day old, the check says from which date it is.
- **No connection to Apple's server is not "macOS: up to date".** When `softwareupdate -l` fails, a check says it could not check.

New:

- **Containers of dev builds whose app is gone** (`clean.dev_containers`, opt-in). List your bundle ids in `dev_container_prefixes`; `macup check` lists each container in `~/Library/Containers` that no installed app owns, with its size and last change; what is inside goes to the Trash only when you pick it and say yes (macOS keeps the empty folder). Apple's containers, open ones, extensions and helpers of a live app (`dev.app.share`, `dev.app-LaunchAtLoginHelper`) and anything outside the prefixes are never offered. A container the terminal cannot read is said, and the yes before deleting says that app data goes.
- **Leftovers of deleted apps.** An app dragged to the Trash often leaves its updater running, its folders and its data; `check.startup` only noticed an agent whose program was gone, so an updater kept in Application Support looked alive (Perplexity's Comet updater still ran every hour, with 330 MB beside it and an 800 MB profile). macup now finds an agent's owner by its signing team and bundle id, and `macup check` lists background programs, app data and system services of deleted apps in plain words. The ones you pick go to the Trash (`clean.orphan_agents`, `clean.orphan_data`); system services ask for your Mac password once. Login items that point to deleted apps are reported too.
- **Cleaners:** expired provisioning profiles, npm and Gradle daemon logs older than 30 days (safe); the npx cache (skipped while anything started with `npx` runs, MCP servers included), the Go module cache, Cargo's git downloads, old Cypress versions, older Node versions in fnm and Volta (standard).
- **Stale build folders** (`clean.stale_artifacts`, opt-in): `Pods`, `.build`, `.dart_tool`, `.next`, Rust and Maven `target`, Gradle `build` in projects untouched for `stale_project_days`. Only next to the file that builds them again, never when git tracks files in them, never when they were built recently.
- **Docker:** images no container uses and stopped containers can be picked after a check (or enabled: `clean.docker_images`, `clean.docker_containers`). Volumes are never deleted; a check says how many no container uses.
- **Homebrew packages nothing needs any more** (`brew autoremove`) can be picked after a check.
- **Measured, never deleted:** virtual machines (Colima, Lima, Podman, minikube, Parallels, VMware), core dumps in `/cores`.
- **Updates:** Windsurf and VSCodium extensions, Google Cloud SDK components (its own install), .NET global tools (.NET 9 or later), Composer global packages.
- **Checks:** signing certificates of your code-signing identities that expire within 30 days (a certificate renewed in Xcode no longer warns for the old one, and one without a private key is ignored), a GitHub CLI login that no longer works, apps in `/Applications` that crashed 3 or more times in a week (counted by the time in the report, `Retired/` included; macOS system processes are one count, not a list), Remote Login, Screen Sharing and Remote Management that are on, folders of yours in `PATH` that do not exist.
- **For other programs (a GUI):** `--json` now carries every line of the run (`items`) and every item that can be cleaned (`cleanable`, each with a stable `key`); `macup clean --pick key,…` cleans exactly those. `cleanable` also has the small items the terminal list hides (`"hidden": true`), so they can be picked too, and says which are in use right now (`"busy": true`). `macup tasks --json` and `macup history --json` print the lists. `--enable id,…` turns an opt-in task on for one run. See "For scripts and other programs" in the README.

## 2.8.1 — 2026-11-19

Fixes:

- **"pnpm globals: update failed" without global pnpm packages.** pnpm refuses `pnpm update -g` while its global bin folder (`~/Library/pnpm/bin`) is not on `PATH`, even when there is nothing to update. The step now runs only when `pnpm ls -g` lists packages.

## 2.8.0 — 2026-11-15

Fixes:

- **Creating the config file no longer runs `macup clean` and `macup all`.** The config template had those two commands in backticks, and bash ran them: the first `macup config`, `macup lang` or install on a Mac where `macup` was already on `PATH` (a Homebrew install, a reinstall) cleaned the safe level and updated everything without being asked, and pasted the output into the config. If your config has a long "# What macup …" block, delete that block.
- **Stale `node_modules` are really deleted.** `clean.stale_node_modules` said "cleaned" and deleted nothing: the last check before a delete allowed only `~/Library` and dot-folders. It now also allows a `node_modules` folder inside `project_dirs`, and a cleanup whose paths are all refused is reported as failed.
- **Pinned Node versions stay in more cases.** A pin without the patch (`.nvmrc` with `20.5`) keeps the newest installed `20.5.x`; pins in `package.json` (`volta`, `engines`) count too.
- **Poetry's virtualenvs are never offered as a cache.** "Other big folders in `~/Library/Caches`" listed `pypoetry`, where Poetry keeps them. A folder with a virtualenv inside is skipped; Poetry's real cache has its own safe cleaner.
- **`macup update --deep` works.** It printed `project_roots: command not found` instead of the build artifacts.
- **Xcode's caches are left alone while `xcodebuild` runs**, not only while Xcode is open.
- **sudo forgets the password after the App Store updates.** The updaters that run next (pipx, Oh My Zsh, gh extensions, …) could use it without asking for up to 5 minutes.
- **The Trash that cannot be read is said so.** Without Full Disk Access for the terminal it showed nothing.

New:

- **Exit status.** `3` when an update or cleanup step failed; it was always `0`. Failed steps show ✗.
- **`--quiet`** prints only the summary, **`--json`** prints it as one JSON object.
- **A command that hangs is stopped** after `step_timeout_minutes` (60; App Store installs get four times as long). The checks that ask other programs (`softwareupdate`, `brew doctor`, `claude mcp list`, `docker info`, …) have their own shorter limits.
- **One run at a time.** A second macup started meanwhile refuses to start. Report names carry seconds.
- **`self-update` and the installer install the tagged release and check its SHA-256** (`macup.sha256`, written by `build.sh`). They used to take whatever was on `main`, unchecked. Before a version is tagged they fall back to `main`, still checked.
- **Optional schedule:** `macup schedule weekly` or `daily` adds a LaunchAgent that runs `macup check` and shows a notification when something needs attention; `macup schedule off` removes it. Nothing is scheduled unless you ask.
- **Updates:** global pnpm packages, Bun, Deno (their own installs; Homebrew's are left to Homebrew), `cargo install` programs (needs `cargo-update`), mise tools, asdf plugins, VS Code and Cursor extensions. Ruby gems are opt-in: `enable = update.gem`.
- **Cleaners:** Bun, Deno and Poetry caches (safe); Cargo registry downloads and sources, JetBrains IDE caches (standard, skipped while the IDE is open).
- **Measured, never deleted:** iPhone and iPad backups, Docker Desktop's disk image.
- **`--deep`** also lists Rust and Maven `target`, Gradle `build`, `.next` and `.venv`.
- Tests for all of the above, and for reading `softwareupdate`, `system_profiler` and `memory_pressure` output. CI runs on macOS 15 and 26, Apple silicon and Intel.

## 2.7.2 — 2026-11-11

- **The summary names the apps that fell behind.** It showed only "Apps with a newer version: 14", and the list was in the section above. The names are now in the warning itself; the section still lists both versions.
- **Dead links say whose leftovers they are.** "Dead links in /usr/local/bin, leftovers of removed Python.framework, node_modules/quicktype: …", and that they are safe to remove with the printed command.
- **Time Machine can be turned off on its own:** `skip = check.time_machine`. The "no backup destination" warning says so. `--only check.security` still includes it.

## 2.7.1 — 2026-11-10

- **App Store updates ask for the Mac password once.** sudo forgets it after 5 minutes, and one install (Xcode, Final Cut Pro) takes longer, so macup asked again before the next app. It now keeps sudo's password fresh in the background until the App Store updates end, and stops when macup exits or is interrupted.

## 2.7.0 — 2026-11-10

- **Grok CLI and Antigravity CLI are updated** (`grok update`, `agy update`). `macup check` shows when a newer Grok is out; Antigravity has no read-only check, so a check lists it as updated by `macup update`. A Grok installed by brew or npm is left to that step.
- **Apps that update themselves are listed when they fall behind.** Apps in `/Applications` and `~/Applications` that Homebrew and the App Store did not install (Cursor, VS Code, Postman, OBS, …) are compared with the Homebrew catalog by their `.app` name, and the ones behind are listed with both versions: open or restart them to update. macup installs nothing for them. Task id: `update.apps`.
  - The catalog (formulae.brew.sh, about 20 MB) is kept in `~/Library/Caches/macup` and downloaded again only when it changed. `macup uninstall` removes it.
  - Beta casks are ignored; an app name that two casks share with different versions (Telegram) is skipped.
- **Old Antigravity CLI versions** (`~/.local/bin/agy.*.old`, about 190 MB each) are cleaned at the safe level.

## 2.6.1 — 2026-10-31

- **App Store updates say what is going on.** `macup update` lists the apps first (`Xcode (27.1 → 27.2)`), then:
  - asks for the Mac password on its own line, saying it is for the App Store updates, and only when sudo has none cached. mas used to ask a bare `Password:` stuck to the step line.
  - updates one app at a time, with a line that shows the step (downloading, installing) and the time, every second. The Xcode install prints nothing for many minutes, so it used to look hung.
  - reports each app on its own: updated, or not installed with the App Store to open.
- Without a password (no terminal, or sudo refused) mas does not run and macup says the updates need it.
- `macup check` lists App Store updates without their ids.

## 2.6.0 — 2026-10-30

- **Homebrew:** `brew install vitaliideveloper/macup/macup`. `macup self-update` and the "newer macup" notice say `brew upgrade macup` for a Homebrew install, and the installer leaves Homebrew's link alone.
- **`macup uninstall` removes everything macup made.** It lists it all and asks once (`--yes` skips the question):
  - the script and older copies in `~/.npm-global/bin`, `/usr/local/bin`, `/opt/homebrew/bin`
  - settings, history and reports
  - temporary files of interrupted runs
  - the `PATH` line the installer added to `~/.zshrc` and `~/.bash_profile`, unless other programs live in that folder; it says which
  - for a Homebrew install, it runs `brew uninstall macup` and removes the tap.
- `./macup uninstall` in a source checkout no longer deletes the built file.
- An interrupted run (Ctrl-C) no longer leaves the cleaners' temporary lists in `$TMPDIR`.

## 2.5.0 — 2026-10-30

- **Commands that cannot start come with the command that fixes them.** macup prints it and never runs it.
  - Dead links: a command that removes the dead links in that folder (`find … ! -exec test -e {} \; -print -delete`), with `sudo` for a folder owned by root such as `/usr/local/bin`.
  - A missing interpreter whose formula is installed but not linked: `brew link --overwrite node`, or `brew link --force --overwrite node@24` for the newest keg-only version.
  - No brew command when the interpreter is on PATH and only a venv's copy is gone; linking would not help.
- npm globals and agent skills: "skipped, node is not on PATH" carries the same `brew link` command.
- Casks that update themselves are listed by name (`flutter`), not as a count followed by a fixed "(Chrome, Slack, …)". Only `auto_updates` casks count now: a `version :latest` cask is always "outdated" and showed up on every run. The hint is `brew upgrade --cask --greedy-auto-updates`.
- Homebrew and App Store counts read "formulae: 1, casks: 0" and "updates: 1" instead of "1 formulae" and "1 updates".
- macOS updates show their name ("Command Line Tools for Xcode 27.2"), not their label ("…27.2-27.2").
- Older Python versions: virtualenvs made by pipenv, virtualenvwrapper and hatch also count as pins, so `clean.old_versions` keeps the Python they are built on.
- `macup update` shows the size of Xcode Archives and simulator devices too, not only `check` and `clean`.

## 2.4.0 — 2026-10-30

- **App and browser caches are found by their folder layout, not a list of names.** Any Chromium, Electron or Firefox-based app is covered (Chrome, Edge, Brave, Comet, Slack, Discord, Notion and others; App Store apps keep theirs in a container macOS does not let macup into): a cache folder next to Chromium's own files in Application Support, the same folders in `~/Library/Caches`, Firefox's `cache2`. Browsers stay aggressive, apps are safe. An app macup has no name for is skipped while any process has a file open in its folders. In Application Support only what is inside a cache folder can be deleted, so Chrome's profile caches are now cleaned while passwords, history and cookies are never touched.
- **New check: commands that cannot start.** Scripts in `~/.local/bin`, `~/.npm-global/bin`, `/opt/homebrew/bin` and `/usr/local/bin` whose interpreter is gone (an unlinked keg-only `node@24`, a pipx tool whose Python was removed) or whose link points at a deleted file, with the fix when there is one (`brew link --force --overwrite node@24`, `pipx reinstall-all`).
- npm globals and agent skills say "skipped, node is not on PATH" when npm/npx are there but node is not. npm globals used to show a false "up to date" and agent skills only "update failed".
- Downloaded app updates waiting to be installed (Sparkle, ShipIt) are never deleted. Arc's cache used to include its pending update, and the pick list offered VS Code's.
- Electron caches are also looked for in `Default/` and `Partitions/*`, and in `~/Library/Caches` (Codex keeps most of its cache there). Postman, Slack, Discord, Notion, Obsidian and Signal are named. An app also counts as open while a process uses its folder as `--user-data-dir` (Application Support/Codex belongs to ChatGPT).
- Unavailable simulators: also Xcode's parallel-test clones (`XCTestDevices`), with their real size in `check`; skipped while Xcode or xcodebuild runs.
- `--deep` lists the largest folders in Application Support.

## 2.3.2 — 2026-10-11

- `macup check`: the updates section is now titled "Update status (check only, nothing installed)", not "Available updates", because ✓ lines mean up to date. The line for agent skills, pipx and uv, which a check cannot version-check, says they are not checked in this mode and `macup update` updates them (no count that looked like pending updates).
- Cleaning: what was skipped because its app is open is now listed in the summary and the report ("Skipped because the app is open"), with the size, so a run that freed nothing is not a mystery. It is not a warning: editors are often open and "Needs attention" stays for real problems.
- Tests no longer depend on which apps happen to be running on the machine (a fake `pgrep`); they passed only with Xcode, Cursor, Chrome and others closed.

## 2.3.0 — 2026-10-10

- **Pick what to clean.** `macup check` lists everything that can be cleaned with its size and level, then asks: numbers (`1,3`, `2-5`), a level, or Enter for nothing.
- **Three levels.** `safe` (rebuilds itself, the default), `standard` (downloaded again), `aggressive` (browser caches). `macup clean --level standard`, or `clean_level` in the config.
- **New cleaners:** Gradle, Android Studio, Maven, Docker build cache, older patch versions in nvm/rbenv/pyenv/mise/asdf (pinned versions stay), old Playwright/Puppeteer browsers, caches of VS Code, Cursor, Windsurf, Antigravity, Claude and Codex, Codex leftovers, browser caches, pnpm metadata, node-gyp. Other big folders in `~/Library/Caches` can be picked one by one.
- **Simulators, on pick:** delete a runtime you no longer need (shows last use and how many simulators need it), erase a simulator's apps and data, delete simulators unused for `simulator_days` (30). Running ones are skipped.
- **Measured, never deleted:** Final Cut Pro, Premiere/After Effects, DaVinci Resolve, Lightroom Classic and Camera Raw caches, with the app's own menu item to clear them; Codex chat history; AI models; Android SDK and emulators.
- Apps that are open are skipped. Only listed cache folders are touched; settings, history, keys and symlink targets never are.
- `macup clean` and `macup all` without `--level` still clean only the `safe` level. New in it: editor and Claude/Codex app caches (skipped while open), Codex leftovers, pnpm metadata, node-gyp headers.
- Sizes in decimal units, as in Finder (1 GB = 1000³ bytes); swap files on disk are shown under Disk.
- Source split into `src/` (built into the single `macup` by `./build.sh`); translations in one JSON file; caches described in tables.
- Tests in `tests/run.sh`, run by CI.

## 2.2.0 — 2026-10-02

First public release.

- Updates for Claude Code, npm, agent skills, Homebrew, App Store, pipx, uv, rustup, Oh My Zsh and gh extensions
- Safe cleanup of Xcode, simulator and package-manager caches; opt-in removal of stale `node_modules` and the Trash
- Health and security checks, a Markdown report for every run, and trends across runs
- Nothing changes without an explicit command; `macup check` installs and deletes nothing
- Interface in English, Ukrainian and Russian
- Interactive installer, `self-update`, `uninstall`

Earlier versions were private.

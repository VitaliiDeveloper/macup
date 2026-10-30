# Changelog

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

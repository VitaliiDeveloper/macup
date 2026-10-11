# Changelog

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

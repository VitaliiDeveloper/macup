# Changelog

## 2.3.0 — 2026-10-10

- **Pick what to clean.** `macup check` lists everything that can be cleaned with its size and level, then asks: numbers (`1,3`, `2-5`), a level, or Enter for nothing.
- **Three levels.** `safe` (rebuilds itself, the default), `standard` (downloaded again), `aggressive` (browser caches). `macup clean --level standard`, or `clean_level` in the config.
- **New cleaners:** Gradle, Android Studio, Maven, Docker build cache, older patch versions in nvm/rbenv/pyenv/mise/asdf (pinned versions stay), old Playwright/Puppeteer browsers, caches of VS Code, Cursor, Windsurf, Antigravity, Claude and Codex, Codex leftovers, browser caches, pnpm metadata, node-gyp. Other big folders in `~/Library/Caches` can be picked one by one.
- **Measured, never deleted:** Final Cut Pro, Premiere/After Effects, DaVinci Resolve, Lightroom Classic and Camera Raw caches, with the app's own menu item to clear them; Codex chat history; AI models; Android SDK and emulators.
- Apps that are open are skipped. Only listed cache folders are touched; settings, history, keys and symlink targets never are.
- `macup clean` and `macup all` without `--level` still clean only the `safe` level. New in it: editor and Claude/Codex app caches (skipped while open), Codex leftovers, pnpm metadata, node-gyp headers.
- Sizes in decimal units, as in Finder (1 GB = 1000³ bytes); swap files on disk are shown under Disk.
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

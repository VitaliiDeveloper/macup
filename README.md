# macup

**English** · [Українська](README.uk.md) · [Русский](README.ru.md)

[![CI](https://github.com/VitaliiDeveloper/macup/actions/workflows/ci.yml/badge.svg)](https://github.com/VitaliiDeveloper/macup/actions/workflows/ci.yml)

One command to keep a developer's Mac up to date, clean and healthy. It updates your tools, clears caches that rebuild themselves, checks system health and security, and tracks changes over time.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/VitaliiDeveloper/macup/main/install.sh | bash
```

The installer asks for a language (English, Українська, Русский) and where your projects live, offers to install `mas` for App Store updates, and then offers a first check. It needs no sudo and no dependencies; the bash that ships with macOS is enough. What it changes:

- installs `~/.local/bin/macup`, replacing an older macup in `/usr/local/bin`, `/opt/homebrew/bin` or `~/.npm-global/bin`
- creates `~/.config/macup/config`, or keeps yours on reinstall
- adds `~/.local/bin` to `PATH` in `~/.zshrc` (and `~/.bash_profile`, if you have one) when it isn't there yet

Unattended:

```bash
curl -fsSL https://raw.githubusercontent.com/VitaliiDeveloper/macup/main/install.sh | bash -s -- --yes --lang en --projects "~/Code"
```

## Use

| Command | What it does |
|---|---|
| `macup` | Menu |
| `macup check` | Check everything, then pick what to clean (or nothing) |
| `macup all` | Updates + cleanup up to your level + checks |
| `macup update` · `macup clean` | Only updates · only cleanup (checks included) |
| `macup last` · `macup history` | Latest report · trends across runs |
| `macup tasks` · `macup config` | What runs and its ids · your settings |
| `macup lang [en\|uk\|ru]` | Interface language |
| `macup self-update` · `macup uninstall` | Update or remove macup |

Options: `--level safe|standard|aggressive` (what `clean`/`all` may remove), `--deep` (largest folders, including Application Support, old Downloads, project build artifacts), `--skip id,…`, `--only id,…` (groups work: `clean.*`), `--lang xx`, `--no-color`.

Start with `macup check`. It lists what can be cleaned, with sizes and levels, and lets you pick:

```
▸ What can be cleaned
    1  safe           3.1 GB  Xcode DerivedData
    2  safe           1.4 GB  uv cache
    3  standard       640 MB  Older Node.js versions (nvm): 20.5.0, 18.17.0
    4  aggressive     2.5 GB  Arc cache

Clean now? Numbers (1,3 or 2-5), a level (safe, standard, aggressive), or Enter to skip:
```

Every run ends with a summary and saves a report to `~/Library/Logs/macup/`:

```
━━━━━━━━━━━━━━━━ Summary ━━━━━━━━━━━━━━━━
  Updated: 2
    · Claude Code 2.1.280 → 2.1.286
    · Homebrew: 4 formulae, 1 casks
  Freed: 14.2 GB
  Free disk space: 212.4 GB (23%)
  Needs attention: 1
    ! Time Machine: last backup 2026-09-20 (11 days ago)
  Report: ~/Library/Logs/macup/macup_2026-10-01_14-05.md · 3m 12s
```

## What it does

- **Updates:** Claude Code (CLI, plugins, marketplaces), global npm packages, agent skills in `~/.agents`, Homebrew, App Store apps (with [`mas`](https://github.com/mas-cli/mas)), pipx, uv tools, rustup, Oh My Zsh, GitHub CLI extensions. macOS updates are reported, never installed.
- **Cleans, in three levels:**
  - 🟢 **safe** (default; rebuilds itself): Xcode DerivedData and SwiftUI previews, old DeviceSupport and device logs, simulator caches, simulators whose runtime is gone (also Xcode's parallel-test clones); SwiftPM, CocoaPods, Carthage, Homebrew, npm, pnpm, Yarn, pip, uv and Go caches; caches of VS Code, Cursor, Windsurf, Antigravity, Claude, Codex and Postman; Codex leftovers; old logs.
  - 🟡 **standard** (downloaded again on next use): Gradle, Android Studio, Maven; Docker build cache and dangling images; old Playwright/Puppeteer browsers; older patch versions in nvm, rbenv, pyenv, mise and asdf.
  - 🔴 **aggressive** (apps may be slow for a while or sign you out): browser caches (Arc, Chrome, Firefox, Edge, Brave, Opera, Vivaldi).
  - **Only when you pick them:** simulator runtimes (with last use and how many simulators need them), erasing a simulator's apps and data, simulators unused for 30 days; other big folders in `~/Library/Caches`; stale `node_modules`; the Trash. Running simulators are skipped.
- **Measures, never deletes:** render and preview caches of Final Cut Pro, Premiere/After Effects, DaVinci Resolve, Lightroom Classic and Camera Raw (with the app's own menu item to clear them), Codex chat history, AI models, Android SDK and emulators, Xcode Archives, simulators.
- **Checks:** uptime, disk space and SMART, memory and swap, CPU and throttling, battery; FileVault, Firewall, SIP, Gatekeeper, automatic updates, Time Machine; third-party and orphaned launch agents; Claude Code MCP servers; `brew doctor`; commands that cannot start because node or Python is gone, with a command that fixes it when there is one; Xcode and simulator runtimes; Docker; sizes of what macup never deletes.

Tools you don't have are skipped.

## Safety

- **Nothing changes without a command.** Updates and cleanup run only with `all`, `update`, `clean` or from the menu. Outside a terminal, plain `macup` only prints help, so scripts must say `macup all`.
- **`clean` and `all` stop at the `safe` level** unless you set `--level` or `clean_level`. A check deletes only what you pick, and items that are aggressive or opt-in ask for a yes.
- **Only listed cache folders, never what sits next to them.** Settings, chat history, sessions, virtualenvs, keystores, `gradle.properties`, Maven's `settings.xml`, browser profiles and passwords are never touched. Versions you pin (`.nvmrc`, `.tool-versions`, …) or use by default stay. Symlinks are never followed.
- **Apps that are open are skipped.** Close the app and run again.
- **`macup check` installs and upgrades nothing.** It does go online: it refreshes Homebrew's package list, asks npm, the App Store, Apple and GitHub for available versions, and briefly starts your MCP servers to test them.
- **Updates go to the latest version**, including new major versions of npm packages. If you pin versions, skip that task: `skip = update.npm`.
- **No sudo.** macup never calls it. A password prompt during a cask upgrade comes from that app's own installer.
- **`--deep` reads your whole home folder.** macOS may ask Terminal for access to Documents, Downloads or other apps' data; declining only shortens the scan.

## Configuration

`macup config` opens `~/.config/macup/config`:

```ini
language = en                          # en, uk, ru
skip = update.mas, check.docker        # tasks to never run; groups work: clean.*
enable = clean.stale_node_modules      # opt-in tasks
clean_level = safe                     # what clean/all may remove: safe, standard, aggressive
project_dirs = ~/Developer, ~/Code     # used by --deep and stale node_modules
device_support_days = 90
stale_project_days = 90
simulator_days = 30
keep_reports_days = 60
```

## Files

| Path | Contents |
|---|---|
| `~/.local/bin/macup` | The script |
| `~/.config/macup/config` | Settings |
| `~/Library/Logs/macup/` | Reports (`.md`) and command logs (`.log`) |
| `~/Library/Application Support/macup/history.csv` | Run history for trends |

`macup uninstall` asks before removing the script, and again before removing your settings, history and reports. It leaves the `PATH` line that the installer may have added to `~/.zshrc`, because other tools use `~/.local/bin` too.

## Development

The source is in `src/` (the order is listed in `build.sh`; translations in `src/i18n/translations.json`, embedded at build time). After editing, run `./build.sh` to produce the single-file `macup` that users install, then `tests/run.sh`; both run in CI. New caches usually need one line in the tables at the top of `src/cleaners.sh`.

## License

[MIT](LICENSE)

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
| `macup check` | Check everything; installs and deletes nothing |
| `macup all` | Updates + safe cleanup + checks |
| `macup update` · `macup clean` | Only updates · only cleanup (checks included) |
| `macup last` · `macup history` | Latest report · trends across runs |
| `macup tasks` · `macup config` | What runs and its ids · your settings |
| `macup lang [en\|uk\|ru]` | Interface language |
| `macup self-update` · `macup uninstall` | Update or remove macup |

Options: `--deep` (largest folders, old Downloads, project build artifacts), `--skip id,…`, `--only id,…` (groups work: `clean.*`), `--lang xx`, `--no-color`.

Start with `macup check`. Every run ends with a summary and saves a report to `~/Library/Logs/macup/`:

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
- **Cleans, by default:** Xcode DerivedData and SwiftUI previews (skipped while Xcode is open), DeviceSupport older than 90 days, old device logs, unavailable simulators, simulator caches; SwiftPM, CocoaPods, Carthage, Homebrew, npm, Yarn, pnpm, pip, uv and Go caches; app logs and crash reports older than 30 days; the Quick Look cache.
- **Cleans, only if you enable it:** `clean.stale_node_modules` (projects untouched for 90 days) and `clean.trash`.
- **Checks:** uptime, disk space and SMART, memory and swap, CPU and throttling, battery; FileVault, Firewall, SIP, Gatekeeper, automatic updates, Time Machine; third-party and orphaned launch agents; Claude Code MCP servers; `brew doctor`; Xcode and simulator runtimes; Docker; sizes of what macup never deletes.

Tools you don't have are skipped.

## Safety

- **Nothing changes without a command.** Updates and cleanup run only with `all`, `update`, `clean` or from the menu. Outside a terminal, plain `macup` only prints help, so scripts must say `macup all`.
- **Cleanup removes only what rebuilds or re-downloads itself.** Xcode Archives, the Trash, Downloads and simulator devices are measured, never deleted.
- **`macup check` installs, upgrades and deletes nothing.** It does go online: it refreshes Homebrew's package list, asks npm, the App Store, Apple and GitHub for available versions, and briefly starts your MCP servers to test them.
- **Updates go to the latest version**, including new major versions of npm packages. If you pin versions, skip that task: `skip = update.npm`.
- **No sudo.** macup never calls it. A password prompt during a cask upgrade comes from that app's own installer.
- **`--deep` reads your whole home folder.** macOS may ask Terminal for access to Documents, Downloads or other apps' data; declining only shortens the scan.

## Configuration

`macup config` opens `~/.config/macup/config`:

```ini
language = en                          # en, uk, ru
skip = update.mas, check.docker        # tasks to never run; groups work: clean.*
enable = clean.stale_node_modules      # opt-in tasks
project_dirs = ~/Developer, ~/Code     # used by --deep and stale node_modules
device_support_days = 90
stale_project_days = 90
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

## License

[MIT](LICENSE)

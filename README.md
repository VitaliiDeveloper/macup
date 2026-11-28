# macup

[![CI](https://github.com/VitaliiDeveloper/macup/actions/workflows/ci.yml/badge.svg)](https://github.com/VitaliiDeveloper/macup/actions/workflows/ci.yml)

One command to update, clean and check a developer's Mac.

![macup check: a numbered list of what can be cleaned, leftovers of deleted apps explained in plain words, startup items, then the pick](docs/images/check.svg)

## Why

A developer's Mac has tools from many package managers, and each one updates with its own command.
Caches from Xcode, simulators, package managers and Electron apps keep growing.
macup updates all of them, deletes only caches that rebuild themselves (what is left of deleted apps goes to the Trash, and only when you pick it), and checks the system's health and security in one run.

## Features

- **Updates in one go:** Homebrew, App Store apps (with [`mas`](https://github.com/mas-cli/mas)), Claude Code and its plugins, global npm packages, agent skills in `~/.agents`, pipx, uv tools, rustup, Oh My Zsh, GitHub CLI extensions, Grok CLI, Antigravity CLI, global pnpm packages, Bun, Deno, `cargo install` programs (with [`cargo-update`](https://github.com/nabijaczleweli/cargo-update)), mise tools, asdf plugins, VS Code, Cursor, Windsurf and VSCodium extensions, Google Cloud SDK components, .NET global tools, Composer global packages. Ruby gems are opt-in.
- **Apps that update themselves are listed when they fall behind.** Apps installed from a download (Cursor, VS Code, Postman, …) are compared with the Homebrew catalog; macup installs nothing for them.
- **macOS updates are reported, never installed.**
- **Cleanup in three levels:** `safe` (rebuilds itself, the default), `standard` (downloaded again), `aggressive` (browser caches; apps may sign you out).
- **Check first, pick later:** `macup check` changes nothing. It lists what can be cleaned, with sizes, and lets you pick.
- **Health and security checks:** disk space and SMART, memory, CPU, battery, FileVault, Firewall, SIP, Gatekeeper, Time Machine, Remote Login, Screen Sharing and Remote Management, launch agents, Claude Code MCP servers, `brew doctor`, commands that cannot start, a GitHub CLI login that stopped working, signing certificates about to expire, apps that keep crashing, core dumps, folders in `PATH` that do not exist.
- **Leftovers of deleted apps:** an app dragged to the Trash often leaves its updater running, its folders and its data. `macup check` lists them in plain words (what it is, why it can go) and moves the ones you pick to the Trash.
- **Reports and trends:** every run saves a Markdown report. `macup history` shows free space, swap and battery across runs.
- **For scripts and other programs:** `--quiet` prints only the summary, `--json` prints the whole result as JSON, `--pick` cleans exactly the items you name, and the exit status is 3 when a step failed.
- **Tidy with its own files:** macup keeps its reports for 30 days and never more than 20 runs, and removes its leftover temp files.
- **Optional schedule:** `macup schedule weekly` runs a check on its own and shows a notification when something needs a look. Off unless you turn it on.
- **Interface in English, Ukrainian and Russian.**
- **No dependencies:** one universal binary for Apple silicon and Intel, with nothing to install next to it.
- **Tools you don't have are skipped.**

<details>
<summary>What each level cleans</summary>

- 🟢 **safe:** Xcode DerivedData, SwiftUI previews, old DeviceSupport, old device logs, simulator caches, unavailable simulators (also Xcode's test clones); SwiftPM, CocoaPods, Carthage, Homebrew, npm, pnpm, Yarn, Bun, Deno (its `localStorage` and KV data stay), pip, Poetry (its virtualenvs stay), uv and Go build caches; expired provisioning profiles; caches of Electron apps (VS Code, Cursor, Claude, Slack, Discord and others, found by folder layout); leftovers of AI coding tools: Codex temporary files, unfinished downloads and plugin backups, old Grok and Antigravity CLI versions, edit backups of deleted Claude Code sessions (backups and unfinished writes go to the Trash); logs and crash reports older than 30 days, npm and Gradle daemon logs too; Quick Look cache.
- 🟡 **standard:** Gradle, Android Studio, JetBrains IDEs, Maven, Cargo registry and git downloads, the Go module cache, the npx cache; Docker build cache and dangling images; old Playwright, Puppeteer and Cypress builds; older patch versions in nvm, fnm, Volta, rbenv, pyenv, mise and asdf; Codex plugin catalogs of accounts unused for 30 days.
- 🔴 **aggressive:** browser caches (Chrome, Arc, Edge, Brave, Firefox, Opera, Vivaldi and other Chromium or Firefox-based browsers). Profiles, passwords and history are never touched.
- **Only when you pick them** (or turn them on with `enable`): simulator runtimes, erasing a simulator, simulators unused for 30 days, other big folders in `~/Library/Caches`, stale `node_modules` and other stale build folders (`Pods`, `.build`, `.dart_tool`, `.next`, Rust and Maven `target`, Gradle `build`), Docker images no container uses, stopped Docker containers, Homebrew packages nothing needs any more, the Trash; what VS Code, Cursor and similar editors keep for a workspace whose folder in your home folder is gone, AI chats included (to the Trash).
- **Only when you pick them after `macup check`:** leftovers of deleted apps — background programs and their folders, the app's data (settings, history, saved passwords), and system services (these ask for your Mac password once). They go to the Trash, so you can put them back.
- **Only when you pick them, never with `enable`:** containers of your own dev builds whose app is gone (`dev_container_prefixes`). What is inside goes to the Trash; macOS keeps the empty folder.
- **Measured, never deleted:** Xcode Archives, simulator devices, Flutter pub-cache, Codex and Claude Code chat history, Claude's Cowork virtual machine, AI models, Android SDK and emulators, iPhone and iPad backups, Docker Desktop's disk image, Docker volumes, virtual machines (Colima, Lima, Podman, minikube, Parallels, VMware); render caches of Final Cut Pro, Premiere/After Effects, DaVinci Resolve, Lightroom Classic and Camera Raw (with the app's own menu item to clear them).

Run `macup tasks` for the full list with task ids.

</details>

### Safety

- **Nothing changes without a command.** Only `all`, `update`, `clean`, the menu, or your pick after a check change anything.
- **`macup check` installs and deletes nothing** on your Mac. It tidies only macup's own old reports. It does go online: it asks Homebrew, npm, the App Store, Apple and GitHub for versions, and briefly starts your MCP servers to test them.
- **`clean` and `all` stop at `safe`** unless you set `--level` or `clean_level`.
- **Only listed cache folders.** Settings, chat history, keys, `gradle.properties`, Maven's `settings.xml`, browser profiles and pending app updates are never touched. Symlinks are never followed. The exceptions are the data of a deleted app, the containers of your own dev builds whose app is gone, and the data of an editor workspace whose folder is gone, only when you pick them; they go to the Trash.
- **Pinned versions stay.** Versions named in `.nvmrc`, `.tool-versions`, `.python-version`, `package.json` (`volta`, `engines`), virtualenvs and similar files are kept. A pin without the patch (`20.5`) keeps the newest `20.5.x`.
- **Apps that are open are skipped.** The summary lists them. Xcode's caches are also left alone while an `xcodebuild` runs, Cargo's while `cargo` runs, the npx cache while anything started with `npx` runs (MCP servers), Claude Code's while Claude Code or Claude.app runs, and Codex's while Codex or ChatGPT.app runs. A check already marks such items in its list and leaves them out of what could be freed.
- **Build folders in projects are deleted only on request,** only next to the file that builds them again (`target` next to `Cargo.toml`), never when git tracks files in them, and never when they were built recently.
- **Docker volumes are never deleted.**
- **One run at a time.** A second `macup` started while one is running refuses to start.
- **A command that hangs is stopped** after `step_timeout_minutes` (60), together with what it started, and the run goes on.
- **Aggressive and opt-in picks ask for a yes.**
- **No sudo, with two exceptions** (`sudo macup` refuses to run): App Store updates need your Mac password (`mas` requires it), and macup asks for it before installing them. It makes sudo forget the password right after them, so the updaters that run next cannot use it. A cask's own installer may also ask; that password is forgotten after `brew upgrade` too. Picked system leftovers of deleted apps ask for it once, show the exact commands first, and sudo forgets it right after; scheduled and `--quiet` runs never ask.
- **Fixes are printed, never run.** For example, `brew link --overwrite node` for a command whose interpreter is gone. The exception: when you pick a leftover background program, macup stops it (`launchctl bootout`) before moving it to the Trash.

## Requirements

- macOS 13 Ventura or later, on Apple silicon or Intel: macup is one universal binary. The tests run on macOS 15 and 26 on Apple silicon; macOS 13 and 14 and Intel Macs are built for but not tested. On macOS 12 or older the installer and `self-update` keep macup 2.9.2, the last version that runs there.
- `curl`, which ships with macOS, for the installer and `self-update`.
- Optional: `git`, also from the Command Line Tools. Stale build folders are offered only when git can tell that it tracks no file in them.
- Optional: the tools macup updates (Homebrew, `mas`, Claude Code, npm, …). Missing ones are skipped.

## Installation

**Installer (recommended):**

```bash
curl -fsSL https://raw.githubusercontent.com/VitaliiDeveloper/macup/main/install.sh | bash
```

It asks for a language and your project folders, offers to install `mas`, then offers a first check. What it changes:

- installs `~/.local/bin/macup`: the binary of the latest release (`macup-<version>-macos-universal.tar.gz` on the GitHub release), checked against its published SHA-256 and run once before it replaces anything, so a copy you already have keeps working if the download fails
- removes older copies from `/usr/local/bin`, `/opt/homebrew/bin` and `~/.npm-global/bin`
- creates `~/.config/macup/config`, or keeps yours on reinstall
- adds `~/.local/bin` to `PATH` in `~/.zshrc` (and `~/.bash_profile`, if you have one) when it is not there yet

**Unattended:**

```bash
curl -fsSL https://raw.githubusercontent.com/VitaliiDeveloper/macup/main/install.sh | bash -s -- --yes --lang en --projects "~/Code"
```

Installer options: `--lang en|uk|ru`, `--projects "~/Code, ~/Work"`, `--prefix DIR`, `--yes`.

**Homebrew:**

```bash
brew install vitaliideveloper/macup/macup
```

It installs the same release binary. There are no installer questions here. The language follows macOS. Use `macup lang` to change it and `macup config` to set your project folders.

There is no download to open from a browser: the binary is ad hoc signed, not notarized, and macOS quarantines what a browser downloads. The installer and Homebrew don't set that flag.

**From source:**

```bash
git clone https://github.com/VitaliiDeveloper/macup.git
```

```bash
cd macup && ./build.sh && ./install.sh
```

This needs Xcode or the Command Line Tools (Swift 5.9 or later). `./install.sh` in a checkout installs the binary you just built.

**Update or remove:**

```bash
macup self-update
```

```bash
macup uninstall
```

`self-update` installs the latest release from GitHub when it is newer: the binary attached to that release, checked against its published SHA-256 and required to report that version. It then takes the old file's place by a rename, so a macup that is running keeps its file. For a Homebrew install it tells you to run `brew upgrade macup`.
`uninstall` lists everything it will remove and asks once (`--yes` skips the question): the binary, settings, history, reports, the schedule and the installer's `PATH` line. It keeps the `PATH` line if other programs live in that folder. For a Homebrew install it runs `brew uninstall macup`.

**From 2.9 to 3.0:** run `macup self-update` as usual (`brew upgrade macup` for Homebrew). Version 2.9 was a bash script; 3.0 is a binary, so 2.9's self-update installs a small bootstrap first. Its next run does the rest:

- downloads the 3.0 binary, checks its SHA-256 and that it runs, replaces itself with it and runs the command you typed;
- points a schedule from `macup schedule` at the binary. A scheduled check that comes first still runs, from a temporary copy, and its log says to run macup once in Terminal to finish;
- in the minutes between a release and its upload, says the release is not published yet and changes nothing;
- on macOS 12 or older, installs 2.9.2 instead.

With Homebrew, the first time you run macup 3.0 in Terminal, it moves the schedule onto the binary.

## Usage

Start with `macup check`. It lists what can be cleaned, then lets you pick (the screenshot at the top).

Every run ends with a summary and saves a report to `~/Library/Logs/macup/`:

![macup clean: what each cleaner freed, then the summary with freed space and free disk space](docs/images/summary.svg)

Plain `macup` opens a menu:

![The macup menu: check, update and clean, deep check, history, reports, settings, language](docs/images/menu.svg)

### Commands

| Command | What it does |
|---|---|
| `macup` | Interactive menu (outside a terminal it only prints help) |
| `macup check` | Check updates, health and security, list what can be cleaned, let you pick (Enter = nothing) |
| `macup all` | Updates + cleanup up to your level + checks |
| `macup update` | Updates + checks |
| `macup clean` | Cleanup + checks |
| `macup last` | Print the latest report |
| `macup history` | Trends across runs: free space, swap, battery, freed space |
| `macup reports` | How many reports there are, their size, the oldest and newest. `macup reports clean` removes them all (asks first; `--yes` does not ask), `macup reports open` shows the folder in Finder |
| `macup tasks` | Every task id and whether it is on |
| `macup config` | Create or open the config file |
| `macup lang [en\|uk\|ru]` | Change the interface language |
| `macup schedule [weekly\|daily\|off]` | Optional: run `macup check` on a schedule, with a notification. Without a word it shows the current state |
| `macup self-update` | Install the latest macup from GitHub |
| `macup uninstall` | Remove macup and everything it made |
| `macup help` · `macup version` | Help · version |

### Options

| Option | What it does |
|---|---|
| `--level safe\|standard\|aggressive` | What `clean` and `all` may remove (default: `safe`) |
| `--deep` | Also list the largest folders, old and big files in Downloads, project build artifacts (`node_modules`, `Pods`, `.build`, Rust and Maven `target`, Gradle `build`, `.next`, `.venv`). On its own (`macup --deep`) it is a deep check |
| `--skip id,…` | Skip tasks for this run. Groups work: `'clean.*'` |
| `--only id,…` | Run only these tasks |
| `--enable id,…` | Turn on opt-in tasks for this run, e.g. `--enable clean.trash` |
| `--lang en\|uk\|ru` | Language for this run |
| `--no-color` | Plain output |
| `--quiet` | Print only the summary; the rest is in the report |
| `--json` | Print the whole result as one JSON object. Also `macup tasks --json`, `macup history --json` and `macup reports --json` |
| `--pick key,…` | Clean exactly these items of `macup check --json`, without asking |
| `--notify` | Show a macOS notification when something needs attention (the schedule uses it) |
| `--yes` | `uninstall` without the question |

Exit status: `0` the run finished · `3` an update or cleanup step failed · `2` bad arguments · `1` unknown command, or macup is already running · `130` interrupted. Warnings from the health checks do not change it; read them from `--json` (`needs_attention`).

### Examples

```bash
macup check                         # see what's up; nothing changes unless you pick
macup all                           # update everything, clean the safe level
macup clean --level standard        # also Gradle, Maven, Docker, old Node/Ruby/Python patches
macup update --skip update.mas      # updates without the App Store
macup check --only check.security   # only the security checks
macup check --deep                  # find what fills the disk
macup all --no-color                # from a script: plain `macup` only prints help there
macup check --json                  # everything a check found, for a script or another program
macup clean --enable clean.stale_artifacts --level standard   # also stale build folders in projects
macup schedule weekly               # optional: a check every Monday at 10:00, with a notification
```

Quote task groups in zsh: `--skip 'clean.*'`.

### For scripts and other programs

A program that shows macup's results its own way (a menu bar app, a GUI) needs no terminal output to parse:

| Command | What it prints |
|---|---|
| `macup check --json` | One object: `free_kb`, `total_kb`, `needs_attention`, `updated`, `failed_steps`, `report` (and `log`, the same path: the command output is at the end of the report); `items`, every line of the run with its `section`, `kind` (`ok`, `info`, `warn`, `fail`), `text` and `details`; `cleanable`, every item that can be cleaned with its `key`, `task`, `level`, `kb`, `text`, `opt_in` (cleaned only when picked or enabled) and `in_clean` (a plain `macup clean` takes it), `hidden` (under 1 MB, so the terminal list leaves it out; it can still be picked) and `busy` (in use right now: the cleanup skips it, and `could_free_kb` and `could_free_more_kb` leave it out) |
| `macup clean --pick key,… --json` | Cleans exactly the items with these keys, opt-in and aggressive ones too, runs no update and no check, and prints the same object. A key stays the same from run to run. A key that is no longer there is reported and the exit status is 3 |
| `macup all --json`, `update`, `clean` | The same object after the run; `cleanable` is empty |
| `macup tasks --json` | Every task: `id`, `group`, `default`, `on`, `text`; and the path of the config |
| `macup history --json` | The runs of `history.csv` as objects |
| `macup reports --json` | `folder`, `count`, `kb`, and `reports`: each with `file`, `date`, `mode` and `kb` |

`--pick` asks nothing: the program that calls it shows the choice to the person first. Texts come in the language of `--lang` or the config. Every object has `"schema": 1`; new fields may be added, and the number changes only when an existing field does.

### Schedule (optional)

macup runs only when you start it. `macup schedule weekly` (or `daily`) adds a LaunchAgent that runs `macup check --quiet --notify` at 10:00, on Mondays or every day. A check installs and deletes nothing. You get a notification only when something needs attention or more than 1 GB can be freed; `macup last` shows the report. `macup schedule off` removes it, and so does `macup uninstall`.

## Configuration

`macup config` opens `~/.config/macup/config` in `$VISUAL` or `$EDITOR` (default: `nano`). Defaults:

```ini
language = en                 # en, uk, ru (first run: your macOS language)
skip =                        # tasks to never run; groups work: update.*, clean.*, check.*
enable =                      # opt-in tasks, e.g. clean.stale_node_modules, clean.stale_artifacts, clean.trash
clean_level = safe            # what clean/all may remove: safe, standard, aggressive
device_support_days = 90      # delete DeviceSupport folders older than this
simulator_days = 30           # offer simulators unused for this long
stale_project_days = 90       # a project is stale after this many days without changes
project_dirs = ~/Developer, ~/Projects, ~/Code, ~/dev, ~/src, ~/repos, ~/work
dev_container_prefixes =      # bundle ids of your dev builds, e.g. dev.myapp
keep_reports_days = 30        # delete macup reports older than this
keep_reports = 20             # and never keep more than this many runs (one report file per run)
step_timeout_minutes = 60     # stop an update or cleanup command that runs longer (App Store installs: four times as long)
```

`project_dirs` is used by `--deep`, by stale `node_modules` and build folders, and to find version pins.

`dev_container_prefixes` names your own bundle ids (`dev.myapp` also covers `dev.myapp.demo`). A sandboxed build leaves a container in `~/Library/Containers`, and it stays after the build is gone (a cleaned DerivedData, a test bundle id). `macup check` lists each one whose app Spotlight cannot find, with its size and last change, for you to pick; `clean` and `all` never delete them. What is inside goes; macOS keeps the empty folder and its `.com.apple.containermanagerd.metadata.plist`, and refuses to remove them, so macup leaves them and does not offer them again. A container stays while its parent id has an app (`dev.myapp.share` while `dev.myapp` exists), because Spotlight does not index app extensions, and while something has a file open in it. A container holds the app's data, so nothing is offered without this setting, `com.apple.*` never is, and with Spotlight off nothing is offered.

Environment variables: `MACUP_LANG` (language), `NO_COLOR` (plain output), `XDG_CONFIG_HOME` (config location).

| Path | Contents |
|---|---|
| `~/.local/bin/macup` | The binary |
| `~/.config/macup/config` | Settings |
| `~/Library/Logs/macup/` | One report per run (`.md`, with what the commands printed at the end), kept for `keep_reports_days` and at most `keep_reports` runs; `macup reports clean` removes them. `schedule.log`: the scheduled check's output, its last 200 lines |
| `~/Library/Application Support/macup/history.csv` | Run history for `macup history`, its last 500 runs |
| `~/Library/Caches/macup/` | The Homebrew cask catalog for the apps check |
| `~/Library/LaunchAgents/com.vitaliideveloper.macup.plist` | The schedule, only after `macup schedule weekly` or `daily` |

## Tech stack and architecture

- **Bash**, compatible with the stock macOS bash 3.2. Small embedded Python 3 snippets read JSON.
- **Single-file build:** the source lives in `src/*.sh`. `build.sh` joins the parts in a fixed order and embeds the translations from `src/i18n/translations.json`. The result is the one `macup` file users install, and `macup.sha256`, which `self-update` and the installer check the download against.
- **Task registry:** every step has an id (`check.*`, `update.*`, `clean.*`) in one table in `src/core.sh`. `--skip`, `--only`, `skip` and `enable` all use these ids.
- **Cleaners as data:** tables at the top of `src/cleaners.sh` (`CACHE_DIRS`, `TOOL_CACHES`, `ELECTRON_APPS`, `BROWSERS`). A new cache is usually one line.
- **Two-phase cleanup:** cleaners first register candidates with a size and level, then the chosen ones run. Every path is checked against an allow-list again right before it is deleted.
- **Tests:** `tests/run.sh` runs macup against throwaway fake home folders, with fake `pgrep`, `lsof`, `xcrun`, `mas`, `docker`, `security`, `curl`, `launchctl` and system tools (`softwareupdate`, `system_profiler`, `memory_pressure`). It checks that each level deletes exactly the expected files and that protected files survive.
- **CI (GitHub Actions):** ShellCheck on Ubuntu; a bash 3.2 syntax check, the tests, an install and smoke runs on macOS 15 and 26, Apple silicon.

Development:

```bash
./build.sh
```

```bash
tests/run.sh
```

Edit `src/`, run `./build.sh` to rebuild `macup`, then run `tests/run.sh` on macOS. `./build.sh --check` fails if `macup` is out of date.

On the `swift/main` branch (the port to Swift, see [docs/swift-port-plan.md](docs/swift-port-plan.md)) `./build.sh` also builds the Swift package, whose binary carries the bash build and runs what is not ported yet through it; neither `macup` nor the binary is committed there. `swift test` runs the unit tests, `MACUP_BUILD=swift tests/run.sh` runs the suite on the binary, and `tests/diff.sh` compares the two builds case by case. Release notes are in [CHANGELOG.md](CHANGELOG.md). After tagging a release and pushing the tag, `tools/bump-formula.sh X.Y.Z [TAP_DIR]` points the Homebrew tap's `Formula/macup.rb` at it (tarball URL and SHA-256), shows the diff and prints the commit and push commands; `--commit` commits in the tap, nothing is ever pushed. The tap defaults to `~/Documents/Work-Projects/homebrew-macup`. `tools/screenshots.sh` makes the screenshots in `docs/images` from the macup in the checkout, run against a made-up Mac (fake home, sizes and free space), so nothing of your own Mac shows up.

## License

[MIT](LICENSE)

## Author

**Vitalii Lavreniuk** · [GitHub](https://github.com/VitaliiDeveloper) · [LinkedIn](https://www.linkedin.com/in/vitalii-lavreniuk)

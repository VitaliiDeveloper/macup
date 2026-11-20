# Leftovers of Deleted Apps Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `macup check` finds launch agents, updater folders, app data and system services left by deleted apps, explains each in plain words, and moves the picked ones to the Trash (one sudo prompt for system items).

**Architecture:** A new `src/leftovers.sh` (built after `cleaners`, before `report`) scans installed apps and launch plists once, keeps results in `O_*` arrays, registers pick-only candidates of a new key kind `orph:<n>` / `odata:<n>`, and `check.startup` in `report.sh` prints from the same arrays. Candidates gain a detail field shown under each entry. Everything removed goes to `~/.Trash` through one guarded `to_trash` function.

**Tech Stack:** bash 3.2 (no associative arrays, no `mapfile`), `plutil`, `codesign`, `launchctl`, `sfltool`, `sudo`; tests in `tests/run.sh` with fake home and stubbed commands.

**Spec:** `docs/superpowers/specs/2026-11-20-orphan-launch-agents-design.md`

## Global Constraints

- Runs on `/bin/bash` 3.2; `./build.sh --check`, `bash -n`, `shellcheck -S warning` must pass.
- Edit `src/`, then `./build.sh`; add `leftovers` to `ORDER` in `build.sh` between `cleaners` and `report`.
- Every UI string goes through `_`/`_f`/`info`/`warn` and has `uk` and `ru` in `src/i18n/translations.json` with the same `%s` placeholders (`tests/translations.py`).
- Never Spotlight (`mdfind`) for installed apps; read `Contents/Info.plist` on disk.
- Nothing is deleted with `rm`: only `to_trash`. Never follow symlinks; refuse paths with `..`.
- No sudo and no Containers / Group Containers access unless interactive (`[ -t 0 ] && [ -t 1 ]`) and not `--quiet`/`--json`.
- Both new tasks are off by default, pick-only (`C_AUTO=0`), level 3.
- Test roots are overridable: `MACUP_APPS` (default `/Applications:$HOME/Applications`), `MACUP_SYSLIB` (default `/Library`).
- Comments only for a why the code cannot show.

## Review Focus

1. Label with spaces or quotes in a plist path (`Application Support/Some App/`): paths are never word-split — test in Task 2 uses a vendor folder with a space.
2. App reinstalled between check and pick: the re-check drops it — test in Task 2.
3. Trash already holds a file of the same name: `to_trash` picks a new name, never overwrites — test in Task 2.
4. User picks a 🔑 item and gives a wrong password: those items are skipped with a message, user items still go — test in Task 4.
5. `sfltool` missing or output format changed: check prints no BTM lines and no errors — test in Task 5.

---

### Task 1: Detection and `check.startup` report

**Files:**
- Create: `src/leftovers.sh`
- Modify: `build.sh` (ORDER), `src/core.sh` (TASKS: add two lines after `clean.trash`), `src/report.sh:53-71` (STARTUP section)
- Modify: `src/i18n/translations.json`
- Test: `tests/run.sh` (new block `# --- leftovers of deleted apps`), stubs at top of `tests/run.sh`

**Interfaces:**
- Produces (globals, newline-separated or indexed arrays, bash 3.2):
  - `apps_scan` → fills `APPS` lines `bundleid_lowercase|teamid|appname` (team ids only filled lazily by `apps_teams` when `O_N>0` suspects).
  - `vendor_of <id>` → prints first two dot components lowercased, or nothing if fewer than two.
  - `vendor_installed <vendor>` → true if any `APPS` id starts with `<vendor>.` or equals it.
  - `team_installed <team>` → true if any `APPS` team equals it.
  - `team_of <path>` → Team ID from `codesign -dv` (`TeamIdentifier=`), empty if unsigned/unreadable.
  - `signer_of <path>` → human vendor from `Authority=Developer ID Application: <Name> (<TEAM>)`, suffixes ` Inc.`, `, Inc.`, ` LLC`, ` Ltd.` stripped.
  - `leftovers_scan` → fills `O_N` and arrays `O_PLIST[] O_LABEL[] O_PROG[] O_REASON[] O_SYS[] O_VENDOR[] O_NAME[] O_DIR[]`; `O_REASON` ∈ `empty|missing|gone|broken`; `O_SYS=1` for `$MACUP_SYSLIB/…`; `O_DIR` = program's own folder (see Task 2), may be empty.
- Task registry lines (exact):
  - `clean.orphan_agents|off|Background programs of deleted apps and their folders (only when you pick them)`
  - `clean.orphan_data|off|Data of deleted apps: settings, history, saved passwords (only when you pick them)`

- [ ] **Step 1: Add stubs and a fixture to `tests/run.sh`**

Stubs in `$W/bin`: `codesign` prints `TeamIdentifier=<T>` and `Authority=Developer ID Application: <Name> (<T>)` from `FAKE_SIGN` lines `path-prefix|TEAM|Name` (first prefix match of its last argument), else exits 1. `plutil` stays real. A function `leftovers_home H` builds:
  - `$H/Apps/Steam.app` (`CFBundleIdentifier com.valvesoftware.steam`), `$H/Apps/iStat.app` (`imagetasks.iStatistica`), `$H/Apps/Vendor Folder/Tool.app` (`com.tool.app`, one level down).
  - `~/Library/LaunchAgents/ai.perplexity.CometUpdater.wake.plist` → program `~/Library/Application Support/Perplexity/CometUpdater/Current/CometUpdater.app/Contents/MacOS/CometUpdater` (exists), `AssociatedBundleIdentifiers` `ai.perplexity.CometUpdater`.
  - `~/Library/LaunchAgents/ai.perplexity.keystone.agent.plist`: `<dict/>`.
  - `~/Library/LaunchAgents/com.locked.empty.plist`: `<dict/>` with `chflags uchg`.
  - `~/Library/LaunchAgents/com.valvesoftware.steamclean.plist` → `~/Library/Application Support/Steam/SteamApps/steamclean` (exists).
  - `~/Library/LaunchAgents/com.imagetasks.helper.plist` → `~/Library/Application Support/iStat Helper/helper` (exists); `FAKE_SIGN` gives it and `iStat.app` team `NF7JU763MN`.
  - `~/Library/LaunchAgents/homebrew.mxcl.redis.plist` → `/opt/homebrew/opt/redis/bin/redis-server`.
  - `~/Library/LaunchAgents/com.me.script.plist` → `~/Library/pnpm/run.sh` (exists).
  - `~/Library/LaunchAgents/com.gone.thing.plist` → `/Applications/Gone.app/Contents/MacOS/Gone` (missing).
  - `~/Library/LaunchAgents/broken.plist`: text `not a plist`.
  Run with `MACUP_APPS="$H/Apps" MACUP_SYSLIB="$H/SysLib"`. Clean up `uchg` in the `trap` (`chflags -R nouchg "$W"`).

- [ ] **Step 2: Write the failing test**

```bash
leftovers_home "$W/lo"; env HOME="$W/lo" MACUP_APPS="$W/lo/Apps" MACUP_SYSLIB="$W/lo/SysLib" FAKE_SIGN="$FS" \
  /bin/bash "$M" check --only check.startup --no-color </dev/null >"$W/lo.out" 2>&1
for l in ai.perplexity.CometUpdater.wake ai.perplexity.keystone.agent com.gone.thing; do
  grep -q "$l" "$W/lo.out" || fail "leftovers: $l not reported"; done
for l in steamclean com.imagetasks.helper homebrew.mxcl.redis com.me.script com.locked.empty; do
  tr -d '\r' <"$W/lo.out" | grep -A99 'Leftovers of deleted apps' | grep -q "$l" && fail "leftovers: live $l reported"; done
grep -q 'broken.plist.*cannot be read' "$W/lo.out" || fail "leftovers: broken plist"
```
End the block with one `pass "leftovers: report flags exactly the orphans"` when none failed.

- [ ] **Step 3: Run it to see it fail**

Run: `tests/run.sh 2>&1 | grep leftovers` — Expected: FAIL lines.

- [ ] **Step 4: Implement detection in `src/leftovers.sh`**

Rules (spec "Orphaned launch item"): owner ids = every `AssociatedBundleIdentifiers` entry + `Label`; `empty` = parses, no `Label`, no program, no `uchg` flag (`ls -lO`); `broken` = `plutil -lint` fails (reported, never a candidate); `missing` = absolute program that does not exist; `gone` = program under a `.app`, `*/Library/Application Support/`, or `~/Library/<Name>/` with `<Name>` equal (case-insensitive) to a label component, and not `team_installed`, and no owner vendor `vendor_installed`. Skip `com.apple.*` and `$SCHED_LABEL`. App roots from `MACUP_APPS` (colon list), each scanned at depth 1–3 for `*.app`, not descending into `.app`. Run `leftovers_scan` once when `task_allowed check.startup || task_allowed clean.orphan_agents || task_allowed clean.orphan_data`.

- [ ] **Step 5: Replace the STARTUP orphan block in `report.sh`**

Keep the background-services count. Then section line `warn 'Leftovers of deleted apps: %s (macup check lets you pick them)' N` and one `sub` line per item `"<name> · <label> — <reason text>"`, reason texts: `'app is not installed'`, `'its program is gone'`, `'empty file'`. `broken`: `info '%s cannot be read (not a valid plist)'`. For `O_SYS=1` print the commands from Task 4 instead of the pick hint (Task 4 fills them in; here print the `sub` line only).

- [ ] **Step 6: Translations, build, run**

Add strings to `translations.json`, `./build.sh`, `tests/run.sh` — Expected: `PASS leftovers: report flags exactly the orphans`, all other tests unchanged.

- [ ] **Step 7: Commit**

```bash
git add src/leftovers.sh src/report.sh src/core.sh build.sh src/i18n/translations.json macup macup.sha256 tests/run.sh
git commit -m "check.startup: leftovers of deleted apps found by signing team and vendor"
```

---

### Task 2: `clean.orphan_agents` with plain-language entries

**Files:**
- Modify: `src/cleanup.sh` (`cand` gets a 10th arg, array `C_INFO`; `list_cands` prints it and a heading; `run_key` cases `orph:*`)
- Modify: `src/leftovers.sh`, `src/i18n/translations.json`
- Test: `tests/run.sh`

**Interfaces:**
- Consumes: `leftovers_scan` arrays, `vendor_installed`, `team_installed`.
- Produces:
  - `cand … [info]` — 10th parameter, lines separated by `\n`, stored in `C_INFO[]`.
  - `to_trash <path> [sudo]` → moves to `$HOME/.Trash/<basename>`, or `<basename> 2`, `3`… if taken; refuses symlink, `..`, and any path not in `O_ALLOW` (newline list, exact match); appends refusals to `$RAW`; returns 1 on refuse/fail.
  - `orph_still <n>` → true if plist still exists, owner still not installed (fresh `apps_scan`), and `running "$(basename "${O_PROG[n]}")"` is false.
  - `O_DIR[n]`: first folder below `Application Support/<X>/` or `~/Library/<Name>/` containing the program (`…/Perplexity/CometUpdater`); parent `<X>` added to the move only if empty afterwards.

- [ ] **Step 1: Write the failing tests**

With `leftovers_home` plus `Application Support/Perplexity/Other Product/data` added in a second variant:
  - pick the `Perplexity` entry, answer `y` → `~/Library/LaunchAgents/ai.perplexity.CometUpdater.wake.plist` and `Application Support/Perplexity/CometUpdater` are in `~/.Trash`, `Application Support/Perplexity` is gone (was empty after) in variant 1 and stays with `Other Product` in variant 2.
  - pick the empty keystone plist → it is in `~/.Trash`; `launchctl.log` has no `bootout` for it.
  - `launchctl.log` contains `bootout gui/` for CometUpdater only when the stub `launchctl print` succeeds (`FAKE_LOADED=ai.perplexity.CometUpdater.wake`), none otherwise.
  - output contains `What:`, `Why:` and the heading `Leftovers of deleted apps`; no path under `Application Support` is printed in the list.
  - re-check: create `$H/Apps/Comet.app` (`ai.perplexity.comet`) between list and answer (inside the `script` pipeline before sending the number) → nothing moved, message `still in use, skipped`.
  - Trash collision: pre-create `~/.Trash/CometUpdater` → the moved folder is `~/.Trash/CometUpdater 2`, the old one intact.
  - `clean --level aggressive --only clean.orphan_agents` (non-interactive) moves nothing.
  Extend the `launchctl` stub: `print` exits 0 only if its last arg ends with a label in `FAKE_LOADED`.

- [ ] **Step 2: Run, see them fail**

Run: `tests/run.sh 2>&1 | grep -i 'leftovers\|orphan'` — Expected: FAIL.

- [ ] **Step 3: Implement**

Register one candidate per non-system `empty|missing|gone` item, `CL_MANUAL=1`, level 3, kind `cmd`, key `orph:<n>`, size = `kb O_DIR`, label `"<name> · <kind text>"`. Kind text: `'update program'` when label or path contains `update` or `keystone` (case-insensitive), else `'background program'`; `empty` → `'empty startup file'`. Info lines (copy, translatable):
  - `What: a background program that %s.` with `'checked for %s updates every hour'` when `StartInterval`=3600 and kind is update, else `'started with your Mac'`.
  - `Why: %s is no longer installed.` / `Why: its program was deleted.` / `Why: the file is empty and does nothing.`
  - `Safe: yes, it goes to the Trash.`
  `list_cands` prints the heading `Leftovers of deleted apps — found %s, total %s` once, before the first `clean.orphan_*` candidate, then info lines indented 6 spaces under each entry; same in the Markdown report. `run_key orph:<n>`: `orph_still` → `launchctl print gui/$(id -u)/<Label>` then `bootout` if found (label must match `^[A-Za-z0-9._-]+$`, never for `empty`) → `to_trash` plist → `to_trash` `O_DIR` → parent if empty. Set `KEY_FREED` to the moved size.

- [ ] **Step 4: Translations, build, run all tests**

Expected: new tests PASS, existing PASS.

- [ ] **Step 5: Commit**

```bash
git add src/ macup macup.sha256 tests/run.sh
git commit -m "clean.orphan_agents: picked leftovers of deleted apps go to the Trash"
```

---

### Task 3: `clean.orphan_data`

**Files:**
- Modify: `src/leftovers.sh`, `src/i18n/translations.json`
- Test: `tests/run.sh`

**Interfaces:**
- Consumes: `O_VENDOR[]`, `vendor_installed`, `APPS`, `to_trash`, `O_ALLOW`, `cand` info param.
- Produces: `data_scan` → arrays `D_N D_VENDOR[] D_NAME[] D_PATHS[]` (newline list) `D_SHARED[]` (1 if containers included); key `odata:<n>`.

- [ ] **Step 1: Write the failing tests**

Fixture additions: `Preferences/ai.perplexity.comet.plist`, `HTTPStorages/ai.perplexity.CometUpdater/x`, `Application Support/Comet/Default/History`, `~/Library/Perplexity/x`, `Containers/ai.perplexity.mac.Notif/x`, `Group Containers/group.ai.perplexity.app/x`, `Preferences/com.segment.analytics.plist`, `Application Support/Downloader/x` with `$H/Apps/Downloader.app` (`local.vitalii.downloader`), `Preferences/ai.perplexity.downloader.plist`.
  - Interactive pick of the Perplexity data entry + `y` → all `ai.perplexity` paths above plus `Application Support/Comet` and `~/Library/Perplexity` in `~/.Trash`; `Application Support/Downloader` and `com.segment` stay.
  - Entry shows `⚠` and `saved passwords`.
  - Non-TTY `check`: the Markdown report lists the Perplexity data paths but none under `Containers` or `Group Containers`.
  - No orphaned agent for a vendor → no data entry for it (fixture `Preferences/com.other.app.plist` without an agent).

- [ ] **Step 2: Run, see them fail**

- [ ] **Step 3: Implement**

Vendors = unique `O_VENDOR` of non-broken orphans. Paths (spec "Cleaner clean.orphan_data" + "Containers"): `~/Library/{Preferences,Caches,HTTPStorages,Saved Application State,WebKit,Logs}/<vendor>.*`; `Application Support/<last>` for ids seen there with ≥3 components; `~/Library/<second>` and `Application Support/<second>`; interactive only: `Containers/<vendor>.*`, `Group Containers/group.<vendor>.*`, `Group Containers/<TEAM>.*`. Name match case-insensitive; skip deny list `app mac helper agent code updater update service daemon data cache support` and names equal to any installed app's last id component or `.app` name. Info lines: `What: settings, history, saved passwords and cookies of %s.`, `Why: %s is no longer installed.`, `Note: move your passwords to another browser first if you need them.` (only when a `Login Data`, `History` or `Cookies` file exists inside), `Note: macOS may ask once for access.` (when containers included). Label prefix `⚠ `.

- [ ] **Step 4: Translations, build, run all tests** — Expected: PASS.

- [ ] **Step 5: Commit** — `git commit -m "clean.orphan_data: data of deleted apps as a separate pick"`

---

### Task 4: System leftovers with one sudo prompt

**Files:**
- Modify: `src/leftovers.sh`, `src/summary.sh:2-12`, `src/report.sh` (STARTUP commands), `src/i18n/translations.json`
- Test: `tests/run.sh`

**Interfaces:**
- Consumes: `O_SYS[]`, `to_trash <path> sudo`, `C_INFO`.
- Produces: array `C_SUDO[]` (1 for system candidates); `sudo_cmds <n>` prints the exact commands for item n.

- [ ] **Step 1: Write the failing tests**

Stub `sudo` records argv to `$HOME/sudo.log`; `-v`/`-k`/`-n true` succeed unless `FAKE_SUDO_FAIL=1`; otherwise runs the rest. Fixture: `$H/SysLib/LaunchDaemons/com.gone.daemon.plist` → missing program; `$H/SysLib/PrivilegedHelperTools/com.gone.daemon` exists; `$H/SysLib/LaunchDaemons/com.prefix.only.plist` → existing program under `$H/SysLib/Application Support/Prefix/`, unsigned, vendor not installed.
  - Interactive pick of `com.gone.daemon` + `y` → `sudo.log` has exactly one `-v`, then the moves, then `-k`; plist and helper in `~/.Trash`.
  - `com.prefix.only` is not offered (prefix alone does not qualify for system items) but reported.
  - Pick a 🔑 item and a user item with `FAKE_SUDO_FAIL=1` → user item moved, system item stays, message `password not accepted, system items skipped`.
  - Non-interactive `check`: `sudo.log` absent; report shows `sudo launchctl bootout system/com.gone.daemon` and `sudo mv`.

- [ ] **Step 2: Run, see them fail**

- [ ] **Step 3: Implement**

System candidates only when interactive and `O_REASON` is `missing` or (`gone` with a readable Team ID not installed). Info lines: `What: a service that starts for every user of this Mac.`, `Why: …` as in Task 2, `Needs your Mac password (asked once for all such items).`; label suffix ` 🔑`. In `summary.sh` after the existing confirm: if any chosen `C_SUDO=1`, print `sudo_cmds` for each, `sudo -v -p "  $(_ 'Mac password to remove system leftovers:') "` once (pattern from `updates.sh:143-145`); on failure drop those indexes and `warn 'Password not accepted, system items skipped'`; after the loop `sudo -k`. Commands: `launchctl bootout gui/<uid>/<label>` for `LaunchAgents`, `system/<label>` for `LaunchDaemons`, only when `launchctl print` finds it; then moves. `report.sh` prints the same `sudo …` lines for `O_SYS=1` items.

- [ ] **Step 4: Translations, build, run all tests** — Expected: PASS.

- [ ] **Step 5: Commit** — `git commit -m "Leftovers: system services and helpers with one password prompt"`

---

### Task 5: Stale Background Task Management records (read-only)

**Files:**
- Modify: `src/leftovers.sh`, `src/report.sh`, `src/i18n/translations.json`
- Test: `tests/run.sh`

**Interfaces:**
- Produces: `btm_stale` → prints names of records whose path no longer exists, one per line.

- [ ] **Step 1: Write the failing tests**

Stub `sfltool dumpbtm` prints `$FAKE_BTM` file. Fixture text with a `Records for UID -2` section (an entry with a missing path that must be ignored) and a `Records for UID <id -u>` section holding: `Name: Ghost` / `URL: /Users/<uid>/Applications/Ghost.app` (missing), `Name: Steam` / `URL: /Users/<uid>/Apps/Steam.app` (exists in fake home), `Name: X` / `URL: (null)`, `Name: Y` / `URL: Contents/Library/LoginItems/Y.app`.
  - Report has `Ghost` under `Login items that point to deleted apps` with `System Settings → General → Login Items`; no `Steam`, `X`, `Y`, nothing from UID -2.
  - `FAKE_BTM` empty file or `sfltool` missing → no BTM line, no `line N:` errors.

- [ ] **Step 2: Run, see them fail**

- [ ] **Step 3: Implement** — parse only the section for `$(id -u)`; map `/Users/<uid>/` to `$HOME/`; skip `(null)` and non-absolute. Called from `check.startup`.

- [ ] **Step 4: Translations, build, run all tests** — Expected: PASS.

- [ ] **Step 5: Commit** — `git commit -m "check.startup: login items that point to deleted apps"`

---

### Task 6: Documentation

**Files:**
- Modify: `README.md` (Features, "What each level cleans" → "Only when you pick them", Safety), `CHANGELOG.md` (new `## Unreleased` section), `src/help.sh` if it lists opt-in picks.

- [ ] **Step 1: Update README Safety lines** (spec "Safety rules"): exceptions for the two picks in "Only listed cache folders" and "browser profiles … never touched"; "Fixes are printed, never run" gains `launchctl bootout` of picked agents; "No sudo, with one exception" becomes two (App Store updates, picked system leftovers); everything goes to the Trash.
- [ ] **Step 2: CHANGELOG `## Unreleased`** with the user-visible change and the Perplexity example in one line.
- [ ] **Step 3: `./build.sh && tests/run.sh`** — Expected: all PASS.
- [ ] **Step 4: Commit** — `git commit -m "Docs: leftovers of deleted apps"`

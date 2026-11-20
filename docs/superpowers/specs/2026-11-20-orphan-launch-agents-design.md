# Orphaned launch agents and app leftovers: detect and remove

Size: small change, two new cleaners and a sharper `check.startup`. Reviewed once by an independent model; its
findings are folded in.

## Why

Uninstalling an app by dragging it to the Trash leaves its updater behind. On the author's Mac, Perplexity and
Comet were deleted, yet `ai.perplexity.CometUpdater.wake` stayed registered to start every hour, two empty
`ai.perplexity.keystone.*` plists sat in `~/Library/LaunchAgents`, the updater kept 332 MB in
`~/Library/Application Support/Perplexity`, and Comet's profile kept 413 MB in `Application Support/Comet`.
`check.startup` reported none of it: it calls an item orphaned only when its program is gone, and updaters live in
Application Support, not inside the `.app`. Items without `Program` (empty plists) were skipped.

## Goals

- `macup check` names launch items whose owning app is no longer installed, plus empty plists.
- macup removes them itself when the user picks them, with the updater's own folder.
- It also offers the deleted app's data (prefs, profile) as a separate pick.
- Works for any vendor, not a hand-kept list.

## Non-goals

- Deleting Background Task Management records: only `sfltool resetbtm` can, needs sudo, resets every choice.
  BTM keeps a developer record ("Perplexity AI Inc.") after the agent is gone; it is harmless and only shown.
- Sudo or privacy prompts in unattended runs (schedule, `--quiet`, `--json`, no TTY): there, system items are only
  reported with commands, and `Containers` / `Group Containers` are not touched.

## Anti-goals

- Removing anything of an installed app. Real cases on the author's Mac that must stay: Steam
  (`com.valvesoftware.steamclean`, program in Application Support), iStatistica (label `com.imagetasks.*`, app id
  `imagetasks.iStatistica`), `Application Support/Google` holding Chrome profiles beside `GoogleUpdater`,
  `Application Support/Downloader` owned by `local.vitalii.downloader`.
- Flagging Homebrew services or user-made agents.
- Deleting irreversibly: everything goes to the Trash.

## Approaches

- **A. Owner by signing team, then vendor prefix (picked).**
- B. Hand-kept list of known updaters. No false positives, but blind to new vendors.

## Design

### Installed apps

`CFBundleIdentifier` (compared case-insensitively) and Team ID of every `.app` in `/Applications`,
`/Applications/*/`, `/Applications/*/*/`, `~/Applications`, `~/Applications/*/`. Read from `Info.plist` on disk,
never Spotlight (`mdfind` still returned the deleted `Comet.app`). Team ID from `codesign -dv`, computed only when
there is at least one suspect item.

### Orphaned launch item

Scan `~/Library/LaunchAgents`, `/Library/LaunchAgents`, `/Library/LaunchDaemons`; skip `com.apple.*` and macup's own
label. For each plist, owner ids = all `AssociatedBundleIdentifiers` plus `Label` (not the filename). Vendor of an id
= its first two components; ids with fewer than two components never make anything an orphan.

An item is orphaned when one of:

1. **Empty plist:** it parses and has no `Label` and no program. Skipped if the file has the `uchg` flag (some tools
   lock an empty plist on purpose to block an updater). A plist that fails to parse is reported, not removed.
2. **Program missing:** absolute program path that does not exist.
3. **Owner gone:** program inside a `.app`, under `~/Library/Application Support/`, `/Library/Application Support/`,
   or `~/Library/<Name>/` where `<Name>` equals a component of the label (case-insensitive), and:
   - no installed app shares the program's Team ID (unsigned or unreadable program: this check cannot clear it), and
   - no installed app's id starts with any owner vendor.
   Programs elsewhere (`/opt/homebrew`, `/usr/local`, `~/.local`, scripts) are never orphaned by this rule.

### Report (`check.startup`)

Orphans with reason (`app not installed`, `program missing`, `empty plist`) and, for system-wide ones, the commands:
`sudo launchctl bootout gui/<uid>/<label>` for `/Library/LaunchAgents`, `system/<label>` for daemons, then
`sudo rm <plist>`. Privileged helpers in `/Library/PrivilegedHelperTools` whose daemon is orphaned are listed the same
way.

BTM (read-only): `sfltool dumpbtm` runs without sudo. Only the `Records for UID <uid>` section is parsed; paths
`/Users/<uid>/…` are mapped to `$HOME`; `(null)` and relative URLs are skipped. A remaining absolute path that does not
exist is a stale login item, shown with "System Settings → General → Login Items". When nothing parses (format
changed), the BTM part is skipped silently.

### Cleaner `clean.orphan_agents`

Off by default, offered only on pick, level aggressive, asks yes. Only `~/Library/LaunchAgents` items.
New candidate kind (`cmd` key) that, per item:

1. Re-checks at run time that the item is still orphaned and its program is not running (`pgrep -f`).
2. `launchctl bootout gui/<uid>/<Label>` only if `launchctl print` finds the service (not loaded is the normal case);
   never for empty plists. The label must match `^[A-Za-z0-9._-]+$`.
3. Moves the plist to the Trash.
4. Moves the program's own folder to the Trash: the first folder below `Application Support/<Vendor>/` or
   `~/Library/<Name>/` that contains the program (`Perplexity/CometUpdater`, not `Perplexity`). Then the parent goes
   too only if it is left empty. Never follows symlinks; refuses a path containing `..`.

Size shown = that folder's size.

### Cleaner `clean.orphan_data`

Off by default, offered only on pick, level aggressive, asks yes with a warning that it holds the deleted app's
history, saved passwords and cookies. Vendors come only from orphaned launch items of this run (so it never guesses at
SDK ids or test bundles). One candidate per vendor, total size, moved to the Trash:

- `~/Library/{Preferences,Caches,HTTPStorages,Saved Application State,WebKit,Logs}/<vendor>.*`;
- `~/Library/<Name>` and `Application Support/<Name>` where `<Name>` equals the vendor's second component
  case-insensitively (`ai.perplexity` → `~/Library/Perplexity`), with the same generic-name and installed-app guards;
- for each id seen there with three or more components (`ai.perplexity.comet`), `Application Support/<last component>`
  matched case-insensitively, unless that name is generic (`app`, `mac`, `helper`, `agent`, `code`, `updater`, …),
  equals the last id component or name of any installed app, or the folder holds an installed vendor's files.

Re-checked at run time like the agents cleaner.

### System items (sudo)

`/Library/LaunchAgents`, `/Library/LaunchDaemons` and their helpers in `/Library/PrivilegedHelperTools` are orphan
candidates too, marked 🔑, with stricter evidence: only "program missing" or "no installed app shares the program's
Team ID" (prefix alone never qualifies). Detection needs no sudo. Interactive only. When the user's pick contains 🔑
items, macup prints the exact commands, asks for the Mac password once (`sudo -v`), runs
`sudo launchctl bootout gui/<uid>/<label>` (LaunchAgents) or `system/<label>` (daemons) when loaded, moves plist and
helper to the user's Trash, then `sudo -k`. Unattended runs only print the commands.

### Containers

`~/Library/Containers/<vendor>.*`, `Group Containers/group.<vendor>.*` and `Group Containers/<TEAMID>.*` (Team ID of
the orphaned program) join `clean.orphan_data` in interactive runs only; macOS may ask once for access. A refused path
is reported and skipped.

### Terminal UX

A section "Leftovers of deleted apps — found N, total X" after the usual cache list in `macup check`, numbered in the
same pick flow (`1,3`, `1-4`, `all`, Enter to skip). Each entry, written for a non-developer:

```
 1  Perplexity · Comet update program                       332 MB
    What:  a background program that checked for Comet updates every hour.
    Why:   Comet is no longer installed, there is nothing to update.
    Safe:  yes, files go to the Trash.
```

- Vendor name from the signing certificate ("Developer ID Application: Perplexity AI Inc. (…)" → "Perplexity"),
  else the BTM developer name, else the vendor prefix.
- "What" text by kind: update program (label or path contains `update`/`keystone`), background service, system
  service 🔑, app data ⚠ (history, saved passwords, cookies: "move your passwords first if you need them"), shared
  data (containers: "macOS may ask for access once").
- Paths stay out of the screen; the Markdown report lists them.
- After the pick: one password prompt if needed, everything moved to the Trash, a summary of freed space.

### Safety rules

`safe_path` gets an exact-match list filled at detection; it is checked after the existing `..` and symlink
refusals, and only these two cleaners can add to it. The README Safety section is updated: "Only listed cache
folders" and "browser profiles are never touched" get an exception for these two opt-in picks, and "fixes are printed,
never run" gets one for `launchctl bootout` of picked agents; "No sudo, with one exception" becomes two exceptions
(App Store updates, picked system leftovers).

Translations: new strings in en/uk/ru (`src/i18n/translations.json`).

Tests (fixture home): orphaned updater with its folder; empty plist; empty plist with `uchg`; live Steam-like agent
with its app; agent whose label prefix differs from its app id but shares the Team ID; Homebrew service; agent running
a script in `~/Library/pnpm`; vendor folder holding a second product's profile. Only the first two and their own
folders are flagged and moved; the shared parent stays.

## Left to the builder

- Exact wording of the new strings and the generic-name deny list.
- Faking Team IDs in tests (stub `codesign`).

# shellcheck shell=bash
# shellcheck disable=SC2154,SC2088  # SC2154: work, quick_skip, build_path and the helpers come from tests/run.sh; SC2088: a literal ~ as users type it
# Sourced by tests/run.sh: system checks, schedule, --notify, config file, installer, task ids.
# --- system checks read the output of macOS tools: fakes with real samples, so a format change shows up here
SB="$work/sbin"; mkdir -p "$SB"; home="$work/sys"; mkdir -p "$home/.config/macup"; printf 'language = en\n' >"$home/.config/macup/config"
sys(){ env HOME="$home" PATH="$SB:$PATH" macup_run check --no-color "$@" </dev/null 2>&1; }
cat >"$SB/softwareupdate" <<'FAKE'
#!/bin/bash
[ -n "$SU_FAIL" ] && { printf 'Software Update Tool\n\nFinding available software\nSoftware Update Tool: could not reach the server\n' >&2; exit 1; }
[ -n "$NO_UPDATES" ] && { printf 'Software Update Tool\n\nFinding available software\nNo new software available.\n'; exit 0; }
printf 'Software Update Tool\n\nFinding available software\nSoftware Update found the following new or updated software:\n'
printf '* Label: Command Line Tools for Xcode-16.0\n\tTitle: Command Line Tools for Xcode, Version: 16.0, Size: 746159KiB, Recommended: YES, \n'
printf '* Label: macOS Sequoia 15.1-24B83\n\tTitle: macOS Sequoia 15.1, Version: 15.1, Size: 6283533KiB, Recommended: YES, Action: restart, \n'
FAKE
cat >"$SB/pmset" <<'FAKE'
#!/bin/bash
[ "$*" = "-g batt" ] && printf "Now drawing from 'Battery Power'\n -InternalBattery-0 (id=4653155)\t83%%; discharging; 4:10 remaining present: true\n"
exit 0
FAKE
cat >"$SB/system_profiler" <<'FAKE'
#!/bin/bash
printf 'Power:\n\n    Battery Information:\n\n      Health Information:\n          Cycle Count: 612\n          Condition: Normal\n          Maximum Capacity: 76%%\n'
FAKE
cat >"$SB/memory_pressure" <<'FAKE'
#!/bin/bash
printf 'The system has 17179869184 (1048576 pages with a page size of 16384).\n\nSystem-wide memory free percentage: 9%%\n'
FAKE
chmod +x "$SB"/*
out=$(sys --only check.macos_updates)
echo "$out" | grep -q 'macOS: updates available' && echo "$out" | grep -q '^ *Command Line Tools for Xcode 16.0$' && echo "$out" | grep -q '^ *macOS Sequoia 15.1$' \
  && NO_UPDATES=1 sys --only check.macos_updates | grep -q 'macOS: up to date' && pass "macOS updates: titles read from softwareupdate -l" || { fail "softwareupdate parsing"; echo "$out"; }
SU_FAIL=1 sys --only check.macos_updates >"$work/sufail.out"
grep -q 'could not check' "$work/sufail.out" && ! grep -q 'up to date' "$work/sufail.out" && pass "macOS updates: a failed softwareupdate is not reported as up to date" || { fail "softwareupdate failure"; cat "$work/sufail.out"; }
BB="$work/brewbin"; mkdir -p "$BB"
cat >"$BB/brew" <<'FAKE'
#!/bin/bash
echo "brew $* NO_AUTO_UPDATE=${HOMEBREW_NO_AUTO_UPDATE:-}" >>"$BREWLOG"
[ "$1" = --repository ] && echo "$BREWREPO"
[ "$1" = --cache ] && echo "$BREWREPO/cache"
exit 0
FAKE
chmod +x "$BB/brew"; mkdir -p "$work/brewrepo/.git"; : >"$work/brewrepo/.git/FETCH_HEAD"; touch -t 202001010000 "$work/brewrepo/.git/FETCH_HEAD"
fake_first "$BB" brew MACUP_PATH=keep HOME="$home" PATH="$BB:$SB:$PATH" || return 1
env MACUP_PATH=keep HOME="$home" PATH="$BB:$SB:$PATH" BREWLOG="$work/brew.log" BREWREPO="$work/brewrepo" macup_run check --only update.brew --no-color </dev/null >"$work/brewchk.out" 2>&1
grep -q 'brew outdated' "$work/brew.log" && ! grep -q '^brew update' "$work/brew.log" && ! grep 'brew outdated' "$work/brew.log" | grep -qv 'NO_AUTO_UPDATE=1$' \
  && grep -q 'package list is from 2020-01-01' "$work/brewchk.out" && pass "check never runs brew update, calls brew with HOMEBREW_NO_AUTO_UPDATE=1 and says how old the list is" || { fail "check leaves Homebrew alone"; cat "$work/brew.log" "$work/brewchk.out"; }
sys --only check.battery | grep -q 'Battery: 83% charged, 612 cycles, 76% capacity, Normal — capacity under 80%' && pass "battery: cycles and capacity read from system_profiler" || { fail "battery parsing"; sys --only check.battery; }
sys --only check.memory | grep -q '! Memory: .* 9% free, .* memory is tight' && pass "memory: free percentage read from memory_pressure" || { fail "memory parsing"; sys --only check.memory; }

# --- the schedule is optional: nothing until asked, a LaunchAgent that only runs a check, off removes it
home="$work/sch"; mkdir -p "$home/.local/bin" "$home/.config/macup"; printf 'language = en\n' >"$home/.config/macup/config"; cp "$build_path" "$home/.local/bin/macup"
SP="$home/Library/LaunchAgents/com.vitaliideveloper.macup.plist"; sch(){ env HOME="$home" MACUP_AT="$home/.local/bin/macup" macup_run schedule "$@" --no-color </dev/null 2>&1; }
sch | grep -q 'No schedule' && [ ! -e "$SP" ] && pass "schedule: none by default" || fail "schedule: default"
sch weekly | grep -q 'every Monday at 10:00' && grep -q '<key>Weekday</key><integer>1</integer>' "$SP" && grep -qF "<array><string>$home/.local/bin/macup</string><string>check</string><string>--quiet</string><string>--notify</string>" "$SP" \
  && grep -q "^bootstrap gui/.* $SP" "$home/launchctl.log" && grep -q "<key>PATH</key><string>.*$work/bin" "$SP" && sch | grep -q 'every Monday' && pass "schedule weekly: a LaunchAgent that runs macup check" || { fail "schedule weekly"; cat "$SP" "$home/launchctl.log"; }
{ ! command -v plutil >/dev/null || plutil -lint "$SP" >/dev/null; } && pass "schedule: the plist is valid" || fail "schedule: plist"
sch daily | grep -q 'every day at 10:00' && ! grep -q Weekday "$SP" && pass "schedule daily" || fail "schedule daily"
sch off | grep -q 'Schedule removed' && [ ! -e "$SP" ] && grep -q "^bootout gui/.*/com.vitaliideveloper.macup" "$home/launchctl.log" && pass "schedule off removes it" || fail "schedule off"
sch hourly >/dev/null; [ $? = 2 ] && [ ! -e "$SP" ] && pass "schedule: unknown word" || fail "schedule: unknown word"
# --notify: a notification only when something needs a look
env HOME="$home" macup_run check --only check.sizes --quiet --notify </dev/null >/dev/null 2>&1
[ ! -e "$home/osascript.log" ] && pass "--notify: silent when all is well" || { fail "--notify without a reason"; cat "$home/osascript.log"; }
mkdir -p "$home/Library/Developer/Xcode"; ln -s "$home/gone" "$home/.local/bin/deadlink"
env HOME="$home" macup_run check --only check.commands --quiet --notify </dev/null >/dev/null 2>&1
grep -q 'display notification "Needs attention: [0-9]' "$home/osascript.log" 2>/dev/null && pass "--notify: says what needs attention" || { fail "--notify"; cat "$home/osascript.log" 2>/dev/null; }

# --- self-update: tests/shipping.sh, against a fake release

# --- creating the config file runs nothing: its template used to run `macup clean` and `macup all` (backticks in a heredoc)
home="$work/cf"; mkdir -p "$home" "$work/mbin"; printf '#!/bin/bash\necho "$*" >>"$HOME/ran.log"\n' >"$work/mbin/macup"; chmod +x "$work/mbin/macup"
env HOME="$home" PATH="$work/mbin:$PATH" macup_run config </dev/null >/dev/null 2>&1
[ ! -e "$home/ran.log" ] && grep -qF '# What `macup clean` / `macup all` may remove' "$home/.config/macup/config" && [ "$(wc -l <"$home/.config/macup/config")" -lt 45 ] \
  && pass "creating the config file runs no command" || { fail "creating the config ran: $(cat "$home/ran.log" 2>/dev/null | tr '\n' ' ')"; }
rm -rf "$home"; env HOME="$home" PATH="$work/mbin:$PATH" macup_run lang uk </dev/null >/dev/null 2>&1
[ ! -e "$home/ran.log" ] && grep -q '^language = uk' "$home/.config/macup/config" && pass "macup lang on a fresh home runs no command" || fail "macup lang ran: $(cat "$home/ran.log" 2>/dev/null | tr '\n' ' ')"
rm -rf "$home"; mkdir -p "$home"; : >"$home/.config"   # a file where the config's folder goes
env HOME="$home" MACUP_LANG=en macup_run lang ru </dev/null >"$work/lang.out" 2>&1; rc=$?
[ $rc = 1 ] && grep -qx "Couldn't write ~/.config/macup/config" "$work/lang.out" && pass "macup lang says when it cannot write the config" || { fail "macup lang on an unwritable config (rc=$rc)"; cat "$work/lang.out"; }

# --- installer, from this checkout: it installs the binary built here
install_home="$work/i"; mkdir -p "$install_home/.npm-global/bin"; printf '#!/bin/bash\n# macup — old\nMACUP_VERSION="1.1"\n' >"$install_home/.npm-global/bin/macup"; printf '#!/bin/bash\n# macup notes\n' >"$install_home/.npm-global/bin/other"
# no test may hang the suite: after the limit it says what was running and stops the command
lim(){ local secs=$1 pid watcher rc; shift; "$@" & pid=$!
  ( sleep "$secs"; echo "TIMEOUT after ${secs}s: $*"; ps -axo pid,ppid,etime,command | grep -v 'ps -axo' | tail -25; kill $pid 2>/dev/null ) & watcher=$!
  wait $pid; rc=$?; kill $watcher 2>/dev/null; wait $watcher 2>/dev/null; return $rc; }
# install.sh takes the binary built last of .build/release and .build/debug
built=.build/release/macup; [ .build/debug/macup -nt "$built" ] && built=.build/debug/macup
lim 120 env HOME="$install_home" MACUP_PREFIX="$work/bin" /bin/bash ./install.sh --yes --lang uk --projects "~/Code, ~/Work" </dev/null >"$work/in" 2>&1; rc=$?
[ $rc = 0 ] && [ ! -e "$install_home/.npm-global/bin/macup" ] && [ -e "$install_home/.npm-global/bin/other" ] && cmp -s "$work/bin/macup" "$built" && grep -q '^project_dirs = ~/Code, ~/Work' "$install_home/.config/macup/config" \
  && pass "install replaces an old copy, keeps unrelated files" || { fail "install (rc=$rc)"; cat "$work/in"; }
lim 120 env HOME="$install_home" MACUP_PREFIX="$work/bin" /bin/bash ./install.sh --yes </dev/null >/dev/null 2>&1
grep -q '^project_dirs = ~/Code, ~/Work' "$install_home/.config/macup/config" && grep -q '^language = uk' "$install_home/.config/macup/config" && [ "$(grep -c '# macup' "$install_home/.zshrc")" = 1 ] \
  && pass "reinstall keeps settings" || fail "reinstall"
/bin/bash ./install.sh --bogus >/dev/null 2>&1; [ $? = 2 ] && pass "installer rejects unknown options" || fail "installer options"

# --- a mistyped task id is said, not silently matched to nothing; no HOME, no run
home="$work/ids"; mkdir -p "$home/.config/macup"; printf 'language = en\nskip = check.tyme_machine\nenable = clean.trash\n' >"$home/.config/macup/config"
env HOME="$home" macup_run check --only chek.disk --no-color </dev/null >"$work/ids.out" 2>&1; rc=$?
[ $rc = 2 ] && grep -q 'Unknown task: chek.disk' "$work/ids.out" && [ ! -d "$home/Library/Logs/macup" ] && pass "unknown id in --only stops the run" || fail "unknown id in --only (rc=$rc)"
env HOME="$home" macup_run check --skip 'update.*,check.docker,clean.nope' --no-color </dev/null >/dev/null 2>&1; [ $? = 2 ] && pass "unknown id in --skip stops the run" || fail "unknown id in --skip"
env HOME="$home" macup_run check --only 'check.system,clean.*' --no-color </dev/null >"$work/ids.out" 2>&1; rc=$?
[ $rc = 0 ] && grep -q 'Unknown task in ~/.config/macup/config: check.tyme_machine' "$work/ids.out" && ! grep -q 'clean.trash (' "$work/ids.out" && pass "unknown id in the config is a warning" || { fail "unknown id in the config (rc=$rc)"; cat "$work/ids.out"; }
env HOME= macup_run version >/dev/null 2>&1; [ $? = 1 ] && pass "no HOME: macup does not start" || fail "empty HOME"


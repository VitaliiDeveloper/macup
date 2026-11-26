# shellcheck shell=bash
# shellcheck disable=SC2154  # SC2154: work, quick_skip, build_path and the helpers come from tests/run.sh
# Sourced by tests/run.sh: tidying, reports, Ctrl-C, swap, --json and --pick, --enable.
# ============================ 2.9

# --- macup tidies its own files on every run, a check too: old reports, too many reports, history, the schedule's log, temp files of killed runs
home="$work/tidy"; LG="$home/Library/Logs/macup"; ST="$home/Library/Application Support/macup"; TT="$work/tidytmp"; mkdir -p "$LG" "$ST" "$TT" "$home/.config/macup"; printf 'language = en\n' >"$home/.config/macup/config"
for index in $(seq 10 79); do : >"$LG/macup_2026-01-01_00-00-$index.md"; echo x >"$LG/macup_2026-01-01_00-00-$index.log"; done
: >"$LG/macup_2024-01-01_00-00-00.md"; : >"$LG/macup_2024-01-01_00-00-00.log"; : >"$LG/macup_2024-06-01_00-00-00.log"; touch -t 202401010000 "$LG"/macup_2024-*
seq 1 1500 | sed 's/^/2026-01-01 00:00,check,1,2,3,4,5,6,7,8,/' >"$ST/history.csv"; seq 1 900 >"$LG/schedule.log"
: >"$TT/macup.AbCdEf"; : >"$TT/macup.AbCdEf.pid"; : >"$TT/macup-lang.GhIjKl"; touch -t 202401010000 "$TT"/macup*; : >"$TT/macup.FrEsH1"; : >"$TT/macup-notes.txt"; touch -t 202401010000 "$TT/macup-notes.txt"
env HOME="$home" TMPDIR="$TT" macup_run check --only check.system --no-color </dev/null >"$work/tidy.out" 2>&1
count=$(ls "$LG"/macup_*.md | wc -l | tr -d ' ')
[ "$count" = 20 ] && [ ! -e "$LG/macup_2024-01-01_00-00-00.md" ] && [ ! -e "$LG/macup_2024-01-01_00-00-00.log" ] && [ ! -e "$LG/macup_2024-06-01_00-00-00.log" ] && [ -e "$LG/macup_2026-01-01_00-00-79.md" ] \
  && pass "own reports: old ones and old orphan logs go, the newest 20 runs stay ($count)" || fail "own reports ($count left)"
lo=0; for log_file in "$LG"/macup_*.log; do [ -e "${log_file%.log}.md" ] || lo=1; done
[ $lo = 0 ] && [ "$(ls "$LG"/macup_*.log | wc -l | tr -d ' ')" = 19 ] && pass "own reports: a removed report takes the log of an older version along" || { fail "logs of removed reports stay"; ls "$LG"; }
[ "$(wc -l <"$ST/history.csv" | tr -d ' ')" -le 501 ] && [ "$(wc -l <"$LG/schedule.log" | tr -d ' ')" = 200 ] && tail -1 "$LG/schedule.log" | grep -q '^900$' && pass "history and the schedule's log keep only their last lines" || fail "history or schedule.log not trimmed"
[ ! -e "$TT/macup.AbCdEf" ] && [ ! -e "$TT/macup.AbCdEf.pid" ] && [ ! -e "$TT/macup-lang.GhIjKl" ] && [ -e "$TT/macup.FrEsH1" ] && [ -e "$TT/macup-notes.txt" ] \
  && [ -z "$(find "$TT" -maxdepth 1 -name 'macup*' ! -name '*FrEsH1' ! -name '*notes*')" ] && pass "temp files of killed runs go after a day; nothing else in the temp folder is touched, none are left" || { fail "temp files"; ls -la "$TT"; }
new=$(ls -t "$LG"/macup_*.md | head -1); [ ! -e "${new%.md}.log" ] && ! grep -q '^## Command output' "$new" && pass "a run that started no command: one report, no command output section" || fail "a run without commands left a log or an empty section"
printf 'language = en\nkeep_reports_days = 30\nkeep_reports = 5\n' >"$home/.config/macup/config"
env HOME="$home" TMPDIR="$TT" macup_run check --only check.system --no-color </dev/null >"$work/tidy.out" 2>&1
[ "$(ls "$LG"/macup_*.md | wc -l | tr -d ' ')" = 5 ] && [ -e "$new" ] && pass "keep_reports caps the runs kept" || { fail "keep_reports"; ls "$LG"; }

# --- macup reports: what there is, clean asks first, --json
home="$work/rep"; LG="$home/Library/Logs/macup"; mkdir -p "$LG" "$home/.config/macup"; printf 'language = en\n' >"$home/.config/macup/config"
printf '# macup report — 2026-11-01 10:00\n\nMode: check · macup 2.8.0 · took 0m 5s\n' >"$LG/macup_2026-11-01_10-00-00.md"; echo raw >"$LG/macup_2026-11-01_10-00-00.log"
printf '# звіт macup — 2026-11-02 11:30\n\nРежим: all+deep · macup 2.9.0 · тривалість 1m 2s\n' >"$LG/macup_2026-11-02_11-30-00.md"; echo keep >"$LG/schedule.log"
env HOME="$home" macup_run reports --no-color </dev/null >"$work/rep.out" 2>&1
grep -q '^Reports: 2 · .* · ~/Library/Logs/macup$' "$work/rep.out" && grep -q '^Oldest: 2026-11-01 10:00 · newest: 2026-11-02 11:30$' "$work/rep.out" && grep -q 'macup reports clean' "$work/rep.out" \
  && pass "reports: count, size, folder, dates, how to clean" || { fail "reports"; cat "$work/rep.out"; }
env HOME="$home" macup_run reports --json </dev/null >"$work/rep.json" 2>/dev/null
python3 -I -c 'import json,sys; data=json.load(open(sys.argv[1])); reports=data["reports"]; assert data["schema"]==1 and data["count"]==2 and data["kb"]>0 and data["folder"].endswith("Logs/macup"); assert [entry["mode"] for entry in reports]==["check","all+deep"] and reports[0]["date"]=="2026-11-01 10:00" and reports[0]["file"].endswith(".md") and reports[0]["kb"]>0' "$work/rep.json" \
  && pass "reports --json: valid, with file, date, mode and size" || { fail "reports --json"; cat "$work/rep.json"; }
env HOME="$home" macup_run reports clean --no-color </dev/null >"$work/rep.out" 2>&1
[ "$(ls "$LG" | wc -l | tr -d ' ')" = 4 ] && grep -q 'Reports to remove: 2 ' "$work/rep.out" && grep -q 'Nothing removed' "$work/rep.out" && ! grep -q tty "$work/rep.out" \
  && pass "reports clean without a yes removes nothing" || { fail "reports clean: no answer"; cat "$work/rep.out"; }
env HOME="$home" macup_run reports clean --yes --no-color </dev/null >"$work/rep.out" 2>&1
[ "$(ls "$LG")" = schedule.log ] && grep -q 'Removed' "$work/rep.out" && pass "reports clean --yes removes the reports and old logs, keeps schedule.log" || { fail "reports clean --yes"; ls "$LG"; cat "$work/rep.out"; }
env HOME="$home" macup_run reports nonsense </dev/null >/dev/null 2>&1; [ $? = 2 ] && pass "reports: an unknown word is exit status 2" || fail "reports nonsense"

# --- Ctrl-C: what the commands printed so far is in the report, and the report is named
home="$work/int"; mkdir -p "$home/.local/bin" "$home/.config/macup"; printf 'language = en\n' >"$home/.config/macup/config"
printf '#!/bin/bash\ncase "$1" in --version) echo 1.0 ;; update) echo "agy is downloading"; : >"$HOME/started"; sleep 30 ;; esac\n' >"$home/.local/bin/agy"; chmod +x "$home/.local/bin/agy"
set -m   # its own process group, and SIGINT not ignored as it is for a background job without job control
env HOME="$home" macup_run update --only update.agy --no-color </dev/null >"$work/int.out" 2>&1 & pid=$!
set +m
# shellcheck disable=SC2034  # waits, counts nothing
for tries in $(seq 1 100); do [ -e "$home/started" ] && break; sleep 0.2; done
kill -INT -- -"$pid" 2>/dev/null; wait "$pid"; rc=$?
report=$(ls "$home"/Library/Logs/macup/macup_*.md 2>/dev/null | head -1)
[ $rc = 130 ] && [ -n "$report" ] && grep -q 'Interrupted. Report: ~/Library/Logs/macup/macup_' "$work/int.out" && grep -q 'agy is downloading' "$report" && grep -q 'incomplete' "$report" && [ -z "$(ls "$home"/Library/Logs/macup/*.log 2>/dev/null)" ] \
  && pass "Ctrl-C: the report keeps what the commands printed" || { fail "Ctrl-C (rc=$rc)"; cat "$work/int.out" "$report"; }
# the same for a terminal that closes (SIGHUP) or a kill (SIGTERM)
home="$work/term"; mkdir -p "$home/.local/bin" "$home/.config/macup"; printf 'language = en\n' >"$home/.config/macup/config"; cp "$work/int/.local/bin/agy" "$home/.local/bin/agy"
env HOME="$home" macup_run update --only update.agy --no-color </dev/null >"$work/term.out" 2>&1 & pid=$!
# shellcheck disable=SC2034  # waits, counts nothing
for tries in $(seq 1 100); do [ -e "$home/started" ] && break; sleep 0.2; done
kill -TERM "$pid" 2>/dev/null; wait "$pid"; rc=$?
report=$(ls "$home"/Library/Logs/macup/macup_*.md 2>/dev/null | head -1)
[ -n "$report" ] && grep -q 'agy is downloading' "$report" && grep -q 'incomplete' "$report" && pass "SIGTERM: the report keeps what the commands printed" || { fail "SIGTERM (rc=$rc)"; cat "$work/term.out"; }

# the same in a step the Swift build runs itself: Ctrl-C while brew downloads, and a kill that waits for the step to end
home="$work/intb"; mkdir -p "$home/.config/macup"; printf 'language = en\n' >"$home/.config/macup/config"; fakes "$work/intbin" brew sudo df
brew_env=(HOME="$home" MACUP_PATH=keep PATH="$work/intbin:$PATH")   # started straight from here, so the pid is macup's
# shellcheck disable=SC2034  # waits, counts nothing
brew_started(){ local tries; for tries in $(seq 1 100); do grep -q '^brew update' "$home/brew.log" 2>/dev/null && return; sleep 0.2; done; }
set -m; env "${brew_env[@]}" FAKE_BREW_SLEEP=30 macup_run update --only update.brew --no-color </dev/null >"$work/intb.out" 2>&1 & pid=$!; set +m
brew_started; kill -INT -- -"$pid" 2>/dev/null; wait "$pid"; rc=$?
report=$(ls "$home"/Library/Logs/macup/macup_*.md 2>/dev/null | head -1)
[ $rc = 130 ] && [ -n "$report" ] && grep -q 'Interrupted. Report: ~/Library/Logs/macup/macup_' "$work/intb.out" && grep -q 'Updating Homebrew' "$report" && grep -q 'incomplete' "$report" \
  && [ ! -e "$home/Library/Application Support/macup/lock" ] && pass "Ctrl-C during brew update: the report keeps what brew printed, the lock is gone" || { fail "Ctrl-C during brew update (rc=$rc)"; cat "$work/intb.out" "$report"; }
rm -rf "$home/Library/Logs/macup" "$home/brew.log"
env "${brew_env[@]}" FAKE_BREW_SLEEP=3 macup_run update --only update.brew --no-color </dev/null >"$work/intb.out" 2>&1 & pid=$!
brew_started; kill -TERM "$pid" 2>/dev/null; wait "$pid"; rc=$?
report=$(ls "$home"/Library/Logs/macup/macup_*.md 2>/dev/null | head -1)
[ $rc = 130 ] && grep -q 'incomplete' "$report" && [ "$(grep -c . "$home/brew.log")" = 1 ] && pass "SIGTERM: the run stops once the running step ends" || { fail "SIGTERM after a step (rc=$rc)"; cat "$work/intb.out" "$home/brew.log"; }

# --- since the last run: swap that grew is not "something is filling the disk"
home="$work/swp"; SW="$work/swpbin"; mkdir -p "$SW" "$home/.config/macup" "$home/Library/Application Support/macup"; printf 'language = en\n' >"$home/.config/macup/config"
printf '#!/bin/bash\ncase "$*" in *vm.swapusage*) echo "total = 12288.00M  used = ${FAKE_SWAP_MB}.00M  free = 100.00M  (encrypted)" ;; *) exec /usr/sbin/sysctl "$@" ;; esac\n' >"$SW/sysctl"; chmod +x "$SW/sysctl"
swp(){ # free KB more last time, swap MB last time, swap MB now (the disk itself may change meanwhile: the patterns allow a few GB)
  local fr; fr=$(df -k /System/Volumes/Data 2>/dev/null | awk 'NR==2{print $4}')
  echo "2026-11-01 10:00,check,$((fr + $1)),500000000,50,$2,,,0,0,0" >"$home/Library/Application Support/macup/history.csv"
  FAKE_SWAP_MB=$3 env HOME="$home" PATH="$SW:$PATH" macup_run check --only check.trends,check.memory --no-color </dev/null 2>&1 | grep 'Free space' | head -1; }
out=$(swp 26214400 0 10240)   # 26.8 GB less, 10.7 GB of it swap: 16 GB is under the 21 GB that warns
echo "$out" | grep -q '· Free space: -2[4-9]\.[0-9] GB since 2026-11-01 10:00 (10.7 GB of it is swap, freed on restart)$' && pass "free space: swap is subtracted before warning" || fail "free space with swap: $out"
out=$(swp 31457280 0 2048)
echo "$out" | grep -q '! Free space: -3[0-5]\.[0-9] GB .*(2.1 GB of it is swap, freed on restart) — something is filling the disk' && pass "free space: still a warning when the rest crosses the line" || fail "free space, swap too small: $out"
out=$(swp 31457280 7000 7000)
echo "$out" | grep -q '! Free space: -3[0-5]\.[0-9] GB since 2026-11-01 10:00 — something is filling' && pass "free space: unchanged swap, the warning as before" || fail "free space without swap: $out"

# --- --json carries everything the terminal shows, with a key for each thing that can be cleaned; --pick cleans exactly those
home="$work/js"; tests/fixture.sh "$home"; (cd "$home" && find . -type f | sort) >"$home.b"
env HOME="$home" macup_run check --json --skip "$quick_skip" </dev/null >"$work/js.json" 2>/dev/null
jq "$work/js.json" 'cleanable=data["cleanable"]; assert data["schema"]==1 and len(cleanable)>20 and all(key in cleanable[0] for key in ("key","task","level","kb","opt_in","in_clean","text")); assert len({entry["key"] for entry in cleanable})==len(cleanable); trash=[entry for entry in cleanable if entry["task"]=="clean.trash"][0]; assert trash["opt_in"] and not trash["in_clean"] and trash["level"]=="aggressive"; spm=[entry for entry in cleanable if entry["task"]=="clean.spm"][0]; assert spm["in_clean"] and spm["kb"]>5000' \
  && pass "--json: cleanable items with unique keys, level and size" || { fail "--json cleanable"; head -c 600 "$work/js.json"; }
mkdir -p "$home/Library/LaunchAgents"; : >"$home/Library/LaunchAgents/com.example.agent.plist"   # its name is a line under "Third-party background services"
env HOME="$home" macup_run check --json --only check.sizes,check.system,check.startup </dev/null >"$work/js2.json" 2>/dev/null
jq "$work/js2.json" 'items=data["items"]; assert items and all(entry["kind"] in ("ok","info","warn","fail") and entry["section"] and isinstance(entry["details"],list) for entry in items); assert any("Trash" in entry["text"] for entry in items); assert any(entry["details"] for entry in items)' \
  && pass "--json: every line of the run with its section and kind" || { fail "--json items"; head -c 600 "$work/js2.json"; }
k3=$(jq "$work/js.json" 'print([entry["key"] for entry in data["cleanable"] if entry["task"]=="clean.derived_data"][0])')
k1=$(jq "$work/js.json" 'print([entry["key"] for entry in data["cleanable"] if entry["task"]=="clean.spm"][0])'); k2=$(jq "$work/js.json" 'print([entry["key"] for entry in data["cleanable"] if entry["task"]=="clean.trash"][0])')
env HOME="$home" macup_run check --json --skip "$quick_skip" </dev/null 2>/dev/null >"$work/js3.json"; [ "$(jq "$work/js3.json" 'print(sorted(entry["key"] for entry in data["cleanable"]))')" = "$(jq "$work/js.json" 'print(sorted(entry["key"] for entry in data["cleanable"]))')" ] \
  && pass "--json: the keys are the same on the next run" || fail "--json keys change between runs"
env HOME="$home" macup_run clean --pick "$k1,$k2" --json --skip "$quick_skip" </dev/null >"$work/js4.json" 2>/dev/null; rc=$?
got=$( (cd "$home" && find . -type f | sort) | comm -23 "$home.b" - | grep -v 'macup/')
[ $rc = 0 ] && [ "$got" = "$(printf '%s\n' ./.Trash/thing/blob ./Library/Caches/org.swift.swiftpm/repos/blob)" ] && jq "$work/js4.json" 'assert data["mode"]=="clean" and data["freed_kb"]>10000 and data["cleanable"]==[]' \
  && pass "--pick cleans exactly the chosen items, an opt-in one too, and nothing else" || { fail "--pick (rc=$rc)"; echo "$got"; }
env HOME="$home" macup_run clean --pick "$k3,clean.nope:1" --no-color --skip "$quick_skip" </dev/null >"$work/js.out" 2>&1; rc=$?
[ $rc = 3 ] && grep -q 'no longer there: clean.nope:1 ' "$work/js.out" && [ ! -e "$home/Library/Developer/Xcode/DerivedData/App-abc" ] && pass "--pick: a key that is gone is said, exit status 3" || { fail "--pick with a stale key (rc=$rc)"; cat "$work/js.out"; }
env HOME="$home" macup_run tasks --json >"$work/js5.json" 2>/dev/null; env HOME="$home" macup_run history --json >"$work/js6.json" 2>/dev/null
jq "$work/js5.json" 'tasks={entry["id"]:entry for entry in data["tasks"]}; assert tasks["clean.trash"]["on"] is False and tasks["check.disk"]["on"] and tasks["clean.spm"]["group"]=="clean" and data["config"].endswith("/config")' \
  && jq "$work/js6.json" 'runs=data["runs"]; assert len(runs)>=3 and runs[-1]["mode"]=="clean" and isinstance(runs[-1]["free_kb"],int) and runs[-1]["battery_cycles"] is None' \
  && pass "tasks --json and history --json" || { fail "tasks/history --json"; head -c 300 "$work/js5.json" "$work/js6.json"; }

# --- --enable turns an opt-in task on for one run
home="$work/en"; tests/fixture.sh "$home"
env HOME="$home" macup_run clean --level aggressive --only clean.trash --no-color </dev/null >/dev/null 2>&1; [ -f "$home/.Trash/thing/blob" ] && pass "an opt-in task stays off without --enable" || fail "opt-in task ran without --enable"
env HOME="$home" macup_run clean --level aggressive --only clean.trash --enable clean.trash --no-color </dev/null >/dev/null 2>&1; [ ! -e "$home/.Trash/thing" ] && pass "--enable turns it on for this run" || fail "--enable"


# shellcheck shell=bash
# shellcheck disable=SC2154,SC2088  # SC2154: work, quick_skip, build_path and the helpers come from tests/run.sh; SC2088: a literal ~ as users type it
# Sourced by tests/run.sh: exit status, --quiet, --json, hangs, lock, --deep, Full Disk Access, dev containers.
# --- exit status, --quiet, --json, a step that hangs, two runs at once
home="$work/rc"; mkdir -p "$home/.local/bin" "$home/.config/macup"; printf 'language = en\n' >"$home/.config/macup/config"
# a fake Antigravity CLI: no CI machine has a real one in /opt/homebrew/bin, which macup puts first in PATH
agy(){ printf '#!/bin/bash\ncase "$1" in --version) echo 1.0 ;; update) %s ;; esac\n' "$1" >"$home/.local/bin/agy"; chmod +x "$home/.local/bin/agy"; }
agy 'exit 1'; env HOME="$home" macup_run update --only update.agy --no-color </dev/null >"$work/rc.out" 2>&1; rc=$?
[ $rc = 3 ] && grep -q '✗ Antigravity CLI: update failed' "$work/rc.out" && pass "a failed update step: exit status 3" || { fail "exit status of a failed step (rc=$rc)"; cat "$work/rc.out"; }
agy 'exit 0'; env HOME="$home" macup_run update --only update.agy --no-color --quiet </dev/null >"$work/rc.out" 2>&1; rc=$?
[ $rc = 0 ] && grep -q 'Summary' "$work/rc.out" && grep -q 'Antigravity CLI' "$home"/Library/Logs/macup/*.md && ! grep -q '▸' "$work/rc.out" && pass "--quiet: only the summary, exit status 0" || { fail "--quiet (rc=$rc)"; cat "$work/rc.out"; }
report=$(ls -t "$home"/Library/Logs/macup/macup_*.md | head -1); grep -q '^## Command output$' "$report" && grep -qx '$ agy update' "$report" && [ -z "$(ls "$home"/Library/Logs/macup/*.log 2>/dev/null)" ] \
  && pass "one file per run: what the commands printed is at the end of the report, no .log" || { fail "command output in the report"; cat "$report"; }
env HOME="$home" macup_run check --only check.sizes --json </dev/null 2>/dev/null >"$work/rc.json"
python3 -c 'import json,sys; data=json.load(open(sys.argv[1])); assert data["mode"]=="check" and data["failed_steps"]==0 and isinstance(data["needs_attention"],list) and data["report"].endswith(".md") and data["log"]==data["report"]' "$work/rc.json" 2>/dev/null \
  && pass "--json: one valid JSON object" || { fail "--json"; cat "$work/rc.json"; }
agy 'sleep 60'; t0=$SECONDS
env HOME="$home" MACUP_STEP_SECS=2 macup_run update --only update.agy --no-color </dev/null >"$work/rc.out" 2>&1; rc=$?
[ $rc = 3 ] && [ $((SECONDS - t0)) -lt 40 ] && grep -q 'agy: stopped after' "$work/rc.out" && pass "a step that hangs is stopped" || { fail "hanging step (rc=$rc, $((SECONDS - t0))s)"; cat "$work/rc.out"; }
LK="$home/Library/Application Support/macup/lock"; mkdir -p "$LK"; echo $$ >"$LK/pid"
env HOME="$home" macup_run check --only check.sizes --no-color </dev/null >"$work/rc.out" 2>&1; rc=$?
[ $rc = 1 ] && grep -q 'already running' "$work/rc.out" && [ -d "$LK" ] && pass "a second run at the same time refuses to start" || { fail "lock (rc=$rc)"; cat "$work/rc.out"; }
true & wait $!; echo $! >"$LK/pid"   # a lock left by a run that was killed
env HOME="$home" macup_run check --only check.sizes --no-color </dev/null >"$work/rc.out" 2>&1; rc=$?
[ $rc = 0 ] && [ ! -e "$LK" ] && pass "a stale lock is taken over and removed" || { fail "stale lock (rc=$rc)"; cat "$work/rc.out"; }

# --- --deep: build folders only next to their build file; it also works with update (project_roots used to be undefined there)
home="$work/deep"; tests/fixture.sh "$home"
env HOME="$home" macup_run update --deep --only check.sizes --no-color </dev/null >"$work/deep.out" 2>&1
grep -q '~/Code/rs/target' "$work/deep.out" && ! grep -q 'Code/plain' "$work/deep.out" && ! grep -qE 'command not found|line [0-9]+:' "$work/deep.out" \
  && pass "--deep lists Rust target next to Cargo.toml, with update too" || { fail "--deep"; grep -iE 'artifact|Code/|not found' "$work/deep.out"; }

# --- the Trash cannot be read without Full Disk Access: said, not a silent 0 (root reads everything)
if [ "$(id -u)" != 0 ]; then
  home="$work/fda"; mkdir -p "$home/.Trash" "$home/.config/macup"; printf 'language = en\n' >"$home/.config/macup/config"; chmod 000 "$home/.Trash"
  env HOME="$home" macup_run check --only check.sizes --no-color </dev/null >"$work/fda.out" 2>&1; chmod 700 "$home/.Trash"
  grep -q 'Trash: cannot be read' "$work/fda.out" && pass "unreadable Trash is said" || { fail "unreadable Trash"; cat "$work/fda.out"; }
fi

# --- dev containers (opt-in): only containers named by dev_container_prefixes whose app Spotlight cannot find; a fake mdfind knows FAKE_APPS
cat >"$work/bin/mdfind" <<'FAKE'
#!/bin/bash
id=$(printf '%s' "$*" | sed -n "s/.*== '\([^']*\)'.*/\1/p")
[ -n "$FAKE_NO_SPOTLIGHT" ] && exit 0
case " com.apple.finder $FAKE_APPS " in *" $id "*) echo "/Applications/$id.app" ;; esac
FAKE
chmod +x "$work/bin/mdfind"
dch(){ # config → a fake home with containers: of a live app, its extension, gone ones, other names
  home="$work/dc"; rm -rf "$home"; mkdir -p "$home/.config/macup"; printf 'language = en\n%s\n' "$1" >"$home/.config/macup/config"
  for container in dev.acme.app dev.acme.app.share dev.acme.app-LoginHelper dev.acme.shots dev.acme.demo dev.acme.open dev.acmetool com.other.gone com.apple.Notes; do mkdir -p "$home/Library/Containers/$container/Data"; dd if=/dev/zero of="$home/Library/Containers/$container/Data/blob" bs=1024 count=64 2>/dev/null; echo m >"$home/Library/Containers/$container/.com.apple.containermanagerd.metadata.plist"; done
  mkdir -p "$home/Library/Containers/dev.acme.shell"; echo m >"$home/Library/Containers/dev.acme.shell/.com.apple.containermanagerd.metadata.plist"   # emptied before: macOS keeps the folder and the marker
  (cd "$home" && find . -type f | sort) >"$home.b"
}
dcgone(){ (cd "$work/dc" && find . -type f | sort) | comm -23 "$work/dc.b" - | grep -v 'macup/'; }
export FAKE_APPS='dev.acme.app'
dcrun(){ FAKE_OPEN="$work/dc/Library/Containers/dev.acme.open/Data/blob" env HOME="$work/dc" macup_run "$@" --no-color </dev/null >"$work/dc.out" 2>&1; }
dcpick(){ # answer confirm — an interactive check
  (sleep 2; printf '%s\n' "$1"; sleep 1; printf '%s\n' "$2"; until_done "$work/dc.out") | FAKE_OPEN="$work/dc/Library/Containers/dev.acme.open/Data/blob" script -q /dev/null env HOME="$work/dc" macup_run check --no-color --only clean.dev_containers >"$work/dc.out" 2>&1
}
prefixes='dev_container_prefixes = dev.acme, com.apple'
dch "$prefixes
enable = clean.dev_containers"; dcrun clean --level aggressive --only clean.dev_containers
[ -z "$(dcgone)" ] && pass "dev containers: never deleted without a pick, even when enabled" || { fail "dev containers: auto"; dcgone; }
dch "$prefixes"; dcrun check --only clean.dev_containers
! grep -q 'gone: ' "$work/dc.out" && pass "dev containers: unattended runs never read or offer containers" || { fail "dev containers: unattended"; cat "$work/dc.out"; }
dch "$prefixes"; dcpick '' ''; out=$(tr -d '\r' <"$work/dc.out")
echo "$out" | grep -q 'gone: dev.acme.shots (changed [0-9-]*).*only if you pick it' && echo "$out" | grep -q 'gone: dev.acme.demo' && echo "$out" | grep -q 'dev.acme.open: .*skipped' \
  && ! echo "$out" | grep -qE 'gone: (dev.acme.app|dev.acme.shell|dev.acmetool|com\.)' && [ -z "$(dcgone)" ] \
  && pass "dev containers: one pick-only item per gone container; live app, its extension, open ones, emptied ones, Apple's and other names are not offered" || { fail "dev containers: check"; echo "$out"; }
dch "$prefixes"; touch -t 202611030000 "$work/dc/Library/Containers/dev.acme.demo/Data/blob"; touch -t 202401010000 "$work/dc/Library/Containers/dev.acme.demo/Data" "$work/dc/Library/Containers/dev.acme.demo"; dcpick '' ''
tr -d '\r' <"$work/dc.out" | grep -q 'gone: dev.acme.demo (changed 2026-11-03)' && pass "dev containers: changed is the newest file inside, not the folder" || { fail "dev containers: changed date"; tr -d '\r' <"$work/dc.out" | grep 'dev.acme.demo'; }
dch "$prefixes"; dcpick '' ''; pick_number=$(tr -d '\r' <"$work/dc.out" | grep -E '^ +[0-9]+ .*gone: dev.acme.shots' | awk '{print $1}')
dch "$prefixes"; dcpick "$pick_number" y
[ "$(dcgone)" = "./Library/Containers/dev.acme.shots/Data/blob" ] && [ -f "$work/dc/.Trash/dev.acme.shots/Data/blob" ] && grep -q 'hold app data' "$work/dc.out" && pass "dev containers: a pick and a yes, after a warning about app data, move that container's contents to the Trash; the folder and the macOS marker stay" || { fail "dev containers: pick"; dcgone; tr -d '\r' <"$work/dc.out" | tail -20; }
if [ "$(id -u)" != 0 ]; then
  dch "$prefixes"; chmod 500 "$work/dc/Library/Containers/dev.acme.shots"; dcpick "$pick_number" y; chmod 700 "$work/dc/Library/Containers/dev.acme.shots"
  tr -d '\r' <"$work/dc.out" | grep -q 'dev.acme.shots.*failed' && ! grep -q 'dev.acme.shots.*cleaned\|dev.acme.shots.*freed' "$work/dc.out" && pass "dev containers: a move macOS refuses is a failure, not cleaned" || { fail "dev containers: refused removal"; tr -d '\r' <"$work/dc.out" | tail -15; }
fi
if [ "$(id -u)" != 0 ]; then
  dch "$prefixes"; chmod 000 "$work/dc/Library/Containers/dev.acme.shots"; dcpick '' ''; chmod 700 "$work/dc/Library/Containers/dev.acme.shots"
  grep -q 'dev.acme.shots: cannot be read' "$work/dc.out" && pass "dev containers: an unreadable container is said, not skipped silently" || { fail "dev containers: unreadable"; cat "$work/dc.out"; }
fi
dch "$prefixes"; mkdir -p "$work/dc/Library/Containers/dev.acme.o'q"; echo x >"$work/dc/Library/Containers/dev.acme.o'q/f"; dcpick '' ''
! grep -q "o'q" "$work/dc.out" && pass "dev containers: a name that is not a bundle id is never offered" || { fail "dev containers: odd name"; cat "$work/dc.out"; }
dch ''; dcpick '' ''
! grep -q 'dev build' "$work/dc.out" && pass "dev containers: nothing without prefixes" || { fail "dev containers: no prefixes"; cat "$work/dc.out"; }
dch "$prefixes"; FAKE_NO_SPOTLIGHT=1 dcpick '' ''
grep -q 'Spotlight does not answer' "$work/dc.out" && ! grep -q 'gone: ' "$work/dc.out" && pass "dev containers: nothing offered when Spotlight is off" || { fail "dev containers: Spotlight off"; cat "$work/dc.out"; }
unset FAKE_APPS


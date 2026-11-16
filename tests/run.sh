#!/bin/bash
# shellcheck disable=SC2088  # a literal ~ is what users type into the installer
# macup test suite. Everything runs against throwaway fake home folders; the real one is never touched.
#   tests/run.sh          all tests
cd "$(dirname "$0")/.." || exit 1
W=$(mktemp -d "${TMPDIR:-/tmp}/macup-tests.XXXXXX"); trap 'rm -rf "$W"' EXIT
F=0; pass(){ echo "PASS $*"; }; fail(){ echo "FAIL $*"; F=1; }
M="$PWD/macup"; X='update.*,clean.brew,clean.npm,clean.pnpm,clean.pip,clean.uv,clean.go,clean.go_mod,clean.sim_unavailable,clean.quicklook,clean.docker,clean.docker_images,clean.docker_containers,clean.brew_autoremove,check.*'

# `running` asks pgrep which apps are open; a fake one answers from FAKE_RUNNING (command lines, one per line), so results never depend on this machine
mkdir -p "$W/bin"; cat >"$W/bin/pgrep" <<'FAKE'
#!/bin/bash
[ "$1" = "-x" ] && { printf '%s\n' "${FAKE_PROCS:-}" | grep -qx -- "$2"; exit; }
[ "$1" = "-f" ] && [ -n "$2" ] && printf '%s\n' "${FAKE_RUNNING:-}" | grep -qE -- "$2"
FAKE
# `lsof` tells which app folders have open files: a fake one lists FAKE_OPEN paths (one per line), or fails with FAKE_LSOF_FAIL
cat >"$W/bin/lsof" <<'FAKE'
#!/bin/bash
[ -n "$FAKE_LSOF_FAIL" ] && exit 1
printf 'p1\nn/\n'; printf '%s\n' "${FAKE_OPEN:-}" | sed '/^$/d; s/^/n/'
FAKE
# launchctl and osascript only record what macup asked for: no test loads a LaunchAgent or shows a notification
# (print-disabled is a question, not a change: it answers from FAKE_SHARING and is not recorded)
for c in launchctl osascript; do printf '#!/bin/bash\n[ "$1" = print-disabled ] && { printf "%%s\\n" "${FAKE_SHARING:-}"; exit 0; }\necho "$*" >>"$HOME/%s.log"\n' "$c" >"$W/bin/$c"; done
chmod +x "$W/bin/pgrep" "$W/bin/lsof" "$W/bin/launchctl" "$W/bin/osascript"; export PATH="$W/bin:$PATH"
deleted(){ # fixture-dir macup-args… → files the run deleted
  local H=$1; shift; tests/fixture.sh "$H"; (cd "$H" && find . \( -type f -o -type l \) | sort) >"$H.b"
  env HOME="$H" /bin/bash "$M" "$@" </dev/null >"$H.out" 2>&1
  (cd "$H" && find . \( -type f -o -type l \) | sort) >"$H.a"
  comm -23 "$H.b" "$H.a" | grep -v -e '^./Library/Logs/macup/' -e '^./Library/Application Support/macup/'
}

# --- static
./build.sh --check >/dev/null 2>&1 && pass "macup is built from src/" || fail "macup is out of date: run ./build.sh"
/bin/bash -n macup && /bin/bash -n install.sh && pass syntax || fail syntax
if command -v shellcheck >/dev/null; then shellcheck -s bash -S warning macup install.sh && pass shellcheck || fail shellcheck; fi
python3 tests/translations.py >/dev/null && pass translations || { fail translations; python3 tests/translations.py | head; }

# --- nothing changes without a command
H="$W/h"; mkdir -p "$H"
for a in "" "--no-color" "--lang uk" "--level aggressive" "--skip check.docker"; do
  env HOME="$H" /bin/bash "$M" $a </dev/null >"$W/o" 2>&1; rc=$?
  [ $rc = 2 ] && grep -q 'macup check' "$W/o" && pass "no command '$a' prints help" || fail "no command '$a' (rc=$rc)"
done
env HOME="$H" /bin/bash "$M" --lang xx check </dev/null >/dev/null 2>&1; [ $? = 2 ] && pass "bad --lang" || fail "bad --lang"
env HOME="$H" /bin/bash "$M" --level huge clean </dev/null >/dev/null 2>&1; [ $? = 2 ] && pass "bad --level" || fail "bad --level"
env HOME="$H" /bin/bash "$M" bogus </dev/null >/dev/null 2>&1; [ $? = 1 ] && pass "unknown command" || fail "unknown command"
env HOME="$H" /bin/bash "$M" --deep --no-color --only check.system </dev/null 2>/dev/null | head -1 | grep -q 'check+deep' && pass "--deep alone is a check" || fail "--deep alone"
env HOME="$H" /bin/bash "$M" help --lang ru </dev/null | head -1 | grep -q 'уход за Маком' && pass "help --lang ru" || fail "help --lang ru"

# --- a non-interactive check deletes nothing, in every language, without errors
for l in en uk ru; do   # the full set of checks once; the translations with the quick ones
  if [ $l = en ]; then sk='update.*,check.macos_updates'; else sk="$X"; fi
  d=$(deleted "$W/c$l" check --lang $l --no-color --skip "$sk")
  [ -z "$d" ] && [ -z "$(grep -E 'line [0-9]+:|command not found|integer expression|unbound' "$W/c$l.out")" ] && pass "check $l: no errors, nothing deleted" || { fail "check $l"; echo "$d" | head -3; grep -E 'line [0-9]+:' "$W/c$l.out" | head -3; }
done

# --- each level deletes exactly its set; data, secrets, pins and symlink targets always survive
exp=""; for lv in safe standard aggressive; do
  exp=$(printf '%s\n%s' "$exp" "$(cat tests/expect-$lv.txt)" | grep . | sort)
  got=$(deleted "$W/l$lv" clean --level $lv --skip "$X" --no-color)
  [ "$got" = "$(echo "$exp")" ] && pass "clean --level $lv deletes exactly the expected files" || { fail "clean --level $lv"; diff <(echo "$exp") <(echo "$got") | head; }
done
echo "$got" | grep -E 'codex/sessions|sqlite|gradle.properties|settings.xml|avd|debug.keystore|adbkey|/User/|Backups|Login Data|/History|/Cookies|QtApp|ShipIt|sparkle|Local Storage|elsewhere|Archives|Downloads|Documents|BigApp|com.apple|\.Trash|Code/old|3\.12\.1|3\.13\.1|3\.10\.2|v22\.1\.0|\.m2/|virtualenvs|v21\.2\.5|v21\.7\.0|v23\.|registry/index|location_data|Code/(rs|plain)' \
  && fail "protected files deleted" || pass "protected files survive --level aggressive"
[ -f "$W/laggressive/elsewhere2/big" ] && [ -f "$W/laggressive/elsewhere/precious" ] && [ -f "$W/laggressive/elsewhere3/Cache/big" ] && pass "symlinked cache targets survive" || fail "symlink target deleted"

# --- an app that is open is skipped, and the summary says so
H="$W/run"; tests/fixture.sh "$H"
FAKE_RUNNING='/Applications/Cursor.app/Contents/MacOS/Cursor' env HOME="$H" /bin/bash "$M" clean --skip "$X" --no-color </dev/null >"$W/run.out" 2>&1
[ -f "$H/Library/Application Support/Cursor/Cache/c/blob" ] && grep -q 'Cursor caches.*skipped' "$W/run.out" && pass "open app is skipped" || fail "open app was cleaned"
grep -q 'Skipped because the app is open (1)' "$W/run.out" && grep -q '    · Cursor caches' "$W/run.out" && pass "summary lists what was skipped" || fail "summary does not list the skipped app"
grep -q 'Needs attention: nothing' "$W/run.out" && pass "a skipped app is not a warning" || fail "skipped app became a warning"
tests/fixture.sh "$H"   # Application Support/Codex is used by ChatGPT.app, not Codex.app
FAKE_RUNNING="/Applications/ChatGPT.app/Contents/Frameworks/Codex Framework.framework/Helpers/Codex (Service).app/Contents/MacOS/Codex (Service) --type=gpu-process --user-data-dir=$H/Library/Application Support/Codex --standard-schemes" \
  env HOME="$H" /bin/bash "$M" clean --only clean.editors --no-color </dev/null >"$W/run.out" 2>&1
[ -f "$H/Library/Application Support/Codex/Default/Partitions/browser/Code Cache/js/blob" ] && [ ! -f "$H/Library/Application Support/Claude/Cache/c/blob" ] \
  && pass "an app open under another name is skipped by its --user-data-dir" || fail "app open under another name was cleaned"
tests/fixture.sh "$H"   # an app macup has no name for: open while it has files open in its folder; unknown when lsof fails
FAKE_OPEN="$H/Library/Application Support/SomeApp/Cookies" env HOME="$H" /bin/bash "$M" clean --only clean.editors --no-color </dev/null >"$W/run.out" 2>&1
[ -f "$H/Library/Application Support/SomeApp/Cache/c/blob" ] && [ -f "$H/Library/Caches/SomeApp/Default/Cache/blob" ] && grep -q 'SomeApp caches.*skipped' "$W/run.out" \
  && [ ! -f "$H/Library/Application Support/Claude/Cache/c/blob" ] && pass "an unknown app with open files is skipped" || fail "an unknown open app was cleaned"
tests/fixture.sh "$H"
FAKE_LSOF_FAIL=1 env HOME="$H" /bin/bash "$M" clean --only clean.editors --no-color </dev/null >"$W/run.out" 2>&1
[ -f "$H/Library/Application Support/SomeApp/Cache/c/blob" ] && [ ! -f "$H/Library/Application Support/Claude/Cache/c/blob" ] \
  && pass "lsof fails: unknown apps are left alone, known ones still cleaned" || fail "lsof failed and an unknown app was cleaned"

# --- picking after an interactive check
# keeps the fake terminal open until macup has written its report (slow machines need longer than a fixed sleep)
until_done(){ local i=0; while [ $i -lt 240 ]; do grep -qE 'Report: |Звіт: |Отчёт: ' "$1" 2>/dev/null && return; sleep 0.5; i=$((i + 1)); done; }
pick(){ # answer [confirm] → files deleted
  local H="$W/p"; tests/fixture.sh "$H"; (cd "$H" && find . -type f | sort) >"$W/pb"
  (sleep 2; printf '%s\n' "$1"; sleep 1; printf '%s\n' "${2:-}"; until_done "$W/po") | script -q /dev/null env HOME="$H" /bin/bash "$M" check --no-color --skip "$X" ${PL:+--lang $PL} >"$W/po" 2>&1
  (cd "$H" && find . -type f | sort) | comm -23 "$W/pb" - | grep -v -e 'Logs/macup/' -e 'Support/macup/'
}
num(){ tr -d '\r' <"$W/po" | grep -E "^ +[0-9]+ .*$1" | head -1 | awk '{print $1}'; }
[ -z "$(pick '')" ] && pass "pick: Enter deletes nothing" || fail "pick: Enter"
[ -z "$(pick 'zzz, 999')" ] && pass "pick: garbage deletes nothing" || fail "pick: garbage"
pick '' >/dev/null; n1=$(num 'Xcode DerivedData'); n2=$(num 'SwiftPM cache'); nt=$(num 'Trash')
[ "$(pick "$n1,$n2" | LC_ALL=C sort)" = "$(printf '%s\n' './Library/Caches/org.swift.swiftpm/repos/blob' './Library/Developer/Xcode/DerivedData/App-abc/blob' | LC_ALL=C sort)" ] && pass "pick: numbers delete exactly those" || fail "pick: numbers"
[ -z "$(pick "$nt" n)" ] && pass "pick: opt-in item needs a yes" || fail "pick: confirmation"
[ "$(pick "$nt" y)" = "./.Trash/thing/blob" ] && pass "pick: opt-in item after yes" || fail "pick: yes"
got=$(PL=uk pick 'безпечна')
[ "$(echo "$got" | LC_ALL=C sort)" = "$(LC_ALL=C sort <tests/expect-safe.txt)" ] && pass "pick: a level word in the interface language" || { fail "pick: localized level"; diff <(LC_ALL=C sort <tests/expect-safe.txt) <(echo "$got") | head; }

# --- simulators: only on pick, never a booted one; a fake xcrun records what macup asks for
H="$W/sim"; mkdir -p "$H/.local/bin" "$H/.config/macup"; printf 'language = en\n' >"$H/.config/macup/config"
SD="$H/Library/Developer/CoreSimulator/Devices"
mkdir -p "$SD/AAAA-0001/data" "$SD/BBBB-0002/data/Containers" "$SD/CCCC-0003/data" "$SD/DDDD-0004/data"
dd if=/dev/zero of="$SD/BBBB-0002/data/Containers/app" bs=1024 count=103424 2>/dev/null   # heavy, recently used
echo x >"$SD/CCCC-0003/data/x"; find "$SD/CCCC-0003" -exec touch -t 202401010000 {} +    # unused for a long time
echo x >"$SD/DDDD-0004/data/x"                                                           # used today
cat >"$H/.local/bin/xcrun" <<'FAKE'
#!/bin/bash
case "$*" in
  "simctl list devices -j") echo '{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-26-5":[{"udid":"AAAA-0001","state":"Booted","name":"iPhone A"},{"udid":"CCCC-0003","state":"Shutdown","name":"iPhone C"}],"com.apple.CoreSimulator.SimRuntime.iOS-27-0":[{"udid":"BBBB-0002","state":"Shutdown","name":"iPhone B"},{"udid":"DDDD-0004","state":"Shutdown","name":"iPhone D"}],"com.apple.CoreSimulator.SimRuntime.iOS-25-0":[]}}' ;;
  "simctl runtime list -j") echo '{"A1B2-0026":{"runtimeIdentifier":"com.apple.CoreSimulator.SimRuntime.iOS-26-5","version":"26.5","sizeBytes":8000000000,"lastUsedAt":"2026-10-10T00:00:00Z","deletable":true},"A1B2-0027":{"runtimeIdentifier":"com.apple.CoreSimulator.SimRuntime.iOS-27-0","version":"27.0","sizeBytes":7000000000,"deletable":true},"A1B2-0025":{"runtimeIdentifier":"com.apple.CoreSimulator.SimRuntime.iOS-25-0","version":"25.0","sizeBytes":6000000000,"lastUsedAt":"2025-01-01T00:00:00Z","deletable":true}}' ;;
  simctl\ list*) ;;
  *) echo "$*" >>"$HOME/xcrun.log" ;;
esac
FAKE
chmod +x "$H/.local/bin/xcrun"; SO='clean.sim_runtimes,clean.sim_erase,clean.sim_unused'
env HOME="$H" /bin/bash "$M" clean --level aggressive --only "$SO" --no-color </dev/null >/dev/null 2>&1
[ ! -s "$H/xcrun.log" ] && pass "simulators: nothing without a pick, even at --level aggressive" || { fail "simulators touched without a pick"; cat "$H/xcrun.log"; }
(sleep 2; printf '1-20\n'; sleep 1; printf 'y\n'; until_done "$W/sim.out") | script -q /dev/null env HOME="$H" /bin/bash "$M" check --only "$SO" --no-color >"$W/sim.out" 2>&1
want=$(printf '%s\n' 'simctl runtime delete A1B2-0027' 'simctl runtime delete A1B2-0025' 'simctl erase BBBB-0002' 'simctl delete CCCC-0003' | sort)
[ "$(sort "$H/xcrun.log" 2>/dev/null)" = "$want" ] && pass "simulators: exactly the picked runtimes and devices; booted and recent ones stay" \
  || { fail "simulators"; echo "want:"; echo "$want"; echo "got:"; cat "$H/xcrun.log"; tr -d '\r' <"$W/sim.out" | grep -iE 'simulat|runtime' | head; }

# --- unavailable simulators: the default set and Xcode's test clones (XCTestDevices), with their real size; never while Xcode runs
H="$W/unav"; mkdir -p "$H/.local/bin" "$H/.config/macup"; printf 'language = en\n' >"$H/.config/macup/config"
U1=11111111-AAAA-4AAA-8AAA-111111111111; U2=22222222-BBBB-4BBB-8BBB-222222222222; XT="$H/Library/Developer/XCTestDevices"
for d in "$H/Library/Developer/CoreSimulator/Devices/$U1" "$XT/$U2"; do mkdir -p "$d/data"; dd if=/dev/zero of="$d/data/x" bs=1024 count=3072 2>/dev/null; done
cat >"$H/.local/bin/xcrun" <<FAKE
#!/bin/bash
case "\$*" in
  "simctl list devices unavailable") [ -z "\$NODEFAULT" ] && echo "    iPhone A ($U1) (Shutdown) (unavailable, runtime profile not found)" ;;
  "simctl --set $XT list devices unavailable") echo "    Clone 2 of iPhone B ($U2) (Shutdown) (unavailable, runtime profile not found)" ;;
  simctl\ *list*) ;;
  *) echo "\$*" >>"\$HOME/xcrun.log" ;;
esac
FAKE
chmod +x "$H/.local/bin/xcrun"
env HOME="$H" /bin/bash "$M" check --only clean.sim_unavailable --no-color </dev/null >"$W/unav.out" 2>&1
grep -qE 'safe +6 MB +Unavailable simulators \(2\)' "$W/unav.out" && [ ! -s "$H/xcrun.log" ] && pass "unavailable simulators: check shows both sets with their size" || { fail "unavailable simulators: check"; grep -i simulat "$W/unav.out"; }
FAKE_RUNNING='/Applications/Xcode.app/Contents/MacOS/Xcode' env HOME="$H" /bin/bash "$M" clean --only clean.sim_unavailable --no-color </dev/null >"$W/unav.out" 2>&1
[ ! -s "$H/xcrun.log" ] && grep -q 'Unavailable simulators (2).*skipped' "$W/unav.out" && pass "unavailable simulators: skipped while Xcode is open" || fail "unavailable simulators deleted while Xcode is open"
env HOME="$H" /bin/bash "$M" clean --only clean.sim_unavailable --no-color </dev/null >"$W/unav.out" 2>&1
[ "$(cat "$H/xcrun.log" 2>/dev/null)" = "$(printf '%s\n' 'simctl delete unavailable' "simctl --set $XT delete unavailable")" ] && pass "unavailable simulators: both sets deleted" || { fail "unavailable simulators: delete"; cat "$H/xcrun.log"; }
rm -f "$H/xcrun.log"; env NODEFAULT=1 HOME="$H" /bin/bash "$M" clean --only clean.sim_unavailable --no-color </dev/null >"$W/unav.out" 2>&1
[ "$(cat "$H/xcrun.log" 2>/dev/null)" = "simctl --set $XT delete unavailable" ] && pass "unavailable simulators: only the set that has some" || { fail "unavailable simulators: only test clones"; cat "$H/xcrun.log"; }

# --- npm/npx on PATH without node (unlinked keg-only node@24): both steps say so instead of a false "up to date"
if ! PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin" command -v node >/dev/null; then
  H="$W/nonode"; mkdir -p "$H/.local/bin" "$H/.agents" "$H/.config/macup"; printf 'language = en\n' >"$H/.config/macup/config"; echo '{"skills":{}}' >"$H/.agents/.skill-lock.json"
  for c in npm npx; do printf '#!/bin/bash\necho "%s $*" >>"$HOME/npm.log"\n' "$c" >"$H/.local/bin/$c"; chmod +x "$H/.local/bin/$c"; done
  mkdir -p "$H/brew/opt/node@24/bin"; cp /usr/bin/true "$H/brew/opt/node@24/bin/node"
  env PATH="$W/bin:/usr/bin:/bin" HOME="$H" HOMEBREW_PREFIX="$H/brew" /bin/bash "$M" check --only update.npm,update.skills --no-color </dev/null >"$W/nonode.out" 2>&1
  grep -q 'npm globals: skipped, node is not on PATH — run: brew link --.* node' "$W/nonode.out" && grep -q 'Agent skills: skipped, node is not on PATH — run: brew link' "$W/nonode.out" \
    && ! grep -q 'up to date' "$W/nonode.out" && [ ! -e "$H/npm.log" ] && pass "no node: npm globals and agent skills skipped with a warning" \
    || { fail "no node"; grep -iE 'npm|skill' "$W/nonode.out"; cat "$H/npm.log" 2>/dev/null; }
else echo "SKIP no node: node is installed here"; fi

# --- App Store: the list comes first, then one app at a time with its own result; no password means nothing runs
# mas and sudo are exported functions: macup puts /opt/homebrew/bin first in PATH, so a fake file would lose to the real mas
H="$W/mas"; mkdir -p "$H/.config/macup"; printf 'language = en\n' >"$H/.config/macup/config"
mas(){ case $1 in outdated) printf '        1  Foo          (1.0    -> 1.1)\n123456789  Bar Baz Pro  (2.10.3 -> 3.0)\n' ;; upgrade) echo "mas $*" >>"$HOME/mas.log"; [ "$2" = 1 ] ;; esac; }
sudo(){ [ -z "$NOSUDO" ]; }
export -f mas sudo
env HOME="$H" /bin/bash "$M" update --only update.mas --no-color </dev/null >"$W/mas.out" 2>&1
grep -q '^      Bar Baz Pro (2.10.3 → 3.0)$' "$W/mas.out" && grep -q '✓ App Store: Foo (1.0 → 1.1)$' "$W/mas.out" \
  && grep -q '✗ App Store: updates not installed: Bar Baz Pro (2.10.3 → 3.0) — open the App Store' "$W/mas.out" \
  && [ "$(cat "$H/mas.log")" = "$(printf 'mas upgrade 1\nmas upgrade 123456789')" ] && pass "App Store: list, then each app with its result" \
  || { fail "App Store update"; grep 'App Store\|→' "$W/mas.out"; cat "$H/mas.log" 2>/dev/null; }
rm -f "$H/mas.log"; env NOSUDO=1 HOME="$H" /bin/bash "$M" update --only update.mas --no-color </dev/null >"$W/mas.out" 2>&1
grep -q 'updates not installed: 2 — they need your Mac password' "$W/mas.out" && [ ! -e "$H/mas.log" ] && pass "App Store: no password, mas never runs" \
  || { fail "App Store without a password"; grep 'App Store' "$W/mas.out"; }
unset -f mas sudo

# --- commands that cannot start: missing interpreter, pipx venv whose Python is gone, broken link; working ones stay quiet
H="$W/cmds"; B="$H/.local/bin"; V="$H/.local/pipx/venvs/tool/bin"; mkdir -p "$B" "$H/.npm-global/bin" "$V" "$H/.config/macup"; printf 'language = en\n' >"$H/.config/macup/config"
printf '#!/usr/bin/env macup_no_such_interp\n' >"$B/nodecli"; printf '#!/usr/bin/env -S macup_no_such_interp --flag\n' >"$H/.npm-global/bin/flagcli"
printf '#!/bin/sh\necho ok\n' >"$B/okscript"; cp /usr/bin/true "$B/okbinary"
ln -s "$H/gone/python3.12" "$V/python"; printf '#!%s\n' "$V/python" >"$V/tool"; ln -s "$V/tool" "$B/pipxtool"
for i in 01 02 03 04 05 06 07 08 09 10 11; do ln -s "$H/gone/thing" "$B/gone$i"; done; ln -s "$H/gone/thing" "$B/gonelink"; ln -s "$H/gone/Old.app/Contents/MacOS/old" "$B/oldapp"
mkdir -p "$H/Cellar/x/1/bin"; printf '#!/usr/bin/env macup_no_such_interp\n' >"$H/Cellar/x/1/bin/brewcli"; ln -s "$H/Cellar/x/1/bin/brewcli" "$B/brewcli"; ln -s "$H/Cellar/y/1/bin/gone" "$B/brewgone"   # Homebrew's own files are brew doctor's job
# interpreters a formula has but brew has not linked: the newest versioned keg, or the unversioned formula
printf '#!/usr/bin/env macup_keg_interp\n' >"$B/kegcli"; printf '#!/usr/bin/env macup_plain_interp\n' >"$B/plaincli"
for k in macup_keg_interp@9/bin/macup_keg_interp macup_keg_interp@10/bin/macup_keg_interp macup_plain_interp/bin/macup_plain_interp sh/bin/sh; do mkdir -p "$H/brew/opt/${k%/*}"; cp /usr/bin/true "$H/brew/opt/$k"; done
# a dead absolute interpreter whose name is on PATH (a venv's python3): brew link would not fix it
printf '#!%s\n' "$H/gone/bin/sh" >"$B/deadsh"
chmod +x "$B"/* "$V/tool" "$H/.npm-global/bin/flagcli" "$H/Cellar/x/1/bin/brewcli"
env HOME="$H" HOMEBREW_PREFIX="$H/brew" /bin/bash "$M" check --only check.commands --no-color </dev/null >"$W/cmds.out" 2>&1
grep -q 'cannot start, macup_no_such_interp is missing: flagcli, nodecli$' "$W/cmds.out" \
  && grep -q 'cannot start, python is missing: .*pipxtool.* — run: pipx reinstall-all' "$W/cmds.out" \
  && grep -qF 'macup_keg_interp is missing: kegcli — run: brew link --force --overwrite macup_keg_interp@10' "$W/cmds.out" \
  && grep -qF 'macup_plain_interp is missing: plaincli — run: brew link --overwrite macup_plain_interp' "$W/cmds.out" \
  && grep -q 'cannot start, sh is missing: deadsh$' "$W/cmds.out" \
  && grep -qF 'Dead links in ~/.local/bin, leftovers of removed Old.app, ~/gone: gone01, gone02,' "$W/cmds.out" \
  && grep -qF 'gone10 +3 — safe to remove, run in Terminal: find ~/.local/bin -maxdepth 1 -type l ! -exec test -e {} \; -print -delete' "$W/cmds.out" \
  && ! grep -E 'cannot start|Dead links' "$W/cmds.out" | grep -qE 'okscript|okbinary|brewcli|brewgone' \
  && pass "commands that cannot start are listed with a fix; working ones are not" || { fail "commands that cannot start"; cat "$W/cmds.out"; }
# only the fake home's line: the real /opt/homebrew/bin and /usr/local/bin are scanned too, and their fix may need sudo
fix=$(sed -n 's|.*Dead links in ~/\.local/bin, .* run in Terminal: \(find ~/\.local/bin .*\)$|\1|p' "$W/cmds.out" | head -1)
[ -n "$fix" ] && (HOME="$H"; eval "$fix") >/dev/null 2>&1 </dev/null
[ -n "$fix" ] && [ ! -L "$B/gone01" ] && [ ! -L "$B/gonelink" ] && [ ! -L "$B/oldapp" ] && [ -e "$B/okscript" ] && [ -e "$B/okbinary" ] && [ -L "$B/pipxtool" ] && [ -L "$B/brewcli" ] \
  && pass "the dead-link fix removes only dead links" || { fail "dead-link fix: $fix"; ls -la "$B"; }

# --- Time Machine can be skipped on its own, and --only check.security still includes it
H="$W/tm"; mkdir -p "$H/.config/macup"; printf 'language = en\n' >"$H/.config/macup/config"
tm(){ env HOME="$H" /bin/bash "$M" check --no-color "$@" </dev/null 2>&1; }
tm --only check.security | grep -q 'Time Machine:' && ! tm --only check.security --skip check.time_machine | grep -q 'Time Machine:' \
  && tm --only check.security --skip check.time_machine | grep -q 'FileVault' \
  && pass "check.time_machine hides only Time Machine" || fail "check.time_machine"

# --- uninstall removes every file macup made, keeps a PATH line other programs need, and leaves a Homebrew install to brew
# it also looks for older copies in /usr/local/bin and /opt/homebrew/bin: never run it where a real one is there
if [ -e /usr/local/bin/macup ] || [ -e /opt/homebrew/bin/macup ]; then echo "SKIP uninstall: a real macup is in /usr/local/bin or /opt/homebrew/bin"
else
  H="$W/un"; T="$H/tmp"; mkdir -p "$T" "$H/.local/bin" "$H/.npm-global/bin" "$H/.config/macup" "$H/Library/Logs/macup" "$H/Library/Application Support/macup"
  cp macup "$H/.local/bin/macup"; cp macup "$H/.npm-global/bin/macup"; printf 'language = en\n' >"$H/.config/macup/config"
  echo r >"$H/Library/Logs/macup/macup_x.md"; echo h >"$H/Library/Application Support/macup/history.csv"
  printf 'alias ll=ls\n\n# macup\nexport PATH="$HOME/.local/bin:$PATH"\nexport EDITOR=vim\n' >"$H/.zshrc"
  touch "$T/macup.Ab12Cd" "$T/macup.Ab12Cd.rt" "$T/macup-lang.Zz99Yy" "$T/other.txt"
  SP="$H/Library/LaunchAgents/com.vitaliideveloper.macup.plist"; mkdir -p "${SP%/*}"; echo '<plist/>' >"$SP"
  env HOME="$H" TMPDIR="$T/" /bin/bash "$H/.local/bin/macup" uninstall --no-color </dev/null >"$W/un0.out" 2>&1
  [ -e "$H/.local/bin/macup" ] && [ -d "$H/.config/macup" ] && grep -q 'Nothing removed' "$W/un0.out" && pass "uninstall without a terminal or --yes removes nothing" || { fail "uninstall: no answer"; cat "$W/un0.out"; }
  env HOME="$H" TMPDIR="$T/" /bin/bash "$H/.local/bin/macup" uninstall --yes --no-color </dev/null >"$W/un.out" 2>&1
  [ ! -e "$H/.local/bin/macup" ] && [ ! -e "$H/.npm-global/bin/macup" ] && [ ! -e "$H/.config/macup" ] && [ ! -e "$H/Library/Logs/macup" ] && [ ! -e "$SP" ] \
    && [ ! -e "$H/Library/Application Support/macup" ] && [ "$(cat "$H/.zshrc")" = "$(printf 'alias ll=ls\nexport EDITOR=vim')" ] \
    && [ "$(ls "$T")" = other.txt ] && pass "uninstall --yes removes macup, older copies, settings, history, reports, the schedule, the PATH line, temp files" \
    || { fail "uninstall --yes"; cat "$W/un.out"; cat "$H/.zshrc"; ls -la "$T"; }
  H="$W/un2"; mkdir -p "$H/.local/bin" "$H/brew/Cellar/macup/9.9.9/bin" "$H/brew/bin"; cp macup "$H/.local/bin/macup"; cp /usr/bin/true "$H/.local/bin/claude"
  printf '\n# macup\nexport PATH="$HOME/.local/bin:$PATH"\n' >"$H/.zshrc"
  env HOME="$H" TMPDIR="$H/" /bin/bash "$H/.local/bin/macup" uninstall --yes --no-color </dev/null >"$W/un2.out" 2>&1
  [ ! -e "$H/.local/bin/macup" ] && [ -e "$H/.local/bin/claude" ] && grep -q '^# macup' "$H/.zshrc" && grep -q 'Kept: the PATH line in ~/.zshrc, because ~/.local/bin also has claude' "$W/un2.out" \
    && pass "uninstall keeps the PATH line when other programs live in that folder" || { fail "uninstall: PATH line kept"; cat "$W/un2.out"; }
  cp macup "$H/brew/Cellar/macup/9.9.9/bin/macup"; ln -s ../Cellar/macup/9.9.9/bin/macup "$H/brew/bin/macup"
  printf '#!/bin/bash\necho "brew $*" >>"%s/brew.log"\n' "$H" >"$H/brew/bin/brew"; chmod +x "$H/brew/bin/brew"
  env HOME="$H" /bin/bash "$H/brew/bin/macup" self-update --no-color </dev/null >"$W/un3.out" 2>&1
  env HOME="$H" TMPDIR="$H/" /bin/bash "$H/brew/bin/macup" uninstall --yes --no-color </dev/null >>"$W/un3.out" 2>&1
  grep -q 'installed with Homebrew. Update it with: brew upgrade macup' "$W/un3.out" && grep -qx 'brew uninstall macup' "$H/brew.log" \
    && pass "a Homebrew install: self-update points to brew upgrade, uninstall runs brew uninstall" || { fail "uninstall: Homebrew"; cat "$W/un3.out" "$H/brew.log"; }
fi

# --- sizes of what macup never deletes are shown by update too, not only by check and clean
H="$W/sizes"; mkdir -p "$H/Library/Developer/Xcode/Archives/a.xcarchive" "$H/.config/macup"; printf 'language = en\n' >"$H/.config/macup/config"
echo build >"$H/Library/Developer/Xcode/Archives/a.xcarchive/Info.plist"
env HOME="$H" /bin/bash "$M" update --only check.sizes --no-color </dev/null >"$W/sizes.out" 2>&1
grep -q 'Xcode Archives: ' "$W/sizes.out" && pass "update shows Xcode Archives size" || { fail "update: sizes"; cat "$W/sizes.out"; }

# --- grok: a check reads `grok update --check --json`; an install that brew or npm owns is left alone
mkdir -p "$W/gbin"; printf '#!/bin/bash\nprintf "%%s" "$FAKE_GROK"\n' >"$W/gbin/grok"; chmod +x "$W/gbin/grok"
grok_check(){ env HOME="$H" PATH="$W/gbin:$PATH" FAKE_GROK="$1" /bin/bash "$M" check --only update.grok --no-color </dev/null 2>&1; }
grok_check '{"currentVersion":"1.0.70","latestVersion":"1.0.77","installer":"internal","error":null}' | grep -q 'Grok CLI: 1.0.70 → 1.0.77 available' && pass "grok: newer version shown" || fail "grok: newer version"
grok_check '{"currentVersion":"1.0.70","latestVersion":"1.0.77","installer":"brew","error":null}' | grep -q 'Grok' && fail "grok: brew install is not ours" || pass "grok: brew install left to brew"
grok_check '{"currentVersion":"1.0.70","latestVersion":null,"installer":"internal","error":"offline"}' | grep -q 'Grok CLI: could not check' && pass "grok: failed check said" || fail "grok: failed check"

# --- apps outside Homebrew: compared with the cached cask catalog (the download fails here, so the cache is used)
printf '#!/bin/bash\nexit 1\n' >"$W/gbin/curl"; chmod +x "$W/gbin/curl"
H="$W/apps"; mkdir -p "$H/.config/macup" "$H/Library/Caches/macup"; printf 'language = en\n' >"$H/.config/macup/config"
apps_check(){ env HOME="$H" PATH="$W/gbin:$PATH" /bin/bash "$M" check --only update.apps --no-color </dev/null 2>&1; }
apps_check | grep -q 'Apps outside Homebrew and the App Store: could not check' && pass "apps: no catalog is said" || fail "apps: no catalog"
for a in MacupOld:1.0 MacupNew:2.0 MacupMas:1.0 MacupTwin:1.0; do
  mkdir -p "$H/Applications/${a%:*}.app/Contents"
  printf '<?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleShortVersionString</key><string>%s</string></dict></plist>' "${a#*:}" >"$H/Applications/${a%:*}.app/Contents/Info.plist"
done
mkdir -p "$H/Applications/MacupMas.app/Contents/_MASReceipt"
cask(){ printf '{"token":"%s","version":"%s","artifacts":[{"app":["%s.app"]}]}' "$@"; }
printf '[%s,%s,%s,%s,%s,%s]' "$(cask macup-old 2.0,abc MacupOld)" "$(cask macup-old@beta 3.0 MacupOld)" "$(cask macup-new 2.0 MacupNew)" \
  "$(cask macup-mas 2.0 MacupMas)" "$(cask macup-twin 2.0 MacupTwin)" "$(cask macup-twin-desktop 7.0 MacupTwin)" >"$H/Library/Caches/macup/cask.json"
o=$(apps_check)
echo "$o" | grep -q 'Apps with a newer version: 1 (MacupOld) ' && echo "$o" | grep -q 'MacupOld 1.0 → 2.0$' && ! echo "$o" | grep -qE 'MacupNew|MacupMas|MacupTwin' \
  && pass "apps: only the app behind its catalog version is listed" || { fail "apps: list"; echo "$o" | head; }

# --- stale node_modules (opt-in): the project untouched for 90 days loses it, the fresh one keeps it; it used to say "cleaned" and delete nothing
H="$W/nm"; got=$(tests/fixture.sh "$H"; printf 'enable = clean.stale_node_modules\n' >>"$H/.config/macup/config"; (cd "$H" && find . -type f | sort) >"$H.b"
  env HOME="$H" /bin/bash "$M" clean --level standard --only clean.stale_node_modules --no-color </dev/null >"$H.out" 2>&1; (cd "$H" && find . -type f | sort) | comm -23 "$H.b" - | grep -v 'macup/')
[ "$got" = "./Code/old/node_modules/a/blob" ] && grep -q 'Stale node_modules.*freed' "$H.out" && pass "stale node_modules: only the stale project's folder is deleted" || { fail "stale node_modules"; echo "$got"; cat "$H.out"; }

# --- other big caches: a folder with virtualenvs inside (Poetry) is never offered
H="$W/ac"; tests/fixture.sh "$H"; dd if=/dev/zero of="$H/Library/Caches/pypoetry/virtualenvs/proj-Ab12-py3.12/lib/big" bs=1024 count=103424 2>/dev/null
env HOME="$H" /bin/bash "$M" check --only clean.app_caches --no-color </dev/null >"$W/ac.out" 2>&1
grep -q 'App cache: BigApp' "$W/ac.out" && ! grep -q pypoetry "$W/ac.out" && pass "big caches: Poetry's virtualenvs are not offered" || { fail "big caches"; grep 'App cache' "$W/ac.out"; }

# --- DerivedData is left alone while an xcodebuild started from a terminal runs
H="$W/xb"; tests/fixture.sh "$H"
FAKE_RUNNING='/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -scheme App build' env HOME="$H" /bin/bash "$M" clean --only clean.derived_data --no-color </dev/null >"$W/xb.out" 2>&1
[ -f "$H/Library/Developer/Xcode/DerivedData/App-abc/blob" ] && grep -q 'DerivedData.*skipped' "$W/xb.out" && pass "DerivedData skipped while xcodebuild runs" || { fail "DerivedData cleaned during xcodebuild"; cat "$W/xb.out"; }

# --- exit status, --quiet, --json, a step that hangs, two runs at once
H="$W/rc"; mkdir -p "$H/.local/bin" "$H/.config/macup"; printf 'language = en\n' >"$H/.config/macup/config"
# a fake Antigravity CLI: no CI machine has a real one in /opt/homebrew/bin, which macup puts first in PATH
agy(){ printf '#!/bin/bash\ncase "$1" in --version) echo 1.0 ;; update) %s ;; esac\n' "$1" >"$H/.local/bin/agy"; chmod +x "$H/.local/bin/agy"; }
agy 'exit 1'; env HOME="$H" /bin/bash "$M" update --only update.agy --no-color </dev/null >"$W/rc.out" 2>&1; rc=$?
[ $rc = 3 ] && grep -q '✗ Antigravity CLI: update failed' "$W/rc.out" && pass "a failed update step: exit status 3" || { fail "exit status of a failed step (rc=$rc)"; cat "$W/rc.out"; }
agy 'exit 0'; env HOME="$H" /bin/bash "$M" update --only update.agy --no-color --quiet </dev/null >"$W/rc.out" 2>&1; rc=$?
[ $rc = 0 ] && grep -q 'Summary' "$W/rc.out" && grep -q 'Antigravity CLI' "$H"/Library/Logs/macup/*.md && ! grep -q '▸' "$W/rc.out" && pass "--quiet: only the summary, exit status 0" || { fail "--quiet (rc=$rc)"; cat "$W/rc.out"; }
r=$(ls -t "$H"/Library/Logs/macup/macup_*.md | head -1); grep -q '^## Command output$' "$r" && grep -qx '$ agy update' "$r" && [ -z "$(ls "$H"/Library/Logs/macup/*.log 2>/dev/null)" ] \
  && pass "one file per run: what the commands printed is at the end of the report, no .log" || { fail "command output in the report"; cat "$r"; }
env HOME="$H" /bin/bash "$M" check --only check.sizes --json </dev/null 2>/dev/null >"$W/rc.json"
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["mode"]=="check" and d["failed_steps"]==0 and isinstance(d["needs_attention"],list) and d["report"].endswith(".md") and d["log"]==d["report"]' "$W/rc.json" 2>/dev/null \
  && pass "--json: one valid JSON object" || { fail "--json"; cat "$W/rc.json"; }
agy 'sleep 60'; t0=$SECONDS
env HOME="$H" MACUP_STEP_SECS=2 /bin/bash "$M" update --only update.agy --no-color </dev/null >"$W/rc.out" 2>&1; rc=$?
[ $rc = 3 ] && [ $((SECONDS - t0)) -lt 40 ] && grep -q 'agy: stopped after' "$W/rc.out" && pass "a step that hangs is stopped" || { fail "hanging step (rc=$rc, $((SECONDS - t0))s)"; cat "$W/rc.out"; }
LK="$H/Library/Application Support/macup/lock"; mkdir -p "$LK"; echo $$ >"$LK/pid"
env HOME="$H" /bin/bash "$M" check --only check.sizes --no-color </dev/null >"$W/rc.out" 2>&1; rc=$?
[ $rc = 1 ] && grep -q 'already running' "$W/rc.out" && [ -d "$LK" ] && pass "a second run at the same time refuses to start" || { fail "lock (rc=$rc)"; cat "$W/rc.out"; }
true & wait $!; echo $! >"$LK/pid"   # a lock left by a run that was killed
env HOME="$H" /bin/bash "$M" check --only check.sizes --no-color </dev/null >"$W/rc.out" 2>&1; rc=$?
[ $rc = 0 ] && [ ! -e "$LK" ] && pass "a stale lock is taken over and removed" || { fail "stale lock (rc=$rc)"; cat "$W/rc.out"; }

# --- --deep: build folders only next to their build file; it also works with update (project_roots used to be undefined there)
H="$W/deep"; tests/fixture.sh "$H"
env HOME="$H" /bin/bash "$M" update --deep --only check.sizes --no-color </dev/null >"$W/deep.out" 2>&1
grep -q '~/Code/rs/target' "$W/deep.out" && ! grep -q 'Code/plain' "$W/deep.out" && ! grep -qE 'command not found|line [0-9]+:' "$W/deep.out" \
  && pass "--deep lists Rust target next to Cargo.toml, with update too" || { fail "--deep"; grep -iE 'artifact|Code/|not found' "$W/deep.out"; }

# --- the Trash cannot be read without Full Disk Access: said, not a silent 0 (root reads everything)
if [ "$(id -u)" != 0 ]; then
  H="$W/fda"; mkdir -p "$H/.Trash" "$H/.config/macup"; printf 'language = en\n' >"$H/.config/macup/config"; chmod 000 "$H/.Trash"
  env HOME="$H" /bin/bash "$M" check --only check.sizes --no-color </dev/null >"$W/fda.out" 2>&1; chmod 700 "$H/.Trash"
  grep -q 'Trash: cannot be read' "$W/fda.out" && pass "unreadable Trash is said" || { fail "unreadable Trash"; cat "$W/fda.out"; }
fi

# --- system checks read the output of macOS tools: fakes with real samples, so a format change shows up here
SB="$W/sbin"; mkdir -p "$SB"; H="$W/sys"; mkdir -p "$H/.config/macup"; printf 'language = en\n' >"$H/.config/macup/config"
sys(){ env HOME="$H" PATH="$SB:$PATH" /bin/bash "$M" check --no-color "$@" </dev/null 2>&1; }
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
o=$(sys --only check.macos_updates)
echo "$o" | grep -q 'macOS: updates available' && echo "$o" | grep -q '^ *Command Line Tools for Xcode 16.0$' && echo "$o" | grep -q '^ *macOS Sequoia 15.1$' \
  && NO_UPDATES=1 sys --only check.macos_updates | grep -q 'macOS: up to date' && pass "macOS updates: titles read from softwareupdate -l" || { fail "softwareupdate parsing"; echo "$o"; }
SU_FAIL=1 sys --only check.macos_updates >"$W/sufail.out"
grep -q 'could not check' "$W/sufail.out" && ! grep -q 'up to date' "$W/sufail.out" && pass "macOS updates: a failed softwareupdate is not reported as up to date" || { fail "softwareupdate failure"; cat "$W/sufail.out"; }
BB="$W/brewbin"; mkdir -p "$BB"
cat >"$BB/brew" <<'FAKE'
#!/bin/bash
echo "brew $* NO_AUTO_UPDATE=${HOMEBREW_NO_AUTO_UPDATE:-}" >>"$BREWLOG"
[ "$1" = --repository ] && echo "$BREWREPO"
[ "$1" = --cache ] && echo "$BREWREPO/cache"
exit 0
FAKE
chmod +x "$BB/brew"; mkdir -p "$W/brewrepo/.git"; : >"$W/brewrepo/.git/FETCH_HEAD"; touch -t 202001010000 "$W/brewrepo/.git/FETCH_HEAD"
sed 's|^export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:|export PATH="|' "$M" >"$W/macup-nobrew"   # macup puts the real Homebrew first in PATH
env HOME="$H" PATH="$BB:$SB:$PATH" BREWLOG="$W/brew.log" BREWREPO="$W/brewrepo" /bin/bash "$W/macup-nobrew" check --only update.brew --no-color </dev/null >"$W/brewchk.out" 2>&1
grep -q 'brew outdated' "$W/brew.log" && ! grep -q '^brew update' "$W/brew.log" && ! grep 'brew outdated' "$W/brew.log" | grep -qv 'NO_AUTO_UPDATE=1$' \
  && grep -q 'package list is from 2020-01-01' "$W/brewchk.out" && pass "check never runs brew update, calls brew with HOMEBREW_NO_AUTO_UPDATE=1 and says how old the list is" || { fail "check leaves Homebrew alone"; cat "$W/brew.log" "$W/brewchk.out"; }
sys --only check.battery | grep -q 'Battery: 83% charged, 612 cycles, 76% capacity, Normal — capacity under 80%' && pass "battery: cycles and capacity read from system_profiler" || { fail "battery parsing"; sys --only check.battery; }
sys --only check.memory | grep -q '! Memory: .* 9% free, .* memory is tight' && pass "memory: free percentage read from memory_pressure" || { fail "memory parsing"; sys --only check.memory; }

# --- the schedule is optional: nothing until asked, a LaunchAgent that only runs a check, off removes it
H="$W/sch"; mkdir -p "$H/.local/bin" "$H/.config/macup"; printf 'language = en\n' >"$H/.config/macup/config"; cp macup "$H/.local/bin/macup"
SP="$H/Library/LaunchAgents/com.vitaliideveloper.macup.plist"; sch(){ env HOME="$H" /bin/bash "$H/.local/bin/macup" schedule "$@" --no-color </dev/null 2>&1; }
sch | grep -q 'No schedule' && [ ! -e "$SP" ] && pass "schedule: none by default" || fail "schedule: default"
sch weekly | grep -q 'every Monday at 10:00' && grep -q '<key>Weekday</key><integer>1</integer>' "$SP" && grep -qF "<string>$H/.local/bin/macup</string><string>check</string><string>--quiet</string><string>--notify</string>" "$SP" \
  && grep -q "^bootstrap gui/.* $SP" "$H/launchctl.log" && grep -q "<key>PATH</key><string>.*$W/bin" "$SP" && sch | grep -q 'every Monday' && pass "schedule weekly: a LaunchAgent that runs macup check" || { fail "schedule weekly"; cat "$SP" "$H/launchctl.log"; }
{ ! command -v plutil >/dev/null || plutil -lint "$SP" >/dev/null; } && pass "schedule: the plist is valid" || fail "schedule: plist"
sch daily | grep -q 'every day at 10:00' && ! grep -q Weekday "$SP" && pass "schedule daily" || fail "schedule daily"
sch off | grep -q 'Schedule removed' && [ ! -e "$SP" ] && grep -q "^bootout gui/.*/com.vitaliideveloper.macup" "$H/launchctl.log" && pass "schedule off removes it" || fail "schedule off"
sch hourly >/dev/null; [ $? = 2 ] && [ ! -e "$SP" ] && pass "schedule: unknown word" || fail "schedule: unknown word"
# --notify: a notification only when something needs a look
env HOME="$H" /bin/bash "$M" check --only check.sizes --quiet --notify </dev/null >/dev/null 2>&1
[ ! -e "$H/osascript.log" ] && pass "--notify: silent when all is well" || { fail "--notify without a reason"; cat "$H/osascript.log"; }
mkdir -p "$H/Library/Developer/Xcode"; ln -s "$H/gone" "$H/.local/bin/deadlink"
env HOME="$H" /bin/bash "$M" check --only check.commands --quiet --notify </dev/null >/dev/null 2>&1
grep -q 'display notification "Needs attention: [0-9]' "$H/osascript.log" 2>/dev/null && pass "--notify: says what needs attention" || { fail "--notify"; cat "$H/osascript.log" 2>/dev/null; }

# --- self-update: the file comes from the version's tag and must match its published SHA-256; a fake curl serves $FAKE_REMOTE
mkdir -p "$W/cbin"; cat >"$W/cbin/curl" <<'FAKE'
#!/bin/bash
out=""; url=""
while [ $# -gt 0 ]; do case "$1" in -o) out=$2; shift ;; --max-time|-z) shift ;; http*) url=$1 ;; esac; shift; done
f="$FAKE_REMOTE/$(printf '%s' "$url" | sed -E 's|https://raw.githubusercontent.com/[^/]+/[^/]+/||')"
[ -f "$f" ] || exit 22
if [ -n "$out" ]; then cp "$f" "$out"; else cat "$f"; fi
FAKE
chmod +x "$W/cbin/curl"
sum(){ if command -v shasum >/dev/null; then shasum -a 256 "$1"; else sha256sum "$1"; fi | awk '{print $1}'; }
H="$W/su"; R="$W/remote"; mkdir -p "$H/.local/bin" "$H/.config/macup" "$R/main" "$R/v9.9.9"; printf 'language = en\n' >"$H/.config/macup/config"
sed 's/^MACUP_VERSION=.*/MACUP_VERSION="9.9.9"/' macup >"$R/main/macup"; { cat "$R/main/macup"; echo '# work in progress on main'; } >"$R/main/macup.wip"; mv "$R/main/macup.wip" "$R/main/macup"
sed 's/^MACUP_VERSION=.*/MACUP_VERSION="9.9.9"/' macup >"$R/v9.9.9/macup"
echo "$(sum "$R/main/macup")  macup" >"$R/main/macup.sha256"; echo "$(sum "$R/v9.9.9/macup")  macup" >"$R/v9.9.9/macup.sha256"
old(){ sed 's/^MACUP_VERSION=.*/MACUP_VERSION="0.0.1"/' macup >"$H/.local/bin/macup"; }
su(){ env HOME="$H" PATH="$W/cbin:$PATH" FAKE_REMOTE="$R" /bin/bash "$H/.local/bin/macup" self-update --no-color </dev/null 2>&1; }
old; su | grep -q 'macup updated: 0.0.1 → 9.9.9' && cmp -s "$H/.local/bin/macup" "$R/v9.9.9/macup" && pass "self-update installs the tagged release, not main" || { fail "self-update from the tag"; su; }
old; echo "0000  macup" >"$R/v9.9.9/macup.sha256"
su | grep -q 'does not match its published checksum' && grep -q '^MACUP_VERSION="0.0.1"' "$H/.local/bin/macup" && pass "self-update refuses a file that does not match its checksum" || { fail "self-update checksum"; su; }
rm -rf "$R/v9.9.9"; old
su | grep -q 'macup updated: 0.0.1 → 9.9.9' && cmp -s "$H/.local/bin/macup" "$R/main/macup" && pass "self-update falls back to main before a version is tagged" || { fail "self-update fallback"; su; }

# --- creating the config file runs nothing: its template used to run `macup clean` and `macup all` (backticks in a heredoc)
H="$W/cf"; mkdir -p "$H" "$W/mbin"; printf '#!/bin/bash\necho "$*" >>"$HOME/ran.log"\n' >"$W/mbin/macup"; chmod +x "$W/mbin/macup"
env HOME="$H" PATH="$W/mbin:$PATH" /bin/bash "$M" config </dev/null >/dev/null 2>&1
[ ! -e "$H/ran.log" ] && grep -qF '# What `macup clean` / `macup all` may remove' "$H/.config/macup/config" && [ "$(wc -l <"$H/.config/macup/config")" -lt 45 ] \
  && pass "creating the config file runs no command" || { fail "creating the config ran: $(cat "$H/ran.log" 2>/dev/null | tr '\n' ' ')"; }
rm -rf "$H"; env HOME="$H" PATH="$W/mbin:$PATH" /bin/bash "$M" lang uk </dev/null >/dev/null 2>&1
[ ! -e "$H/ran.log" ] && grep -q '^language = uk' "$H/.config/macup/config" && pass "macup lang on a fresh home runs no command" || fail "macup lang ran: $(cat "$H/ran.log" 2>/dev/null | tr '\n' ' ')"

# --- installer
I="$W/i"; mkdir -p "$I/.npm-global/bin"; printf '#!/bin/bash\n# macup — old\nMACUP_VERSION="1.1"\n' >"$I/.npm-global/bin/macup"; printf '#!/bin/bash\n# macup notes\n' >"$I/.npm-global/bin/other"
# no test may hang the suite: after the limit it says what was running and stops the command
lim(){ local s=$1 p w rc; shift; "$@" & p=$!
  ( sleep "$s"; echo "TIMEOUT after ${s}s: $*"; ps -axo pid,ppid,etime,command | grep -v 'ps -axo' | tail -25; kill $p 2>/dev/null ) & w=$!
  wait $p; rc=$?; kill $w 2>/dev/null; wait $w 2>/dev/null; return $rc; }
lim 120 env HOME="$I" MACUP_PREFIX="$W/bin" /bin/bash ./install.sh --yes --lang uk --projects "~/Code, ~/Work" </dev/null >"$W/in" 2>&1; rc=$?
[ $rc = 0 ] && [ ! -e "$I/.npm-global/bin/macup" ] && [ -e "$I/.npm-global/bin/other" ] && [ -x "$W/bin/macup" ] && grep -q '^project_dirs = ~/Code, ~/Work' "$I/.config/macup/config" \
  && pass "install replaces an old copy, keeps unrelated files" || { fail "install (rc=$rc)"; cat "$W/in"; }
lim 120 env HOME="$I" MACUP_PREFIX="$W/bin" /bin/bash ./install.sh --yes </dev/null >/dev/null 2>&1
grep -q '^project_dirs = ~/Code, ~/Work' "$I/.config/macup/config" && grep -q '^language = uk' "$I/.config/macup/config" && [ "$(grep -c '# macup' "$I/.zshrc")" = 1 ] \
  && pass "reinstall keeps settings" || fail "reinstall"
/bin/bash ./install.sh --bogus >/dev/null 2>&1; [ $? = 2 ] && pass "installer rejects unknown options" || fail "installer options"

# --- a mistyped task id is said, not silently matched to nothing; no HOME, no run
H="$W/ids"; mkdir -p "$H/.config/macup"; printf 'language = en\nskip = check.tyme_machine\nenable = clean.trash\n' >"$H/.config/macup/config"
env HOME="$H" /bin/bash "$M" check --only chek.disk --no-color </dev/null >"$W/ids.out" 2>&1; rc=$?
[ $rc = 2 ] && grep -q 'Unknown task: chek.disk' "$W/ids.out" && [ ! -d "$H/Library/Logs/macup" ] && pass "unknown id in --only stops the run" || fail "unknown id in --only (rc=$rc)"
env HOME="$H" /bin/bash "$M" check --skip 'update.*,check.docker,clean.nope' --no-color </dev/null >/dev/null 2>&1; [ $? = 2 ] && pass "unknown id in --skip stops the run" || fail "unknown id in --skip"
env HOME="$H" /bin/bash "$M" check --only 'check.system,clean.*' --no-color </dev/null >"$W/ids.out" 2>&1; rc=$?
[ $rc = 0 ] && grep -q 'Unknown task in ~/.config/macup/config: check.tyme_machine' "$W/ids.out" && ! grep -q 'clean.trash (' "$W/ids.out" && pass "unknown id in the config is a warning" || { fail "unknown id in the config (rc=$rc)"; cat "$W/ids.out"; }
env HOME= /bin/bash "$M" version >/dev/null 2>&1; [ $? = 1 ] && pass "no HOME: macup does not start" || fail "empty HOME"

# ============================ 2.9
jq(){ python3 -c "import json,sys; d=json.load(open(sys.argv[1])); $2" "$1"; }   # file, python that reads d

# --- macup tidies its own files on every run, a check too: old reports, too many reports, history, the schedule's log, temp files of killed runs
H="$W/tidy"; LG="$H/Library/Logs/macup"; ST="$H/Library/Application Support/macup"; TT="$W/tidytmp"; mkdir -p "$LG" "$ST" "$TT" "$H/.config/macup"; printf 'language = en\n' >"$H/.config/macup/config"
for i in $(seq 10 79); do : >"$LG/macup_2026-01-01_00-00-$i.md"; echo x >"$LG/macup_2026-01-01_00-00-$i.log"; done
: >"$LG/macup_2024-01-01_00-00-00.md"; : >"$LG/macup_2024-01-01_00-00-00.log"; : >"$LG/macup_2024-06-01_00-00-00.log"; touch -t 202401010000 "$LG"/macup_2024-*
seq 1 1500 | sed 's/^/2026-01-01 00:00,check,1,2,3,4,5,6,7,8,/' >"$ST/history.csv"; seq 1 900 >"$LG/schedule.log"
: >"$TT/macup.AbCdEf"; : >"$TT/macup.AbCdEf.pid"; : >"$TT/macup-lang.GhIjKl"; touch -t 202401010000 "$TT"/macup*; : >"$TT/macup.FrEsH1"; : >"$TT/macup-notes.txt"; touch -t 202401010000 "$TT/macup-notes.txt"
env HOME="$H" TMPDIR="$TT" /bin/bash "$M" check --only check.system --no-color </dev/null >"$W/tidy.out" 2>&1
n=$(ls "$LG"/macup_*.md | wc -l | tr -d ' ')
[ "$n" = 20 ] && [ ! -e "$LG/macup_2024-01-01_00-00-00.md" ] && [ ! -e "$LG/macup_2024-01-01_00-00-00.log" ] && [ ! -e "$LG/macup_2024-06-01_00-00-00.log" ] && [ -e "$LG/macup_2026-01-01_00-00-79.md" ] \
  && pass "own reports: old ones and old orphan logs go, the newest 20 runs stay ($n)" || fail "own reports ($n left)"
lo=0; for f in "$LG"/macup_*.log; do [ -e "${f%.log}.md" ] || lo=1; done
[ $lo = 0 ] && [ "$(ls "$LG"/macup_*.log | wc -l | tr -d ' ')" = 19 ] && pass "own reports: a removed report takes the log of an older version along" || { fail "logs of removed reports stay"; ls "$LG"; }
[ "$(wc -l <"$ST/history.csv" | tr -d ' ')" -le 501 ] && [ "$(wc -l <"$LG/schedule.log" | tr -d ' ')" = 200 ] && tail -1 "$LG/schedule.log" | grep -q '^900$' && pass "history and the schedule's log keep only their last lines" || fail "history or schedule.log not trimmed"
[ ! -e "$TT/macup.AbCdEf" ] && [ ! -e "$TT/macup.AbCdEf.pid" ] && [ ! -e "$TT/macup-lang.GhIjKl" ] && [ -e "$TT/macup.FrEsH1" ] && [ -e "$TT/macup-notes.txt" ] \
  && [ -z "$(find "$TT" -maxdepth 1 -name 'macup*' ! -name '*FrEsH1' ! -name '*notes*')" ] && pass "temp files of killed runs go after a day; nothing else in the temp folder is touched, none are left" || { fail "temp files"; ls -la "$TT"; }
new=$(ls -t "$LG"/macup_*.md | head -1); [ ! -e "${new%.md}.log" ] && ! grep -q '^## Command output' "$new" && pass "a run that started no command: one report, no command output section" || fail "a run without commands left a log or an empty section"
printf 'language = en\nkeep_reports_days = 30\nkeep_reports = 5\n' >"$H/.config/macup/config"
env HOME="$H" TMPDIR="$TT" /bin/bash "$M" check --only check.system --no-color </dev/null >"$W/tidy.out" 2>&1
[ "$(ls "$LG"/macup_*.md | wc -l | tr -d ' ')" = 5 ] && [ -e "$new" ] && pass "keep_reports caps the runs kept" || { fail "keep_reports"; ls "$LG"; }

# --- macup reports: what there is, clean asks first, --json
H="$W/rep"; LG="$H/Library/Logs/macup"; mkdir -p "$LG" "$H/.config/macup"; printf 'language = en\n' >"$H/.config/macup/config"
printf '# macup report — 2026-11-01 10:00\n\nMode: check · macup 2.8.0 · took 0m 5s\n' >"$LG/macup_2026-11-01_10-00-00.md"; echo raw >"$LG/macup_2026-11-01_10-00-00.log"
printf '# звіт macup — 2026-11-02 11:30\n\nРежим: all+deep · macup 2.9.0 · тривалість 1m 2s\n' >"$LG/macup_2026-11-02_11-30-00.md"; echo keep >"$LG/schedule.log"
env HOME="$H" /bin/bash "$M" reports --no-color </dev/null >"$W/rep.out" 2>&1
grep -q '^Reports: 2 · .* · ~/Library/Logs/macup$' "$W/rep.out" && grep -q '^Oldest: 2026-11-01 10:00 · newest: 2026-11-02 11:30$' "$W/rep.out" && grep -q 'macup reports clean' "$W/rep.out" \
  && pass "reports: count, size, folder, dates, how to clean" || { fail "reports"; cat "$W/rep.out"; }
env HOME="$H" /bin/bash "$M" reports --json </dev/null >"$W/rep.json" 2>/dev/null
python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); r=d["reports"]; assert d["schema"]==1 and d["count"]==2 and d["kb"]>0 and d["folder"].endswith("Logs/macup"); assert [x["mode"] for x in r]==["check","all+deep"] and r[0]["date"]=="2026-11-01 10:00" and r[0]["file"].endswith(".md") and r[0]["kb"]>0' "$W/rep.json" \
  && pass "reports --json: valid, with file, date, mode and size" || { fail "reports --json"; cat "$W/rep.json"; }
env HOME="$H" /bin/bash "$M" reports clean --no-color </dev/null >"$W/rep.out" 2>&1
[ "$(ls "$LG" | wc -l | tr -d ' ')" = 4 ] && grep -q 'Reports to remove: 2 ' "$W/rep.out" && grep -q 'Nothing removed' "$W/rep.out" && ! grep -q tty "$W/rep.out" \
  && pass "reports clean without a yes removes nothing" || { fail "reports clean: no answer"; cat "$W/rep.out"; }
env HOME="$H" /bin/bash "$M" reports clean --yes --no-color </dev/null >"$W/rep.out" 2>&1
[ "$(ls "$LG")" = schedule.log ] && grep -q 'Removed' "$W/rep.out" && pass "reports clean --yes removes the reports and old logs, keeps schedule.log" || { fail "reports clean --yes"; ls "$LG"; cat "$W/rep.out"; }
env HOME="$H" /bin/bash "$M" reports nonsense </dev/null >/dev/null 2>&1; [ $? = 2 ] && pass "reports: an unknown word is exit status 2" || fail "reports nonsense"

# --- Ctrl-C: what the commands printed so far is in the report, and the report is named
H="$W/int"; mkdir -p "$H/.local/bin" "$H/.config/macup"; printf 'language = en\n' >"$H/.config/macup/config"
printf '#!/bin/bash\ncase "$1" in --version) echo 1.0 ;; update) echo "agy is downloading"; : >"$HOME/started"; sleep 30 ;; esac\n' >"$H/.local/bin/agy"; chmod +x "$H/.local/bin/agy"
set -m   # its own process group, and SIGINT not ignored as it is for a background job without job control
env HOME="$H" /bin/bash "$M" update --only update.agy --no-color </dev/null >"$W/int.out" 2>&1 & p=$!
set +m
for i in $(seq 1 100); do [ -e "$H/started" ] && break; sleep 0.2; done
kill -INT -- -"$p" 2>/dev/null; wait "$p"; rc=$?
r=$(ls "$H"/Library/Logs/macup/macup_*.md 2>/dev/null | head -1)
[ $rc = 130 ] && [ -n "$r" ] && grep -q 'Interrupted. Report: ~/Library/Logs/macup/macup_' "$W/int.out" && grep -q 'agy is downloading' "$r" && grep -q 'incomplete' "$r" && [ -z "$(ls "$H"/Library/Logs/macup/*.log 2>/dev/null)" ] \
  && pass "Ctrl-C: the report keeps what the commands printed" || { fail "Ctrl-C (rc=$rc)"; cat "$W/int.out" "$r"; }

# --- since the last run: swap that grew is not "something is filling the disk"
H="$W/swp"; SW="$W/swpbin"; mkdir -p "$SW" "$H/.config/macup" "$H/Library/Application Support/macup"; printf 'language = en\n' >"$H/.config/macup/config"
printf '#!/bin/bash\ncase "$*" in *vm.swapusage*) echo "total = 12288.00M  used = ${FAKE_SWAP_MB}.00M  free = 100.00M  (encrypted)" ;; *) exec /usr/sbin/sysctl "$@" ;; esac\n' >"$SW/sysctl"; chmod +x "$SW/sysctl"
swp(){ # free KB more last time, swap MB last time, swap MB now
  local fr; fr=$(df -k /System/Volumes/Data 2>/dev/null | awk 'NR==2{print $4}')
  echo "2026-11-01 10:00,check,$((fr + $1)),500000000,50,$2,,,0,0,0" >"$H/Library/Application Support/macup/history.csv"
  FAKE_SWAP_MB=$3 env HOME="$H" PATH="$SW:$PATH" /bin/bash "$M" check --only check.trends,check.memory --no-color </dev/null 2>&1 | grep 'Free space' | head -1; }
o=$(swp 26214400 0 10240)   # 26.8 GB less, 10.7 GB of it swap: 16 GB is under the 21 GB that warns
echo "$o" | grep -q '· Free space: -2[67]\.[0-9] GB since 2026-11-01 10:00 (10.7 GB of it is swap, freed on restart)$' && pass "free space: swap is subtracted before warning" || fail "free space with swap: $o"
o=$(swp 31457280 0 2048)
echo "$o" | grep -q '! Free space: -3[23]\.[0-9] GB .*(2.1 GB of it is swap, freed on restart) — something is filling the disk' && pass "free space: still a warning when the rest crosses the line" || fail "free space, swap too small: $o"
o=$(swp 31457280 7000 7000)
echo "$o" | grep -q '! Free space: -3[23]\.[0-9] GB since 2026-11-01 10:00 — something is filling' && pass "free space: unchanged swap, the warning as before" || fail "free space without swap: $o"

# --- --json carries everything the terminal shows, with a key for each thing that can be cleaned; --pick cleans exactly those
H="$W/js"; tests/fixture.sh "$H"; (cd "$H" && find . -type f | sort) >"$H.b"
env HOME="$H" /bin/bash "$M" check --json --skip "$X" </dev/null >"$W/js.json" 2>/dev/null
jq "$W/js.json" 'c=d["cleanable"]; assert d["schema"]==1 and len(c)>20 and all(k in c[0] for k in ("key","task","level","kb","opt_in","in_clean","text")); assert len({x["key"] for x in c})==len(c); t=[x for x in c if x["task"]=="clean.trash"][0]; assert t["opt_in"] and not t["in_clean"] and t["level"]=="aggressive"; s=[x for x in c if x["task"]=="clean.spm"][0]; assert s["in_clean"] and s["kb"]>5000' \
  && pass "--json: cleanable items with unique keys, level and size" || { fail "--json cleanable"; head -c 600 "$W/js.json"; }
mkdir -p "$H/Library/LaunchAgents"; : >"$H/Library/LaunchAgents/com.example.agent.plist"   # its name is a line under "Third-party background services"
env HOME="$H" /bin/bash "$M" check --json --only check.sizes,check.system,check.startup </dev/null >"$W/js2.json" 2>/dev/null
jq "$W/js2.json" 'i=d["items"]; assert i and all(x["kind"] in ("ok","info","warn","fail") and x["section"] and isinstance(x["details"],list) for x in i); assert any("Trash" in x["text"] for x in i); assert any(x["details"] for x in i)' \
  && pass "--json: every line of the run with its section and kind" || { fail "--json items"; head -c 600 "$W/js2.json"; }
k3=$(jq "$W/js.json" 'print([x["key"] for x in d["cleanable"] if x["task"]=="clean.derived_data"][0])')
k1=$(jq "$W/js.json" 'print([x["key"] for x in d["cleanable"] if x["task"]=="clean.spm"][0])'); k2=$(jq "$W/js.json" 'print([x["key"] for x in d["cleanable"] if x["task"]=="clean.trash"][0])')
env HOME="$H" /bin/bash "$M" check --json --skip "$X" </dev/null 2>/dev/null >"$W/js3.json"; [ "$(jq "$W/js3.json" 'print(sorted(x["key"] for x in d["cleanable"]))')" = "$(jq "$W/js.json" 'print(sorted(x["key"] for x in d["cleanable"]))')" ] \
  && pass "--json: the keys are the same on the next run" || fail "--json keys change between runs"
env HOME="$H" /bin/bash "$M" clean --pick "$k1,$k2" --json --skip "$X" </dev/null >"$W/js4.json" 2>/dev/null; rc=$?
got=$( (cd "$H" && find . -type f | sort) | comm -23 "$H.b" - | grep -v 'macup/')
[ $rc = 0 ] && [ "$got" = "$(printf '%s\n' ./.Trash/thing/blob ./Library/Caches/org.swift.swiftpm/repos/blob)" ] && jq "$W/js4.json" 'assert d["mode"]=="clean" and d["freed_kb"]>10000 and d["cleanable"]==[]' \
  && pass "--pick cleans exactly the chosen items, an opt-in one too, and nothing else" || { fail "--pick (rc=$rc)"; echo "$got"; }
env HOME="$H" /bin/bash "$M" clean --pick "$k3,clean.nope:1" --no-color --skip "$X" </dev/null >"$W/js.out" 2>&1; rc=$?
[ $rc = 3 ] && grep -q 'no longer there: clean.nope:1 ' "$W/js.out" && [ ! -e "$H/Library/Developer/Xcode/DerivedData/App-abc" ] && pass "--pick: a key that is gone is said, exit status 3" || { fail "--pick with a stale key (rc=$rc)"; cat "$W/js.out"; }
env HOME="$H" /bin/bash "$M" tasks --json >"$W/js5.json" 2>/dev/null; env HOME="$H" /bin/bash "$M" history --json >"$W/js6.json" 2>/dev/null
jq "$W/js5.json" 't={x["id"]:x for x in d["tasks"]}; assert t["clean.trash"]["on"] is False and t["check.disk"]["on"] and t["clean.spm"]["group"]=="clean" and d["config"].endswith("/config")' \
  && jq "$W/js6.json" 'r=d["runs"]; assert len(r)>=3 and r[-1]["mode"]=="clean" and isinstance(r[-1]["free_kb"],int) and r[-1]["battery_cycles"] is None' \
  && pass "tasks --json and history --json" || { fail "tasks/history --json"; head -c 300 "$W/js5.json" "$W/js6.json"; }

# --- --enable turns an opt-in task on for one run
H="$W/en"; tests/fixture.sh "$H"
env HOME="$H" /bin/bash "$M" clean --level aggressive --only clean.trash --no-color </dev/null >/dev/null 2>&1; [ -f "$H/.Trash/thing/blob" ] && pass "an opt-in task stays off without --enable" || fail "opt-in task ran without --enable"
env HOME="$H" /bin/bash "$M" clean --level aggressive --only clean.trash --enable clean.trash --no-color </dev/null >/dev/null 2>&1; [ ! -e "$H/.Trash/thing" ] && pass "--enable turns it on for this run" || fail "--enable"

# --- stale build folders (opt-in): only next to their build file, never tracked by git, never built recently
H="$W/art"; tests/fixture.sh "$H"; C="$H/Code"
blob(){ mkdir -p "$1"; dd if=/dev/zero of="$1/blob" bs=1024 count=6144 2>/dev/null; }; old(){ find "$@" -exec touch -t 202401010000 {} +; }
blob "$C/oldrs/target/debug"; echo '[package]' >"$C/oldrs/Cargo.toml"; mkdir -p "$C/oldrs/src"; echo 'fn main(){}' >"$C/oldrs/src/main.rs"
blob "$C/oldplain/target/data"; echo notes >"$C/oldplain/readme"                      # no Cargo.toml: someone's data
blob "$C/oldpods/Pods/Lib"; echo "pod 'Lib'" >"$C/oldpods/Podfile"                      # committed Pods
blob "$C/oldswift/.build/debug"; echo '// swift' >"$C/oldswift/Package.swift"
blob "$C/built/target/debug"; echo '[package]' >"$C/built/Cargo.toml"                  # old sources, built yesterday
blob "$C/oldvenv/.venv/lib"; echo x >"$C/oldvenv/requirements.txt"                     # a venv may hold packages no file lists
blob "$C/.hidden/proj/target/debug"; echo '[package]' >"$C/.hidden/proj/Cargo.toml"
if command -v git >/dev/null; then (cd "$C/oldpods" && git init -q . && git add -A && git -c user.name=t -c user.email=t@t commit -qm x) >/dev/null 2>&1; fi
for d in oldrs oldplain oldpods oldswift oldvenv .hidden; do old "$C/$d"; done; old "$C/built/Cargo.toml"
(cd "$H" && find . -type f | sort) >"$H.b"
env HOME="$H" /bin/bash "$M" check --only clean.stale_artifacts --no-color </dev/null >"$W/art.out" 2>&1
grep -q 'Stale build folders (2, .*(only if you pick it)' "$W/art.out" && [ -d "$C/oldrs/target" ] && pass "stale build folders: listed by a check, only when picked" || { fail "stale build folders: check"; cat "$W/art.out"; }
env HOME="$H" /bin/bash "$M" clean --level standard --only clean.stale_artifacts --enable clean.stale_artifacts --no-color </dev/null >"$W/art.out" 2>&1
got=$( (cd "$H" && find . -type f | sort) | comm -23 "$H.b" - | grep -v 'macup/')
[ "$got" = "$(printf '%s\n' ./Code/oldrs/target/debug/blob ./Code/oldswift/.build/debug/blob)" ] && pass "stale build folders: only the stale ones with a build file; git-tracked, recent, hidden and .venv stay" || { fail "stale build folders"; echo "$got"; cat "$W/art.out"; }

# --- caches are left alone while the tool that uses them runs: cargo, and anything started with npx (MCP servers)
H="$W/busy"; tests/fixture.sh "$H"
FAKE_RUNNING='/Users/me/.cargo/bin/cargo build --release' env HOME="$H" /bin/bash "$M" clean --level standard --only clean.cargo --no-color </dev/null >"$W/busy.out" 2>&1
[ -f "$H/.cargo/registry/src/index.crates.io/blob" ] && [ -f "$H/.cargo/git/db/repo-1/blob" ] && grep -q 'Cargo registry sources.*skipped' "$W/busy.out" && pass "Cargo's downloads are skipped while cargo runs" || { fail "cargo cleaned while it runs"; cat "$W/busy.out"; }
FAKE_RUNNING="node $H/.npm/_npx/abc/node_modules/.bin/some-mcp-server" env HOME="$H" /bin/bash "$M" clean --level standard --only clean.npm --no-color </dev/null >"$W/busy.out" 2>&1
[ -f "$H/.npm/_npx/abc/node_modules/x/blob" ] && grep -q 'npx cache.*skipped' "$W/busy.out" && pass "the npx cache is skipped while something started with npx runs" || { fail "npx cache cleaned under a running server"; cat "$W/busy.out"; }
env HOME="$H" /bin/bash "$M" clean --only clean.npm --no-color </dev/null >"$W/busy.out" 2>&1; [ -d "$H/.npm/_npx/abc" ] && pass "the npx cache stays at the safe level" || fail "npx cache cleaned at safe"
env HOME="$H" /bin/bash "$M" clean --level standard --only clean.npm --no-color </dev/null >"$W/busy.out" 2>&1
[ ! -e "$H/.npm/_npx/abc" ] && pass "the npx cache is cleaned when nothing uses it" || { fail "npx cache"; cat "$W/busy.out"; }

# --- Docker: the build cache at standard; images and stopped containers only when picked; volumes never. A fake docker records what is asked
H="$W/dk"; mkdir -p "$H/.local/bin" "$H/.config/macup"; printf 'language = en\n' >"$H/.config/macup/config"
# an exported function, like mas above: a real docker in /usr/local/bin would win over a fake file
docker(){ case "$*" in
  info) ;;
  "system df --format {{.Type}}|{{.Reclaimable}}") printf 'Images|2.5GB (50%%)\nContainers|12MB (100%%)\nLocal Volumes|3GB (100%%)\nBuild Cache|1.5GB\n' ;;
  system\ df*) printf 'Images 5GB, 2.5GB (50%%) reclaimable\nBuild Cache 1.5GB, 1.5GB reclaimable\n' ;;
  ps\ -aq*) printf 'aaa\nbbb\n' ;;
  volume\ ls*) echo vol1 ;;
  *) echo "$*" >>"$HOME/docker.log"; echo "Total reclaimed space: 1.5GB" ;;
esac; }
export -f docker
DK='clean.docker,clean.docker_images,clean.docker_containers,check.docker'
env HOME="$H" /bin/bash "$M" check --only "$DK" --no-color </dev/null >"$W/dk.out" 2>&1
grep -q 'standard .*1.5 GB  Docker build cache' "$W/dk.out" && grep -q '2.5 GB  Docker images no container uses.*(only if you pick it)' "$W/dk.out" && grep -q 'aggressive .*Stopped Docker containers (2).*(only if you pick it)' "$W/dk.out" \
  && grep -q 'Docker volumes no container uses: 1 — macup never deletes volumes' "$W/dk.out" && [ ! -e "$H/docker.log" ] && pass "Docker: a check lists the cache, the images, the stopped containers and unused volumes; nothing is removed" || { fail "Docker check"; cat "$W/dk.out" "$H/docker.log" 2>/dev/null; }
env HOME="$H" /bin/bash "$M" clean --level aggressive --only "$DK" --no-color </dev/null >"$W/dk.out" 2>&1
[ "$(cat "$H/docker.log")" = "$(printf 'builder prune -f\nimage prune -f')" ] && pass "Docker: clean takes the build cache and dangling images only, even at --level aggressive" || { fail "Docker clean"; cat "$H/docker.log"; }
rm -f "$H/docker.log"; env HOME="$H" /bin/bash "$M" clean --level aggressive --only "$DK" --enable clean.docker_images,clean.docker_containers --no-color </dev/null >"$W/dk.out" 2>&1
grep -qx 'image prune -a -f' "$H/docker.log" && grep -qx 'container prune -f' "$H/docker.log" && ! grep -q volume "$H/docker.log" && grep -q 'Docker images no container uses.*freed 1.5 GB' "$W/dk.out" \
  && pass "Docker: images and stopped containers when enabled; volumes never" || { fail "Docker opt-in"; cat "$H/docker.log" "$W/dk.out"; }
unset -f docker
# the same, with a docker program in PATH, as it prints it: sizes and answers come from FAKE_DK_* so a run can be empty, failing or stuck
H="$W/dk2"; mkdir -p "$H/.local/bin" "$H/.config/macup"; printf 'language = en\n' >"$H/.config/macup/config"
cat >"$H/.local/bin/docker" <<'FAKE'
#!/bin/bash
echo "$*" >>"$HOME/docker.log"
case "$*" in
  info) [ -n "$FAKE_DK_HANG" ] && sleep 300; [ -n "$FAKE_DK_DOWN" ] && { echo "Cannot connect to the Docker daemon" >&2; exit 1; }; echo "Server Version: 27.0" ;;
  "system df --format {{.Type}}|{{.Reclaimable}}") printf 'Images|%s\nContainers|%s\nLocal Volumes|3.2GB (100%%)\nBuild Cache|%s\n' "${FAKE_DK_IMG:-1.2GB (50%)}" "${FAKE_DK_CT:-12.3MB (100%)}" "${FAKE_DK_BC:-1.5GB}" ;;
  "system df --format {{.Type}} {{.Size}}, {{.Reclaimable}} reclaimable") printf 'Images 2.4GB, %s reclaimable\nContainers 12.3MB, %s reclaimable\nLocal Volumes 3.2GB, 3.2GB (100%%) reclaimable\nBuild Cache 1.5GB, %s reclaimable\n' "${FAKE_DK_IMG:-1.2GB (50%)}" "${FAKE_DK_CT:-12.3MB (100%)}" "${FAKE_DK_BC:-1.5GB}" ;;
  ps\ -aq*) printf '%s' "${FAKE_DK_PS-aaa111$'\n'bbb222$'\n'}" ;;
  volume\ ls*) printf '%s' "${FAKE_DK_VOLS-vol1$'\n'vol2$'\n'}" ;;
  "builder prune -f") [ -n "$FAKE_DK_PRUNE_FAIL" ] && { echo "Error response from daemon" >&2; exit 1; }; printf 'Deleted build cache objects:\nabc\n\nTotal reclaimed space: 1.2GB\n' ;;
  "image prune -f") printf 'Total reclaimed space: 300MB\n' ;;
  "image prune -a -f") printf 'Deleted Images:\nuntagged: foo:1\n\nTotal reclaimed space: 1.2GB\n' ;;
  "container prune -f") printf 'Deleted Containers:\naaa111\nbbb222\n\nTotal reclaimed space: 12.3MB\n' ;;
  *) echo "unexpected: $*" >&2; exit 64 ;;
esac
FAKE
chmod +x "$H/.local/bin/docker"
dk(){ rm -f "$H/docker.log"; env HOME="$H" /bin/bash "$M" "$@" --only "$DK" --no-color </dev/null >"$W/dk.out" 2>&1; }
dk check
grep -q 'Docker: Images 2.4GB, 1.2GB (50%) reclaimable; Containers 12.3MB, 12.3MB (100%) reclaimable; Local Volumes 3.2GB, 3.2GB (100%) reclaimable; Build Cache 1.5GB, 1.5GB reclaimable' "$W/dk.out" \
  && grep -q 'Docker volumes no container uses: 2 ' "$W/dk.out" && ! grep -q prune "$H/docker.log" && pass "Docker (real program): the check shows the usage and the unused volumes, and runs no prune" || { fail "Docker check, docker in PATH"; cat "$W/dk.out" "$H/docker.log"; }
env HOME="$H" /bin/bash "$M" check --json --only "$DK" </dev/null >"$W/dk.json" 2>/dev/null
jq "$W/dk.json" 'c={x["task"]:x for x in d["cleanable"]}; assert set(c)=={"clean.docker","clean.docker_images","clean.docker_containers"}; assert 1400000<c["clean.docker"]["kb"]<1500000, c; assert 1100000<c["clean.docker_images"]["kb"]<1200000; assert 10000<c["clean.docker_containers"]["kb"]<14000; assert not c["clean.docker"]["opt_in"] and c["clean.docker_images"]["opt_in"] and c["clean.docker_containers"]["opt_in"] and not any(x["in_clean"] for x in c.values()) and [c[t]["level"] for t in ("clean.docker","clean.docker_images","clean.docker_containers")]==["standard","standard","aggressive"]; assert len({x["key"] for x in c.values()})==3' \
  && pass "Docker: --json lists the cache, the images and the stopped containers with sizes, keys and opt-in" || { fail "Docker --json"; head -c 900 "$W/dk.json"; }
kd(){ jq "$W/dk.json" "print([x['key'] for x in d['cleanable'] if x['task']=='$1'][0])"; }
for t in "clean.docker:builder prune -f|image prune -f:Docker build cache.*freed 1.5 GB" "clean.docker_images:image prune -a -f:Docker images no container uses.*freed 1.2 GB" "clean.docker_containers:container prune -f:Stopped Docker containers.*freed 12 MB"; do
  IFS=: read -r id cmds re <<<"$t"; k=$(kd "$id")
  rm -f "$H/docker.log"; env HOME="$H" /bin/bash "$M" clean --pick "$k" --only "$DK" --no-color </dev/null >"$W/dk.out" 2>&1; rc=$?
  [ $rc = 0 ] && [ "$(grep prune "$H/docker.log")" = "$(printf '%s' "$cmds" | tr '|' '\n')" ] && grep -q "$re" "$W/dk.out" && ! grep -q 'volume prune\|system prune\|--volumes' "$H/docker.log" \
    && pass "Docker: --pick $id runs only: $cmds" || { fail "Docker --pick $id (rc=$rc)"; cat "$H/docker.log" "$W/dk.out"; }
done
for m in "clean --level aggressive --enable clean.docker_images,clean.docker_containers" "clean --level aggressive" "all --level aggressive"; do
  rm -f "$H/docker.log"; env HOME="$H" /bin/bash "$M" $m --only "$DK" --no-color </dev/null >"$W/dk.out" 2>&1
  ! grep -q 'volume prune\|system prune\|--volumes' "$H/docker.log" && grep -q prune "$H/docker.log" && pass "Docker: no volume prune with: $m" || { fail "Docker volumes touched with: $m"; cat "$H/docker.log"; }
done
rm -f "$H/docker.log"; env FAKE_DK_IMG='0B (0%)' FAKE_DK_CT='0B (0%)' FAKE_DK_BC='0B' FAKE_DK_PS='' FAKE_DK_VOLS='' HOME="$H" /bin/bash "$M" check --only "$DK" --no-color </dev/null >"$W/dk.out" 2>&1
! grep -q 'Docker images\|Stopped Docker\|Docker volumes' "$W/dk.out" && grep -q 'Docker: Images' "$W/dk.out" && pass "Docker: nothing to reclaim offers no images, containers or volumes line" || { fail "Docker with 0 B"; cat "$W/dk.out"; }
rm -f "$H/docker.log"; env FAKE_DK_PRUNE_FAIL=1 HOME="$H" /bin/bash "$M" clean --level standard --only clean.docker --no-color </dev/null >"$W/dk.out" 2>&1; rc=$?
[ $rc = 3 ] && grep -q 'Docker build cache.*failed' "$W/dk.out" && pass "Docker: a failing prune is an error, exit status 3" || { fail "Docker prune failure (rc=$rc)"; cat "$W/dk.out"; }
rm -f "$H/docker.log"; env FAKE_DK_DOWN=1 HOME="$H" /bin/bash "$M" all --only "$DK" --no-color </dev/null >"$W/dk.out" 2>&1; rc=$?
[ $rc = 0 ] && ! grep -qi 'docker\|✗' "$W/dk.out" && ! grep -q 'system df\|ps -aq\|prune' "$H/docker.log" && pass "Docker: a daemon that is not running gives no Docker lines and no error" || { fail "Docker down (rc=$rc)"; cat "$W/dk.out" "$H/docker.log"; }
rm -f "$H/docker.log"; s0=$SECONDS; env FAKE_DK_HANG=1 HOME="$H" /bin/bash "$M" check --only "$DK" --no-color </dev/null >"$W/dk.out" 2>&1; rc=$?
[ $rc = 0 ] && [ $((SECONDS - s0)) -lt 60 ] && ! grep -qi 'docker\|✗' "$W/dk.out" && pass "Docker: a daemon that hangs is given up on after 20 seconds, no Docker lines" || { fail "Docker hangs (rc=$rc, $((SECONDS - s0)) s)"; cat "$W/dk.out"; }

# --- tools/bump-formula.sh: a fake curl and a fake git (it answers ls-remote, everything else goes to the real git) keep it off the network; the tap is a throwaway repository
GIT=$(command -v git); TB="$W/bumpbin"; TAP="$W/tap"; mkdir -p "$TB" "$TAP/Formula"
printf '#!/bin/bash\nwhile [ $# -gt 0 ]; do case "$1" in -o) o=$2; shift ;; http*) echo "$1" >>"$FAKE_LOG" ;; esac; shift; done\n[ -n "$FAKE_CURL_FAIL" ] && exit 22\nprintf "tarball of %%s" "$FAKE_VERSION" >"$o"\n' >"$TB/curl"
cat >"$TB/git" <<'FAKE'
#!/bin/bash
a=("$@"); [ "$1" = -C ] && a=("${a[@]:2}")
echo "git ${a[*]}" >>"$FAKE_LOG"
[ "${a[0]}" = ls-remote ] && { printf '%s\n' "$FAKE_TAGS" | grep -x "${a[3]}" | sed "s|.*|abc123	&|"; exit 0; }
exec "$REAL_GIT" "$@"
FAKE
chmod +x "$TB/curl" "$TB/git"
git -C "$TAP" init -q; git -C "$TAP" config user.email t@t; git -C "$TAP" config user.name t
cat >"$TAP/Formula/macup.rb" <<'RB'
class Macup < Formula
  desc "Checks, updates and safe cache cleanup for a developer's Mac"
  url "https://github.com/VitaliiDeveloper/macup/archive/refs/tags/v2.7.2.tar.gz"
  sha256 "31e8b111ffd0ff13621b062fcd4f30d42b7d7dca4c3dd634164a5db56ac2f471"
  license "MIT"
end
RB
git -C "$TAP" add -A; git -C "$TAP" commit -q -m init
bump(){ : >"$W/bump.log"; env REAL_GIT="$GIT" PATH="$TB:$PATH" FAKE_LOG="$W/bump.log" FAKE_VERSION=9.9.9 FAKE_TAGS='refs/tags/v9.9.9' tools/bump-formula.sh "$@" >"$W/bump.out" 2>&1; }
SUM=$(printf 'tarball of 9.9.9' | shasum -a 256 | awk '{print $1}')
bump 9.9.8 "$TAP"; rc=$?
[ $rc = 1 ] && grep -q 'tag v9.9.8 is not on origin' "$W/bump.out" && grep -q 'v2.7.2' "$TAP/Formula/macup.rb" && ! grep -q 'archive' "$W/bump.log" && pass "bump-formula: a tag that is not on origin stops it before any download" || { fail "bump-formula missing tag (rc=$rc)"; cat "$W/bump.out"; }
bump 9.9 "$TAP"; [ $? = 1 ] && grep -q usage "$W/bump.out" && pass "bump-formula: a version that is not X.Y.Z is refused" || fail "bump-formula bad version"
: >"$W/bump.log"; env REAL_GIT="$GIT" FAKE_CURL_FAIL=1 PATH="$TB:$PATH" FAKE_LOG="$W/bump.log" FAKE_TAGS='refs/tags/v9.9.9' tools/bump-formula.sh 9.9.9 "$TAP" >"$W/bump.out" 2>&1; rc=$?
[ $rc = 1 ] && grep -q 'could not download' "$W/bump.out" && grep -q 'v2.7.2' "$TAP/Formula/macup.rb" && pass "bump-formula: a failed download leaves the formula alone" || { fail "bump-formula download failure (rc=$rc)"; cat "$W/bump.out"; }
bump 9.9.9 "$TAP"; rc=$?
[ $rc = 0 ] && grep -q "^  url \"https://github.com/VitaliiDeveloper/macup/archive/refs/tags/v9.9.9.tar.gz\"$" "$TAP/Formula/macup.rb" && grep -q "^  sha256 \"$SUM\"$" "$TAP/Formula/macup.rb" \
  && [ "$(git -C "$TAP" diff --numstat | awk '{print $1+$2}')" = 4 ] && grep -q "^+  sha256 \"$SUM\"" "$W/bump.out" && grep -q 'commit -m "macup 9.9.9"' "$W/bump.out" && grep -q 'push' "$W/bump.out" \
  && [ "$(git -C "$TAP" rev-list --count HEAD)" = 1 ] && ! grep -q '^git \(push\|commit\)' "$W/bump.log" && grep -q 'archive/refs/tags/v9.9.9.tar.gz' "$W/bump.log" \
  && pass "bump-formula: url and sha256 are edited, the diff is shown, the commands are printed and nothing is committed" || { fail "bump-formula edit (rc=$rc)"; cat "$W/bump.out" "$W/bump.log"; git -C "$TAP" diff; }
bump 9.9.9 "$TAP"; [ $? = 0 ] && grep -q 'already points at v9.9.9' "$W/bump.out" && pass "bump-formula: running it twice changes nothing" || fail "bump-formula twice"
bump --commit 9.9.9 "$TAP"; [ $? = 1 ] && grep -q 'uncommitted changes' "$W/bump.out" && pass "bump-formula: --commit refuses a tap with other changes" || fail "bump-formula --commit on a dirty tap"
git -C "$TAP" checkout -q -- Formula/macup.rb
bump --commit 9.9.9 "$TAP"; rc=$?
[ $rc = 0 ] && [ "$(git -C "$TAP" log -1 --format=%s)" = "macup 9.9.9" ] && [ -z "$(git -C "$TAP" status --porcelain)" ] && ! grep -q '^git push' "$W/bump.log" && pass "bump-formula: --commit makes the commit and never pushes" || { fail "bump-formula --commit (rc=$rc)"; cat "$W/bump.out"; }

# --- a step that hangs is stopped together with what it started
H="$W/tree"; mkdir -p "$H/.local/bin" "$H/.config/macup"; printf 'language = en\n' >"$H/.config/macup/config"
printf '#!/bin/bash\ncase "$1" in --version) echo 1.0 ;; update) sleep 300 & echo $! >"$HOME/child.pid"; wait ;; esac\n' >"$H/.local/bin/agy"; chmod +x "$H/.local/bin/agy"
env HOME="$H" MACUP_STEP_SECS=2 /bin/bash "$M" update --only update.agy --no-color </dev/null >"$W/tree.out" 2>&1
sleep 1; st=$(ps -o stat= -p "$(cat "$H/child.pid")" 2>/dev/null | tr -d ' ')   # gone, or a zombie where nothing reaps it (a container)
case "$st" in ""|Z*) pass "a stopped step takes its child processes along" ;; *) fail "the child of a stopped step still runs ($st)"; kill "$(cat "$H/child.pid")" 2>/dev/null ;; esac

# --- signing certificates close to their date; a fake `security` hands out identities and certificates made here
if command -v openssl >/dev/null; then
  H="$W/crt"; mkdir -p "$H/.local/bin" "$H/.config/macup"; printf 'language = en\n' >"$H/.config/macup/config"
  mk(){ openssl req -x509 -newkey rsa:2048 -nodes -keyout /dev/null -days "$2" -subj "/CN=$1/O=Test" 2>/dev/null; }
  { mk 'Apple Development: Soon Gone (AAAA111111)' 10; mk 'Apple Distribution: Long Lived (BBBB222222)' 300; mk 'Some Web Server' 5
    mk 'Apple Development: Renewed (CCCC333333)' 10; mk 'Apple Development: Renewed (CCCC333333)' 300; mk 'Apple Development: No Key (DDDD444444)' 5; } >"$H/certs.pem"
  printf '  1) 0000000000000000000000000000000000000001 "Apple Development: Soon Gone (AAAA111111)"\n  2) 0000000000000000000000000000000000000002 "Apple Distribution: Long Lived (BBBB222222)"\n  3) 0000000000000000000000000000000000000003 "Apple Development: Renewed (CCCC333333)"\n     3 valid identities found\n' >"$H/identities.txt"
  printf '#!/bin/bash\ncase "$1" in find-identity) cat "$HOME/identities.txt" ;; find-certificate) cat "$HOME/certs.pem" ;; esac\n' >"$H/.local/bin/security"; chmod +x "$H/.local/bin/security"
  env HOME="$H" /bin/bash "$M" check --only check.certs --no-color </dev/null >"$W/crt.out" 2>&1
  grep -q 'Signing certificates that expire within 30 days: 1 ' "$W/crt.out" && grep -q 'Apple Development: Soon Gone' "$W/crt.out" && ! grep -qE 'Long Lived|Web Server|Renewed|No Key' "$W/crt.out" \
    && pass "signing certificates: only an identity whose newest certificate expires soon is named" || { fail "signing certificates"; cat "$W/crt.out"; }
fi

# --- crashes, sharing, PATH: said in a check
H="$W/misc"; DR="$H/Library/Logs/DiagnosticReports"; mkdir -p "$DR/Retired" "$H/.config/macup" "$H/.local/bin"; printf 'language = en\n' >"$H/.config/macup/config"
mkips(){ # dir name bug_type days-ago procPath [file-prefix]
  python3 - "$@" <<'PY'
import datetime, json, sys, uuid
d, name, bug, ago, path = sys.argv[1:6]; pre = sys.argv[6] if len(sys.argv) > 6 else ""
ts = (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=float(ago))).strftime("%Y-%m-%d %H:%M:%S.00 +0000")
head = {"app_name": name, "timestamp": ts, "bug_type": bug, "name": name}
open("%s/%s%s-%s.ips" % (d, pre, name, uuid.uuid4().hex[:8]), "w").write(json.dumps(head) + "\n" + json.dumps({"procPath": path, "procName": name}).replace("/", "\\/") + "\n")
PY
}
for i in 1 2; do mkips "$DR" "Crashy App" 309 1 "/Applications/Crashy App.app/Contents/MacOS/Crashy App"; mkips "$DR/Retired" "Crashy App" 309 2 "/Applications/Crashy App.app/Contents/MacOS/Crashy App"; done
for i in 1 2 3; do mkips "$DR" "Crashy App" 309 1 "/Applications/Crashy App.app/Contents/MacOS/Crashy App" ExcUserFault_; done
for i in 1 2 3; do mkips "$DR/Retired" "Old App" 309 20 "/Applications/Old App.app/Contents/MacOS/Old App"; mkips "$DR" "Hang App" 385 1 "/Applications/Hang App.app/Contents/MacOS/Hang App"; done
for i in 1 2 3; do mkips "$DR" "Home App" 309 3 "$H/Applications/Home App.app/Contents/MacOS/Home App"; done
for i in 1 2 3 4 5; do mkips "$DR/Retired" "sysd" 309 1 "/System/Library/CoreServices/sysd"; done
for i in 1 2 3; do printf 'Process: Legacy App [1]\nPath: /Applications/Legacy App.app/Contents/MacOS/Legacy App\n' >"$DR/Legacy App_2026-11-1$i-100000_Mac.crash"; done
env HOME="$H" /bin/bash "$M" check --only check.crashes --no-color </dev/null >"$W/misc.out" 2>&1
grep -E 'Crashed 3 or more times in the last 7 days: ' "$W/misc.out" | grep -q 'Crashy App ×4' && grep -E 'Crashed 3' "$W/misc.out" | grep -q 'Home App ×3' && grep -E 'Crashed 3' "$W/misc.out" | grep -q 'Legacy App ×3' && ! grep -qE 'Old App|Hang App|sysd' "$W/misc.out" \
  && pass "crashes: Retired counted, ExcUserFault_, other report types and old crashes skipped, only apps named" || { fail "crashes"; cat "$W/misc.out"; }
grep -q 'macOS system processes crashed 5 times this week (not yours to fix; Apple gets the reports)$' "$W/misc.out" && ! grep -q "$H" "$W/misc.out" && pass "crashes: system processes are a count" || { fail "crash system count"; cat "$W/misc.out"; }
FAKE_SHARING='	"com.openssh.sshd" => enabled' env HOME="$H" /bin/bash "$M" check --only check.security --no-color </dev/null >"$W/misc.out" 2>&1
grep -q 'Remote Login (SSH) is on' "$W/misc.out" && ! grep -qE 'Screen Sharing|Remote Management' "$W/misc.out" && pass "sharing: Remote Login that is on is said" || { fail "sharing"; cat "$W/misc.out"; }
FAKE_SHARING='	"com.apple.RemoteDesktop.agent" => enabled' env HOME="$H" /bin/bash "$M" check --only check.security --no-color </dev/null >"$W/misc.out" 2>&1
grep -q 'Remote Management is on' "$W/misc.out" && pass "sharing: Remote Management that is on is said" || { fail "Remote Management"; cat "$W/misc.out"; }
FAKE_SHARING='	"com.apple.RemoteDesktop.agent" => disabled' FAKE_PROCS=ARDAgent env HOME="$H" /bin/bash "$M" check --only check.security --no-color </dev/null >"$W/misc.out" 2>&1
! grep -q 'Remote Management' "$W/misc.out" && pass "sharing: Remote Management that print-disabled lists as disabled is not said" || { fail "Remote Management disabled"; cat "$W/misc.out"; }
FAKE_PROCS=ARDAgent env HOME="$H" /bin/bash "$M" check --only check.security --no-color </dev/null >"$W/misc.out" 2>&1
grep -q 'Remote Management is on' "$W/misc.out" && pass "sharing: ARDAgent running without a print-disabled entry is Remote Management" || { fail "Remote Management by process"; cat "$W/misc.out"; }
env HOME="$H" PATH="$PATH:$H/no/such/dir:/macup/no/such/system/dir" /bin/bash "$M" check --only check.commands --no-color </dev/null >"$W/misc.out" 2>&1
grep -q 'PATH names folders that do not exist: ~/no/such/dir ' "$W/misc.out" && pass "PATH: a folder that does not exist is said" || { fail "PATH folders"; cat "$W/misc.out"; }
if [ "$(id -u)" = 0 ]; then
  env HOME="$H" SUDO_USER=me /bin/bash "$M" check --only check.system </dev/null >"$W/misc.out" 2>&1; [ $? = 1 ] && grep -q 'does not need sudo' "$W/misc.out" && pass "sudo macup refuses to run" || fail "sudo macup ran"
fi

echo; [ $F = 0 ] && echo "ALL PASS" || { echo "SOME FAILED"; exit 1; }

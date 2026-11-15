#!/bin/bash
# shellcheck disable=SC2088  # a literal ~ is what users type into the installer
# macup test suite. Everything runs against throwaway fake home folders; the real one is never touched.
#   tests/run.sh          all tests
cd "$(dirname "$0")/.." || exit 1
W=$(mktemp -d "${TMPDIR:-/tmp}/macup-tests.XXXXXX"); trap 'rm -rf "$W"' EXIT
F=0; pass(){ echo "PASS $*"; }; fail(){ echo "FAIL $*"; F=1; }
M="$PWD/macup"; X='update.*,clean.brew,clean.npm,clean.pnpm,clean.pip,clean.uv,clean.go,clean.sim_unavailable,clean.quicklook,clean.docker,check.*'

# `running` asks pgrep which apps are open; a fake one answers from FAKE_RUNNING (command lines, one per line), so results never depend on this machine
mkdir -p "$W/bin"; cat >"$W/bin/pgrep" <<'FAKE'
#!/bin/bash
[ "$1" = "-f" ] && [ -n "$2" ] && printf '%s\n' "${FAKE_RUNNING:-}" | grep -qE -- "$2"
FAKE
# `lsof` tells which app folders have open files: a fake one lists FAKE_OPEN paths (one per line), or fails with FAKE_LSOF_FAIL
cat >"$W/bin/lsof" <<'FAKE'
#!/bin/bash
[ -n "$FAKE_LSOF_FAIL" ] && exit 1
printf 'p1\nn/\n'; printf '%s\n' "${FAKE_OPEN:-}" | sed '/^$/d; s/^/n/'
FAKE
# launchctl and osascript only record what macup asked for: no test loads a LaunchAgent or shows a notification
for c in launchctl osascript; do printf '#!/bin/bash\necho "$*" >>"$HOME/%s.log"\n' "$c" >"$W/bin/$c"; done
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
echo "$got" | grep -E 'codex/sessions|sqlite|gradle.properties|settings.xml|avd|debug.keystore|adbkey|/User/|Backups|Login Data|/History|/Cookies|QtApp|ShipIt|sparkle|Local Storage|elsewhere|Archives|Downloads|Documents|BigApp|com.apple|\.Trash|Code/old|3\.12\.1|3\.13\.1|3\.10\.2|v22\.1\.0|\.m2/|virtualenvs|v21\.2\.5|v21\.7\.0|v23\.|registry/index|Code/(rs|plain)' \
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
env HOME="$H" /bin/bash "$M" check --only check.sizes --json </dev/null 2>/dev/null >"$W/rc.json"
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["mode"]=="check" and d["failed_steps"]==0 and isinstance(d["needs_attention"],list) and d["report"].endswith(".md")' "$W/rc.json" 2>/dev/null \
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

# --- installer
I="$W/i"; mkdir -p "$I/.npm-global/bin"; printf '#!/bin/bash\n# macup — old\nMACUP_VERSION="1.1"\n' >"$I/.npm-global/bin/macup"; printf '#!/bin/bash\n# macup notes\n' >"$I/.npm-global/bin/other"
# no test may hang the suite: after the limit it says what was running and stops the command
lim(){ local s=$1 p w rc; shift; "$@" & p=$!
  ( sleep "$s"; echo "TIMEOUT after ${s}s: $*"; ps -axo pid,ppid,etime,command | grep -v 'ps -axo' | tail -25; kill $p 2>/dev/null ) & w=$!
  wait $p; rc=$?; kill $w 2>/dev/null; wait $w 2>/dev/null; return $rc; }
lim 120 env HOME="$I" MACUP_PREFIX="$W/bin" /bin/bash -x ./install.sh --yes --lang uk --projects "~/Code, ~/Work" </dev/null >"$W/in" 2>&1; rc=$?
[ $rc = 0 ] && [ ! -e "$I/.npm-global/bin/macup" ] && [ -e "$I/.npm-global/bin/other" ] && [ -x "$W/bin/macup" ] && grep -q '^project_dirs = ~/Code, ~/Work' "$I/.config/macup/config" \
  && pass "install replaces an old copy, keeps unrelated files" || { fail "install (rc=$rc)"; tail -40 "$W/in"; }
lim 120 env HOME="$I" MACUP_PREFIX="$W/bin" /bin/bash ./install.sh --yes </dev/null >/dev/null 2>&1
grep -q '^project_dirs = ~/Code, ~/Work' "$I/.config/macup/config" && grep -q '^language = uk' "$I/.config/macup/config" && [ "$(grep -c '# macup' "$I/.zshrc")" = 1 ] \
  && pass "reinstall keeps settings" || fail "reinstall"
/bin/bash ./install.sh --bogus >/dev/null 2>&1; [ $? = 2 ] && pass "installer rejects unknown options" || fail "installer options"

echo; [ $F = 0 ] && echo "ALL PASS" || { echo "SOME FAILED"; exit 1; }

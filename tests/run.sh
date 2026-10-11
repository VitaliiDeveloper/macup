#!/bin/bash
# shellcheck disable=SC2088  # a literal ~ is what users type into the installer
# macup test suite. Everything runs against throwaway fake home folders; the real one is never touched.
#   tests/run.sh          all tests
cd "$(dirname "$0")/.." || exit 1
W=$(mktemp -d "${TMPDIR:-/tmp}/macup-tests.XXXXXX"); trap 'rm -rf "$W"' EXIT
F=0; pass(){ echo "PASS $*"; }; fail(){ echo "FAIL $*"; F=1; }
M="$PWD/macup"; X='update.*,clean.brew,clean.npm,clean.pnpm,clean.pip,clean.uv,clean.go,clean.sim_unavailable,clean.quicklook,clean.docker,check.*'

# lines for apps that are open on this machine are expected to be skipped, so drop them from both sides
open_apps(){ local a; for a in "Claude:Application Support/Claude/" "Cursor:Application Support/Cursor/" "Visual Studio Code:Application Support/Code/" \
  "Arc:Caches/Arc/" "Google Chrome:Caches/Google/Chrome/" "Microsoft Edge:Caches/Microsoft Edge/"; do pgrep -f "/${a%%:*}.app/Contents/" >/dev/null 2>&1 && echo "${a#*:}"; done; }
OPEN=$(open_apps); unopen(){ if [ -n "$OPEN" ]; then grep -vF "$OPEN"; else cat; fi; }
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
  got=$(deleted "$W/l$lv" clean --level $lv --skip "$X" --no-color | unopen)
  [ "$got" = "$(echo "$exp" | unopen)" ] && pass "clean --level $lv deletes exactly the expected files" || { fail "clean --level $lv"; diff <(echo "$exp" | unopen) <(echo "$got") | head; }
done
echo "$got" | grep -E 'codex/sessions|sqlite|gradle.properties|settings.xml|avd|debug.keystore|adbkey|/User/|Backups|Login Data|elsewhere|Archives|Downloads|Documents|BigApp|com.apple|\.Trash|Code/old|3\.12\.1|v22\.1\.0|\.m2/' \
  && fail "protected files deleted" || pass "protected files survive --level aggressive"
[ -f "$W/laggressive/elsewhere2/big" ] && [ -f "$W/laggressive/elsewhere/precious" ] && pass "symlinked cache targets survive" || fail "symlink target deleted"

# --- an app that is open is skipped
H="$W/run"; tests/fixture.sh "$H"
bash -c 'exec -a "/Applications/Cursor.app/Contents/MacOS/Cursor" sleep 30' & P=$!; sleep 0.5
env HOME="$H" /bin/bash "$M" clean --skip "$X" --no-color </dev/null >"$W/run.out" 2>&1; kill $P 2>/dev/null; wait $P 2>/dev/null
[ -f "$H/Library/Application Support/Cursor/Cache/c/blob" ] && grep -q 'Cursor caches.*skipped' "$W/run.out" && pass "open app is skipped" || fail "open app was cleaned"

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
[ "$(pick "$n1,$n2")" = "$(printf '%s\n' './Library/Caches/org.swift.swiftpm/repos/blob' './Library/Developer/Xcode/DerivedData/App-abc/blob')" ] && pass "pick: numbers delete exactly those" || fail "pick: numbers"
[ -z "$(pick "$nt" n)" ] && pass "pick: opt-in item needs a yes" || fail "pick: confirmation"
[ "$(pick "$nt" y)" = "./.Trash/thing/blob" ] && pass "pick: opt-in item after yes" || fail "pick: yes"
got=$(PL=uk pick 'безпечна')
[ "$got" = "$(unopen <tests/expect-safe.txt)" ] && pass "pick: a level word in the interface language" || { fail "pick: localized level"; diff <(unopen <tests/expect-safe.txt) <(echo "$got") | head; }

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

# --- installer
I="$W/i"; mkdir -p "$I/.npm-global/bin"; printf '#!/bin/bash\n# macup — old\nMACUP_VERSION="1.1"\n' >"$I/.npm-global/bin/macup"; printf '#!/bin/bash\n# macup notes\n' >"$I/.npm-global/bin/other"
env HOME="$I" MACUP_PREFIX="$W/bin" /bin/bash ./install.sh --yes --lang uk --projects "~/Code, ~/Work" </dev/null >"$W/in" 2>&1; rc=$?
[ $rc = 0 ] && [ ! -e "$I/.npm-global/bin/macup" ] && [ -e "$I/.npm-global/bin/other" ] && [ -x "$W/bin/macup" ] && grep -q '^project_dirs = ~/Code, ~/Work' "$I/.config/macup/config" \
  && pass "install replaces an old copy, keeps unrelated files" || { fail "install (rc=$rc)"; cat "$W/in"; }
env HOME="$I" MACUP_PREFIX="$W/bin" /bin/bash ./install.sh --yes </dev/null >/dev/null 2>&1
grep -q '^project_dirs = ~/Code, ~/Work' "$I/.config/macup/config" && grep -q '^language = uk' "$I/.config/macup/config" && [ "$(grep -c '# macup' "$I/.zshrc")" = 1 ] \
  && pass "reinstall keeps settings" || fail "reinstall"
/bin/bash ./install.sh --bogus >/dev/null 2>&1; [ $? = 2 ] && pass "installer rejects unknown options" || fail "installer options"

echo; [ $F = 0 ] && echo "ALL PASS" || { echo "SOME FAILED"; exit 1; }

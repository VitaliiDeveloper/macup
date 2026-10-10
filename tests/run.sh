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
pick(){ # answer [confirm] → files deleted
  local H="$W/p"; tests/fixture.sh "$H"; (cd "$H" && find . -type f | sort) >"$W/pb"
  (sleep 2; printf '%s\n' "$1"; sleep 1; printf '%s\n' "${2:-}"; sleep 2) | script -q /dev/null env HOME="$H" /bin/bash "$M" check --no-color --skip "$X" ${PL:+--lang $PL} >"$W/po" 2>&1
  (cd "$H" && find . -type f | sort) | comm -23 "$W/pb" - | grep -v -e 'Logs/macup/' -e 'Support/macup/'
}
num(){ tr -d '\r' <"$W/po" | grep -E "^ +[0-9]+ .*$1" | head -1 | awk '{print $1}'; }
[ -z "$(pick '')" ] && pass "pick: Enter deletes nothing" || fail "pick: Enter"
[ -z "$(pick 'zzz, 999')" ] && pass "pick: garbage deletes nothing" || fail "pick: garbage"
pick '' >/dev/null; n1=$(num 'Xcode DerivedData'); n2=$(num 'SwiftPM cache'); nt=$(num 'Trash')
[ "$(pick "$n1,$n2")" = "$(printf '%s\n' './Library/Caches/org.swift.swiftpm/repos/blob' './Library/Developer/Xcode/DerivedData/App-abc/blob')" ] && pass "pick: numbers delete exactly those" || fail "pick: numbers"
[ -z "$(pick "$nt" n)" ] && pass "pick: opt-in item needs a yes" || fail "pick: confirmation"
[ "$(pick "$nt" y)" = "./.Trash/thing/blob" ] && pass "pick: opt-in item after yes" || fail "pick: yes"
[ "$(PL=uk pick 'безпечна')" = "$(unopen <tests/expect-safe.txt)" ] && pass "pick: a level word in the interface language" || fail "pick: localized level"

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

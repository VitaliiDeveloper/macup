# shellcheck shell=bash
# shellcheck disable=SC2154  # SC2154: work, quick_skip, build_path and the helpers come from tests/run.sh
# Sourced by tests/run.sh: picking after a check, simulators, npm without node, App Store.
# --- picking after an interactive check
pick(){ # answer [confirm] → files deleted
  local home="$work/p"; tests/fixture.sh "$home"; (cd "$home" && find . -type f | sort) >"$work/pb"
  (sleep 2; printf '%s\n' "$1"; sleep 1; printf '%s\n' "${2:-}"; until_done "$work/po") | script -q /dev/null env HOME="$home" macup_run check --no-color --skip "$quick_skip" ${PL:+--lang $PL} >"$work/po" 2>&1
  (cd "$home" && find . -type f | sort) | comm -23 "$work/pb" - | grep -v -e 'Logs/macup/' -e 'Support/macup/'
}
num(){ tr -d '\r' <"$work/po" | grep -E "^ +[0-9]+ .*$1" | head -1 | awk '{print $1}'; }
[ -z "$(pick '')" ] && pass "pick: Enter deletes nothing" || fail "pick: Enter"
[ -z "$(pick 'zzz, 999')" ] && pass "pick: garbage deletes nothing" || fail "pick: garbage"
pick '' >/dev/null; n1=$(num 'Xcode DerivedData'); n2=$(num 'SwiftPM cache'); nt=$(num 'Trash')
[ "$(pick "$n1,$n2" | LC_ALL=C sort)" = "$(printf '%s\n' './Library/Caches/org.swift.swiftpm/repos/blob' './Library/Developer/Xcode/DerivedData/App-abc/blob' | LC_ALL=C sort)" ] && pass "pick: numbers delete exactly those" || fail "pick: numbers"
[ -z "$(pick "$nt" n)" ] && pass "pick: opt-in item needs a yes" || fail "pick: confirmation"
[ "$(pick "$nt" y)" = "./.Trash/thing/blob" ] && pass "pick: opt-in item after yes" || fail "pick: yes"
nw=$(num 'data of workspaces whose folder is gone')
[ -n "$nw" ] && [ "$(pick "$nw" y | LC_ALL=C sort)" = "$(printf '%s\n' './Library/Application Support/Code/User/workspaceStorage/abc123/state.vscdb' './Library/Application Support/Code/User/workspaceStorage/abc123/workspace.json' | LC_ALL=C sort)" ] \
  && [ -f "$work/p/.Trash/abc123/state.vscdb" ] && pass "pick: a gone workspace's data goes to the Trash; present, unmounted, symlinked and iCloud ones stay" || fail "pick: editor workspaces"
got=$(PL=uk pick 'безпечна')
[ "$(echo "$got" | LC_ALL=C sort)" = "$(LC_ALL=C sort <tests/expect-safe.txt)" ] && pass "pick: a level word in the interface language" || { fail "pick: localized level"; diff <(LC_ALL=C sort <tests/expect-safe.txt) <(echo "$got") | head; }

# --- simulators: only on pick, never a booted one; a fake xcrun records what macup asks for
home="$work/sim"; mkdir -p "$home/.local/bin" "$home/.config/macup"; printf 'language = en\n' >"$home/.config/macup/config"
SD="$home/Library/Developer/CoreSimulator/Devices"
mkdir -p "$SD/AAAA-0001/data" "$SD/BBBB-0002/data/Containers" "$SD/CCCC-0003/data" "$SD/DDDD-0004/data"
dd if=/dev/zero of="$SD/BBBB-0002/data/Containers/app" bs=1024 count=103424 2>/dev/null   # heavy, recently used
echo x >"$SD/CCCC-0003/data/x"; find "$SD/CCCC-0003" -exec touch -t 202401010000 {} +    # unused for a long time
echo x >"$SD/DDDD-0004/data/x"                                                           # used today
cat >"$home/.local/bin/xcrun" <<'FAKE'
#!/bin/bash
case "$*" in
  "simctl list devices -j") echo '{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-26-5":[{"udid":"AAAA-0001","state":"Booted","name":"iPhone A"},{"udid":"CCCC-0003","state":"Shutdown","name":"iPhone C"}],"com.apple.CoreSimulator.SimRuntime.iOS-27-0":[{"udid":"BBBB-0002","state":"Shutdown","name":"iPhone B"},{"udid":"DDDD-0004","state":"Shutdown","name":"iPhone D"}],"com.apple.CoreSimulator.SimRuntime.iOS-25-0":[]}}' ;;
  "simctl runtime list -j") echo '{"A1B2-0026":{"runtimeIdentifier":"com.apple.CoreSimulator.SimRuntime.iOS-26-5","version":"26.5","sizeBytes":8000000000,"lastUsedAt":"2026-10-10T00:00:00Z","deletable":true},"A1B2-0027":{"runtimeIdentifier":"com.apple.CoreSimulator.SimRuntime.iOS-27-0","version":"27.0","sizeBytes":7000000000,"deletable":true},"A1B2-0025":{"runtimeIdentifier":"com.apple.CoreSimulator.SimRuntime.iOS-25-0","version":"25.0","sizeBytes":6000000000,"lastUsedAt":"2025-01-01T00:00:00Z","deletable":true}}' ;;
  simctl\ list*) ;;
  *) echo "$*" >>"$HOME/xcrun.log" ;;
esac
FAKE
chmod +x "$home/.local/bin/xcrun"; SO='clean.sim_runtimes,clean.sim_erase,clean.sim_unused'
env HOME="$home" macup_run clean --level aggressive --only "$SO" --no-color </dev/null >/dev/null 2>&1
[ ! -s "$home/xcrun.log" ] && pass "simulators: nothing without a pick, even at --level aggressive" || { fail "simulators touched without a pick"; cat "$home/xcrun.log"; }
(sleep 2; printf '1-20\n'; sleep 1; printf 'y\n'; until_done "$work/sim.out") | script -q /dev/null env HOME="$home" macup_run check --only "$SO" --no-color >"$work/sim.out" 2>&1
want=$(printf '%s\n' 'simctl runtime delete A1B2-0027' 'simctl runtime delete A1B2-0025' 'simctl erase BBBB-0002' 'simctl delete CCCC-0003' | sort)
[ "$(sort "$home/xcrun.log" 2>/dev/null)" = "$want" ] && pass "simulators: exactly the picked runtimes and devices; booted and recent ones stay" \
  || { fail "simulators"; echo "want:"; echo "$want"; echo "got:"; cat "$home/xcrun.log"; tr -d '\r' <"$work/sim.out" | grep -iE 'simulat|runtime' | head; }

# --- unavailable simulators: the default set and Xcode's test clones (XCTestDevices), with their real size; never while Xcode runs
home="$work/unav"; mkdir -p "$home/.local/bin" "$home/.config/macup"; printf 'language = en\n' >"$home/.config/macup/config"
U1=11111111-AAAA-4AAA-8AAA-111111111111; U2=22222222-BBBB-4BBB-8BBB-222222222222; XT="$home/Library/Developer/XCTestDevices"
for dir in "$home/Library/Developer/CoreSimulator/Devices/$U1" "$XT/$U2"; do mkdir -p "$dir/data"; dd if=/dev/zero of="$dir/data/x" bs=1024 count=3072 2>/dev/null; done
cat >"$home/.local/bin/xcrun" <<FAKE
#!/bin/bash
case "\$*" in
  "simctl list devices unavailable") [ -z "\$NODEFAULT" ] && echo "    iPhone A ($U1) (Shutdown) (unavailable, runtime profile not found)" ;;
  "simctl --set $XT list devices unavailable") echo "    Clone 2 of iPhone B ($U2) (Shutdown) (unavailable, runtime profile not found)" ;;
  simctl\ *list*) ;;
  *) echo "\$*" >>"\$HOME/xcrun.log" ;;
esac
FAKE
chmod +x "$home/.local/bin/xcrun"
env HOME="$home" macup_run check --only clean.sim_unavailable --no-color </dev/null >"$work/unav.out" 2>&1
grep -qE 'safe +6 MB +Unavailable simulators \(2\)' "$work/unav.out" && [ ! -s "$home/xcrun.log" ] && pass "unavailable simulators: check shows both sets with their size" || { fail "unavailable simulators: check"; grep -i simulat "$work/unav.out"; }
FAKE_RUNNING='/Applications/Xcode.app/Contents/MacOS/Xcode' env HOME="$home" macup_run clean --only clean.sim_unavailable --no-color </dev/null >"$work/unav.out" 2>&1
[ ! -s "$home/xcrun.log" ] && grep -q 'Unavailable simulators (2).*skipped' "$work/unav.out" && pass "unavailable simulators: skipped while Xcode is open" || fail "unavailable simulators deleted while Xcode is open"
env HOME="$home" macup_run clean --only clean.sim_unavailable --no-color </dev/null >"$work/unav.out" 2>&1
[ "$(cat "$home/xcrun.log" 2>/dev/null)" = "$(printf '%s\n' 'simctl delete unavailable' "simctl --set $XT delete unavailable")" ] && pass "unavailable simulators: both sets deleted" || { fail "unavailable simulators: delete"; cat "$home/xcrun.log"; }
rm -f "$home/xcrun.log"; env NODEFAULT=1 HOME="$home" macup_run clean --only clean.sim_unavailable --no-color </dev/null >"$work/unav.out" 2>&1
[ "$(cat "$home/xcrun.log" 2>/dev/null)" = "simctl --set $XT delete unavailable" ] && pass "unavailable simulators: only the set that has some" || { fail "unavailable simulators: only test clones"; cat "$home/xcrun.log"; }

# --- npm/npx on PATH without node (unlinked keg-only node@24): both steps say so instead of a false "up to date"
if ! PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin" command -v node >/dev/null; then
  home="$work/nonode"; mkdir -p "$home/.local/bin" "$home/.agents" "$home/.config/macup"; printf 'language = en\n' >"$home/.config/macup/config"; echo '{"skills":{}}' >"$home/.agents/.skill-lock.json"
  for tool in npm npx; do printf '#!/bin/bash\necho "%s $*" >>"$HOME/npm.log"\n' "$tool" >"$home/.local/bin/$tool"; chmod +x "$home/.local/bin/$tool"; done
  mkdir -p "$home/brew/opt/node@24/bin"; cp /usr/bin/true "$home/brew/opt/node@24/bin/node"
  env PATH="$work/bin:/usr/bin:/bin" HOME="$home" HOMEBREW_PREFIX="$home/brew" macup_run check --only update.npm,update.skills --no-color </dev/null >"$work/nonode.out" 2>&1
  grep -q 'npm globals: skipped, node is not on PATH — run: brew link --.* node' "$work/nonode.out" && grep -q 'Agent skills: skipped, node is not on PATH — run: brew link' "$work/nonode.out" \
    && ! grep -q 'up to date' "$work/nonode.out" && [ ! -e "$home/npm.log" ] && pass "no node: npm globals and agent skills skipped with a warning" \
    || { fail "no node"; grep -iE 'npm|skill' "$work/nonode.out"; cat "$home/npm.log" 2>/dev/null; }
else echo "SKIP no node: node is installed here"; fi

# --- App Store: the list comes first, then one app at a time with its own result; no password means nothing runs
# mas and sudo are exported functions: macup puts /opt/homebrew/bin first in PATH, so a fake file would lose to the real mas
home="$work/mas"; mkdir -p "$home/.config/macup"; printf 'language = en\n' >"$home/.config/macup/config"
mas(){ case $1 in outdated) printf '        1  Foo          (1.0    -> 1.1)\n123456789  Bar Baz Pro  (2.10.3 -> 3.0)\n' ;; upgrade) echo "mas $*" >>"$HOME/mas.log"; [ "$2" = 1 ] ;; esac; }
sudo(){ [ -z "$NOSUDO" ]; }
export -f mas sudo
env HOME="$home" macup_run update --only update.mas --no-color </dev/null >"$work/mas.out" 2>&1
grep -q '^      Bar Baz Pro (2.10.3 → 3.0)$' "$work/mas.out" && grep -q '✓ App Store: Foo (1.0 → 1.1)$' "$work/mas.out" \
  && grep -q '✗ App Store: updates not installed: Bar Baz Pro (2.10.3 → 3.0) — open the App Store' "$work/mas.out" \
  && [ "$(cat "$home/mas.log")" = "$(printf 'mas upgrade 1\nmas upgrade 123456789')" ] && pass "App Store: list, then each app with its result" \
  || { fail "App Store update"; grep 'App Store\|→' "$work/mas.out"; cat "$home/mas.log" 2>/dev/null; }
rm -f "$home/mas.log"; env NOSUDO=1 HOME="$home" macup_run update --only update.mas --no-color </dev/null >"$work/mas.out" 2>&1
grep -q 'updates not installed: 2 — they need your Mac password' "$work/mas.out" && [ ! -e "$home/mas.log" ] && pass "App Store: no password, mas never runs" \
  || { fail "App Store without a password"; grep 'App Store' "$work/mas.out"; }
unset -f mas sudo


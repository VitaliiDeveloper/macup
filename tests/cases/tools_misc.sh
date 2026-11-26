# shellcheck shell=bash
# shellcheck disable=SC2154  # globals of tests/run.sh
# Sourced by tests/run.sh: bump-formula, hanging step tree, certificates, crashes, sharing, PATH, MACUP_PATH=keep.
# --- tools/bump-formula.sh: a fake curl and a fake git (it answers ls-remote, everything else goes to the real git) keep it off the network; the tap is a throwaway repository
GIT=$(command -v git); TB="$work/bumpbin"; TAP="$work/tap"; mkdir -p "$TB" "$TAP/Formula"
printf '#!/bin/bash\nwhile [ $# -gt 0 ]; do case "$1" in -o) out=$2; shift ;; http*) echo "$1" >>"$FAKE_LOG" ;; esac; shift; done\n[ -n "$FAKE_CURL_FAIL" ] && exit 22\nprintf "tarball of %%s" "$FAKE_VERSION" >"$out"\n' >"$TB/curl"
cat >"$TB/git" <<'FAKE'
#!/bin/bash
args=("$@"); [ "$1" = -C ] && args=("${args[@]:2}")
echo "git ${args[*]}" >>"$FAKE_LOG"
[ "${args[0]}" = ls-remote ] && { printf '%s\n' "$FAKE_TAGS" | grep -x "${args[3]}" | sed "s|.*|abc123	&|"; exit 0; }
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
bump(){ : >"$work/bump.log"; env REAL_GIT="$GIT" PATH="$TB:$PATH" FAKE_LOG="$work/bump.log" FAKE_VERSION=9.9.9 FAKE_TAGS='refs/tags/v9.9.9' tools/bump-formula.sh "$@" >"$work/bump.out" 2>&1; }
SUM=$(printf 'tarball of 9.9.9' | shasum -a 256 | awk '{print $1}')
bump 9.9.8 "$TAP"; rc=$?
[ $rc = 1 ] && grep -q 'tag v9.9.8 is not on origin' "$work/bump.out" && grep -q 'v2.7.2' "$TAP/Formula/macup.rb" && ! grep -q 'archive' "$work/bump.log" && pass "bump-formula: a tag that is not on origin stops it before any download" || { fail "bump-formula missing tag (rc=$rc)"; cat "$work/bump.out"; }
bump 9.9 "$TAP"; [ $? = 1 ] && grep -q usage "$work/bump.out" && pass "bump-formula: a version that is not X.Y.Z is refused" || fail "bump-formula bad version"
: >"$work/bump.log"; env REAL_GIT="$GIT" FAKE_CURL_FAIL=1 PATH="$TB:$PATH" FAKE_LOG="$work/bump.log" FAKE_TAGS='refs/tags/v9.9.9' tools/bump-formula.sh 9.9.9 "$TAP" >"$work/bump.out" 2>&1; rc=$?
[ $rc = 1 ] && grep -q 'could not download' "$work/bump.out" && grep -q 'v2.7.2' "$TAP/Formula/macup.rb" && pass "bump-formula: a failed download leaves the formula alone" || { fail "bump-formula download failure (rc=$rc)"; cat "$work/bump.out"; }
bump 9.9.9 "$TAP"; rc=$?
[ $rc = 0 ] && grep -q "^  url \"https://github.com/VitaliiDeveloper/macup/archive/refs/tags/v9.9.9.tar.gz\"$" "$TAP/Formula/macup.rb" && grep -q "^  sha256 \"$SUM\"$" "$TAP/Formula/macup.rb" \
  && [ "$(git -C "$TAP" diff --numstat | awk '{print $1+$2}')" = 4 ] && grep -q "^+  sha256 \"$SUM\"" "$work/bump.out" && grep -q 'commit -m "macup 9.9.9"' "$work/bump.out" && grep -q 'push' "$work/bump.out" \
  && [ "$(git -C "$TAP" rev-list --count HEAD)" = 1 ] && ! grep -q '^git \(push\|commit\)' "$work/bump.log" && grep -q 'archive/refs/tags/v9.9.9.tar.gz' "$work/bump.log" \
  && pass "bump-formula: url and sha256 are edited, the diff is shown, the commands are printed and nothing is committed" || { fail "bump-formula edit (rc=$rc)"; cat "$work/bump.out" "$work/bump.log"; git -C "$TAP" diff; }
bump 9.9.9 "$TAP"; [ $? = 0 ] && grep -q 'already points at v9.9.9' "$work/bump.out" && pass "bump-formula: running it twice changes nothing" || fail "bump-formula twice"
bump --commit 9.9.9 "$TAP"; [ $? = 1 ] && grep -q 'uncommitted changes' "$work/bump.out" && pass "bump-formula: --commit refuses a tap with other changes" || fail "bump-formula --commit on a dirty tap"
git -C "$TAP" checkout -q -- Formula/macup.rb
bump --commit 9.9.9 "$TAP"; rc=$?
[ $rc = 0 ] && [ "$(git -C "$TAP" log -1 --format=%s)" = "macup 9.9.9" ] && [ -z "$(git -C "$TAP" status --porcelain)" ] && ! grep -q '^git push' "$work/bump.log" && pass "bump-formula: --commit makes the commit and never pushes" || { fail "bump-formula --commit (rc=$rc)"; cat "$work/bump.out"; }

# --- a step that hangs is stopped together with what it started
home="$work/tree"; mkdir -p "$home/.local/bin" "$home/.config/macup"; printf 'language = en\n' >"$home/.config/macup/config"
printf '#!/bin/bash\ncase "$1" in --version) echo 1.0 ;; update) sleep 300 & echo $! >"$HOME/child.pid"; wait ;; esac\n' >"$home/.local/bin/agy"; chmod +x "$home/.local/bin/agy"
env HOME="$home" MACUP_STEP_SECS=2 macup_run update --only update.agy --no-color </dev/null >"$work/tree.out" 2>&1
sleep 1; st=$(ps -o stat= -p "$(cat "$home/child.pid")" 2>/dev/null | tr -d ' ')   # gone, or a zombie where nothing reaps it (a container)
case "$st" in ""|Z*) pass "a stopped step takes its child processes along" ;; *) fail "the child of a stopped step still runs ($st)"; kill "$(cat "$home/child.pid")" 2>/dev/null ;; esac

# --- signing certificates close to their date; a fake `security` hands out identities and certificates made here
if command -v openssl >/dev/null; then
  home="$work/crt"; mkdir -p "$home/.local/bin" "$home/.config/macup"; printf 'language = en\n' >"$home/.config/macup/config"
  mk(){ openssl req -x509 -newkey rsa:2048 -nodes -keyout /dev/null -days "$2" -subj "/CN=$1/O=Test" 2>/dev/null; }
  { mk 'Apple Development: Soon Gone (AAAA111111)' 10; mk 'Apple Distribution: Long Lived (BBBB222222)' 300; mk 'Some Web Server' 5
    mk 'Apple Development: Renewed (CCCC333333)' 10; mk 'Apple Development: Renewed (CCCC333333)' 300; mk 'Apple Development: No Key (DDDD444444)' 5; mk 'Developer ID Application: Acme, Inc. (EEEE555555)' 10; } >"$home/certs.pem"
  printf '  1) 0000000000000000000000000000000000000001 "Apple Development: Soon Gone (AAAA111111)"\n  2) 0000000000000000000000000000000000000002 "Apple Distribution: Long Lived (BBBB222222)"\n  3) 0000000000000000000000000000000000000003 "Apple Development: Renewed (CCCC333333)"\n  4) 0000000000000000000000000000000000000004 "Developer ID Application: Acme, Inc. (EEEE555555)"\n     4 valid identities found\n' >"$home/identities.txt"
  printf '#!/bin/bash\ncase "$1" in find-identity) cat "$HOME/identities.txt" ;; find-certificate) cat "$HOME/certs.pem" ;; esac\n' >"$home/.local/bin/security"; chmod +x "$home/.local/bin/security"
  env HOME="$home" macup_run check --only check.certs --no-color </dev/null >"$work/crt.out" 2>&1
  grep -q 'Signing certificates that expire within 30 days: 2 ' "$work/crt.out" && grep -q 'Apple Development: Soon Gone' "$work/crt.out" && grep -q 'Acme, Inc.' "$work/crt.out" && ! grep -qE 'Long Lived|Web Server|Renewed|No Key' "$work/crt.out" \
    && pass "signing certificates: only an identity whose newest certificate expires soon is named" || { fail "signing certificates"; cat "$work/crt.out"; }
fi

# --- crashes, sharing, PATH: said in a check
home="$work/misc"; DR="$home/Library/Logs/DiagnosticReports"; mkdir -p "$DR/Retired" "$home/.config/macup" "$home/.local/bin"; printf 'language = en\n' >"$home/.config/macup/config"
mkips(){ # dir name bug_type days-ago procPath [file-prefix]
  python3 - "$@" <<'PY'
import datetime, json, sys, uuid
folder, name, bug, ago, path = sys.argv[1:6]; pre = sys.argv[6] if len(sys.argv) > 6 else ""
ts = (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=float(ago))).strftime("%Y-%m-%d %H:%M:%S.00 +0000")
head = {"app_name": name, "timestamp": ts, "bug_type": bug, "name": name}
open("%s/%s%s-%s.ips" % (folder, pre, name, uuid.uuid4().hex[:8]), "w").write(json.dumps(head) + "\n" + json.dumps({"procPath": path, "procName": name}).replace("/", "\\/") + "\n")
PY
}
for index in 1 2; do mkips "$DR" "Crashy App" 309 1 "/Applications/Crashy App.app/Contents/MacOS/Crashy App"; mkips "$DR/Retired" "Crashy App" 309 2 "/Applications/Crashy App.app/Contents/MacOS/Crashy App"; done
for index in 1 2 3; do mkips "$DR" "Crashy App" 309 1 "/Applications/Crashy App.app/Contents/MacOS/Crashy App" ExcUserFault_; done
for index in 1 2 3; do mkips "$DR/Retired" "Old App" 309 20 "/Applications/Old App.app/Contents/MacOS/Old App"; mkips "$DR" "Hang App" 385 1 "/Applications/Hang App.app/Contents/MacOS/Hang App"; done
for index in 1 2 3; do mkips "$DR" "Home App" 309 3 "$home/Applications/Home App.app/Contents/MacOS/Home App"; done
for index in 1 2 3 4 5; do mkips "$DR/Retired" "sysd" 309 1 "/System/Library/CoreServices/sysd"; done
for index in 1 2 3; do printf 'Process: Legacy App [1]\nPath: /Applications/Legacy App.app/Contents/MacOS/Legacy App\n' >"$DR/Legacy App_2026-11-1$index-100000_Mac.crash"; done
env HOME="$home" macup_run check --only check.crashes --no-color </dev/null >"$work/misc.out" 2>&1
grep -E 'Crashed 3 or more times in the last 7 days: ' "$work/misc.out" | grep -q 'Crashy App ×4' && grep -E 'Crashed 3' "$work/misc.out" | grep -q 'Home App ×3' && grep -E 'Crashed 3' "$work/misc.out" | grep -q 'Legacy App ×3' && ! grep -qE 'Old App|Hang App|sysd' "$work/misc.out" \
  && pass "crashes: Retired counted, ExcUserFault_, other report types and old crashes skipped, only apps named" || { fail "crashes"; cat "$work/misc.out"; }
grep -q 'macOS system processes crashed 5 times this week (not yours to fix; Apple gets the reports)$' "$work/misc.out" && ! grep -q "$home" "$work/misc.out" && pass "crashes: system processes are a count" || { fail "crash system count"; cat "$work/misc.out"; }
FAKE_SHARING='	"com.openssh.sshd" => enabled' env HOME="$home" macup_run check --only check.security --no-color </dev/null >"$work/misc.out" 2>&1
grep -q 'Remote Login (SSH) is on' "$work/misc.out" && ! grep -qE 'Screen Sharing|Remote Management' "$work/misc.out" && pass "sharing: Remote Login that is on is said" || { fail "sharing"; cat "$work/misc.out"; }
FAKE_SHARING='	"com.apple.RemoteDesktop.agent" => enabled' env HOME="$home" macup_run check --only check.security --no-color </dev/null >"$work/misc.out" 2>&1
grep -q 'Remote Management is on' "$work/misc.out" && pass "sharing: Remote Management that is on is said" || { fail "Remote Management"; cat "$work/misc.out"; }
FAKE_SHARING='	"com.apple.RemoteDesktop.agent" => disabled' FAKE_PROCS=ARDAgent env HOME="$home" macup_run check --only check.security --no-color </dev/null >"$work/misc.out" 2>&1
! grep -q 'Remote Management' "$work/misc.out" && pass "sharing: Remote Management that print-disabled lists as disabled is not said" || { fail "Remote Management disabled"; cat "$work/misc.out"; }
FAKE_PROCS=ARDAgent env HOME="$home" macup_run check --only check.security --no-color </dev/null >"$work/misc.out" 2>&1
grep -q 'Remote Management is on' "$work/misc.out" && pass "sharing: ARDAgent running without a print-disabled entry is Remote Management" || { fail "Remote Management by process"; cat "$work/misc.out"; }
env HOME="$home" PATH="$PATH:$home/no/such/dir:/macup/no/such/system/dir" macup_run check --only check.commands --no-color </dev/null >"$work/misc.out" 2>&1
grep -q 'PATH names folders that do not exist: ~/no/such/dir ' "$work/misc.out" && pass "PATH: a folder that does not exist is said" || { fail "PATH folders"; cat "$work/misc.out"; }
if [ "$(id -u)" = 0 ]; then
  env HOME="$home" SUDO_USER=me macup_run check --only check.system </dev/null >"$work/misc.out" 2>&1; [ $? = 1 ] && grep -q 'does not need sudo' "$work/misc.out" && pass "sudo macup refuses to run" || fail "sudo macup ran"
fi
# --- MACUP_PATH=keep: macup leaves PATH as it is, so a fake brew wins over the real one (tests, the screenshot generator)
home="$work/kp"; mkdir -p "$home/.config/macup" "$work/kpbin"; printf 'language = en\n' >"$home/.config/macup/config"
printf '#!/bin/bash\necho "$*" >>"$HOME/brew.log"\n' >"$work/kpbin/brew"; chmod +x "$work/kpbin/brew"
env -i HOME="$home" MACUP_PATH=keep PATH="$work/kpbin:/usr/bin:/bin:/usr/sbin:/sbin" MACUP_BUILD="$MACUP_BUILD" ${MACUP_BIN:+MACUP_BIN="$MACUP_BIN"} "$work/bin/macup_run" check --only clean.brew --no-color </dev/null >"$work/kp.out" 2>&1
grep -q 'cleanup' "$home/brew.log" 2>/dev/null && pass "MACUP_PATH=keep: the brew on PATH is the one used" || { fail "MACUP_PATH=keep"; cat "$work/kp.out" | tail -5; }

#!/bin/bash
# Shipping: tools/bump-formula.sh, install.sh, the 2.9 bootstrap and the Swift self-update against a fake GitHub release.
# Nothing reaches the network: a fake curl serves $FAKE_REMOTE/raw/<ref>/<file> for raw.githubusercontent.com and
# $FAKE_REMOTE/releases/<tag>/<file> for release assets, and writes every URL it was asked for to $FAKE_REMOTE/curl.log.
# tests/run.sh calls it; it also runs on its own.
cd "$(dirname "$0")/.." || exit 1
work=$(mktemp -d "${TMPDIR:-/tmp}/macup-shipping.XXXXXX"); trap 'rm -rf "$work"' EXIT
failed=0; pass(){ echo "PASS $*"; }; fail(){ echo "FAIL $*"; failed=1; }
sum256(){ shasum -a 256 "$1" | awk '{print $1}'; }

mkdir -p "$work/bin"
cat >"$work/bin/curl" <<'FAKE'
#!/bin/bash
out=""; url=""
while [ $# -gt 0 ]; do case "$1" in -o) out=$2; shift ;; --max-time|--retry|-z) shift ;; http*) url=$1 ;; esac; shift; done
echo "$url" >>"$FAKE_REMOTE/curl.log"
case "$url" in
  https://raw.githubusercontent.com/*) file="$FAKE_REMOTE/raw/$(printf '%s' "$url" | sed -E 's|^https://raw.githubusercontent.com/[^/]+/[^/]+/||')" ;;
  https://github.com/*/releases/download/*) file="$FAKE_REMOTE/releases/${url#*/releases/download/}" ;;
  *) exit 6 ;;
esac
[ -f "$file" ] || exit 22
case "$url" in *.tar.gz) sleep "${FAKE_SLOW:-0}" ;; esac
if [ -n "$out" ]; then cp "$file" "$out"; else cat "$file"; fi
FAKE
# git answers ls-remote from FAKE_TAGS ("v1.0.0 v2.0.0"), writes what it was asked to git.log and leaves the rest to the real git
cat >"$work/bin/git" <<'FAKE'
#!/bin/bash
echo "git $*" >>"$FAKE_REMOTE/git.log"
case " $* " in *" ls-remote "*) for tag in ${FAKE_TAGS:-}; do [ "${!#}" = "refs/tags/$tag" ] && echo "0000000 refs/tags/$tag"; done; exit 0 ;; esac
exec /usr/bin/git "$@"
FAKE
chmod +x "$work/bin/"*
export PATH="$work/bin:$PATH" FAKE_REMOTE="$work/remote"

# release_asset VERSION FILE…: a release of these files as the release workflow packs them, with its published SHA-256
release_asset(){
  local version=$1 dir="$FAKE_REMOTE/releases/v$1" name="macup-$1-macos-universal.tar.gz"; shift
  rm -rf "$work/pack.$version"; mkdir -p "$dir" "$work/pack.$version"; cp "$@" "$work/pack.$version/"
  COPYFILE_DISABLE=1 tar -czf "$dir/$name" -C "$work/pack.$version" .
  echo "$(sum256 "$dir/$name")  $name" >"$dir/$name.sha256"
}

# --- tools/bump-formula.sh: the formula points at the release asset, only once it exists and matches its SHA-256
tap="$work/tap"; mkdir -p "$tap/Formula" "$FAKE_REMOTE"
formula(){ # DEPENDS_ON [URL SHA256]: a formula shaped like the tap's
  printf 'class Macup < Formula\n  url "%s"\n  sha256 "%s"\n  license "MIT"\n\n%s  def install\n    bin.install "macup"\n  end\nend\n' \
    "${2:-https://example.com/old.tar.gz}" "${3:-$(printf '%064d' 0)}" "${1:+  $1$'\n\n'}" >"$tap/Formula/macup.rb"
}
formula 'depends_on :macos'
git -C "$tap" init -q && git -C "$tap" add . && git -C "$tap" -c user.name=test -c user.email=test@example.com commit -qm init
before=$(cat "$tap/Formula/macup.rb")
bump(){ : >"$FAKE_REMOTE/curl.log"; : >"$FAKE_REMOTE/git.log"; env FAKE_TAGS="${tags-v9.9.9}" tools/bump-formula.sh "$@" 2>&1; }
unchanged(){ [ "$(cat "$tap/Formula/macup.rb")" = "$before" ]; }
asset_url="https://github.com/VitaliiDeveloper/macup/releases/download/v9.9.9/macup-9.9.9-macos-universal.tar.gz"
published="$FAKE_REMOTE/releases/v9.9.9/macup-9.9.9-macos-universal.tar.gz.sha256"

out=$(tags="" bump 9.9.9 "$tap"); rc=$?
[ $rc = 1 ] && grep -q 'tag v9.9.9 is not on origin' <<<"$out" && unchanged && [ ! -s "$FAKE_REMOTE/curl.log" ] \
  && pass "bump-formula: a tag that is not on origin stops it before any download" || fail "bump-formula without a tag (rc=$rc): $out"
out=$(bump 9.9 "$tap"); rc=$?
[ $rc = 1 ] && grep -q usage <<<"$out" && pass "bump-formula: a version that is not X.Y.Z is refused" || fail "bump-formula bad version (rc=$rc): $out"
out=$(bump 9.9.9 "$tap"); rc=$?
[ $rc = 1 ] && grep -q 'no release asset at .*: wait for the release workflow' <<<"$out" && unchanged \
  && pass "bump-formula: no release asset yet, the formula stays" || fail "bump-formula before the asset (rc=$rc): $out"
printf 'fake binary\n' >"$work/macup"; release_asset 9.9.9 "$work/macup"; good_sum=$(cat "$published"); rm "$published"
out=$(bump 9.9.9 "$tap"); rc=$?
[ $rc = 1 ] && grep -q 'no published SHA-256' <<<"$out" && unchanged && pass "bump-formula: the asset without its SHA-256 yet (uploads are one by one), the formula stays" || fail "bump-formula without the .sha256 (rc=$rc): $out"
echo "$(printf '%064d' 1)  macup-9.9.9-macos-universal.tar.gz" >"$published"
out=$(bump 9.9.9 "$tap"); rc=$?
[ $rc = 1 ] && grep -q 'does not match its published SHA-256' <<<"$out" && unchanged \
  && pass "bump-formula: an asset that does not match its published SHA-256 is refused" || fail "bump-formula checksum (rc=$rc): $out"
echo "$good_sum" >"$published"
out=$(bump 9.9.9 "$tap"); rc=$?
[ $rc = 0 ] && grep -qxF "  url \"$asset_url\"" "$tap/Formula/macup.rb" && grep -qx "  sha256 \"${good_sum%% *}\"" "$tap/Formula/macup.rb" \
  && grep -qx '  depends_on macos: :ventura' "$tap/Formula/macup.rb" && ! grep -qx '  depends_on :macos' "$tap/Formula/macup.rb" \
  && [ "$(git -C "$tap" diff --numstat | awk '{print $1+$2}')" = 6 ] && grep -q "^+  sha256 \"${good_sum%% *}\"" <<<"$out" && grep -qx '+  depends_on macos: :ventura' <<<"$out" \
  && grep -q 'commit -m "macup 9.9.9"' <<<"$out" && [ "$(git -C "$tap" rev-list --count HEAD)" = 1 ] && ! grep -qE '^git (-C [^ ]+ )?(commit|push)' "$FAKE_REMOTE/git.log" \
  && [ "$(cat "$FAKE_REMOTE/curl.log")" = "$asset_url"$'\n'"$asset_url.sha256" ] \
  && pass "bump-formula: url and sha256 of the release asset, depends_on :macos becomes macOS 13, the diff shown, nothing committed" || { fail "bump-formula edit (rc=$rc): $out"; cat "$tap/Formula/macup.rb"; }
out=$(bump 9.9.9 "$tap"); rc=$?
[ $rc = 0 ] && grep -q 'already points at v9.9.9' <<<"$out" && pass "bump-formula: running it twice changes nothing" || fail "bump-formula twice (rc=$rc): $out"
out=$(bump --commit 9.9.9 "$tap"); rc=$?
[ $rc = 1 ] && grep -q 'uncommitted changes' <<<"$out" && pass "bump-formula: --commit refuses a tap with other changes" || fail "bump-formula --commit on a dirty tap (rc=$rc): $out"
git -C "$tap" checkout -q -- Formula/macup.rb
out=$(bump --commit 9.9.9 "$tap"); rc=$?
[ $rc = 0 ] && [ "$(git -C "$tap" log -1 --format=%s)" = "macup 9.9.9" ] && [ -z "$(git -C "$tap" status --porcelain)" ] && ! grep -qE '^git (-C [^ ]+ )?push' "$FAKE_REMOTE/git.log" \
  && pass "bump-formula --commit: committed, never pushed" || fail "bump-formula --commit (rc=$rc): $out"
formula "" "$asset_url" "${good_sum%% *}"; formula_before=$(cat "$tap/Formula/macup.rb")
git -C "$tap" -c user.name=test -c user.email=test@example.com commit -qam "no depends_on"
out=$(bump 9.9.9 "$tap"); rc=$?
[ $rc = 0 ] && [ "$(cat "$tap/Formula/macup.rb")" = "${formula_before/$'\n\n'  def install/$'\n\n'  depends_on macos: :ventura$'\n\n'  def install}" ] && grep -qx '+  depends_on macos: :ventura' <<<"$out" \
  && pass "bump-formula: a formula without depends_on gets the macOS 13 limit, and nothing else changes" || { fail "bump-formula, no depends_on (rc=$rc): $out"; cat "$tap/Formula/macup.rb"; }
formula 'depends_on macos: :monterey'; before=$(cat "$tap/Formula/macup.rb")
out=$(bump 9.9.9 "$tap"); rc=$?
[ $rc = 1 ] && grep -q 'names another macOS than "depends_on macos: :ventura": change it by hand' <<<"$out" && unchanged && [ ! -s "$FAKE_REMOTE/curl.log" ] \
  && pass "bump-formula: another macOS limit is not overwritten" || fail "bump-formula, other macOS (rc=$rc): $out"

# --- the bootstrap (the root macup) and the installer against a fake release
cat >"$work/bin/sw_vers" <<'FAKE'
#!/bin/bash
echo "${FAKE_MACOS:-15.1}"
FAKE
cat >"$work/bin/launchctl" <<'FAKE'
#!/bin/bash
echo "$*" >>"$HOME/launchctl.log"
case " ${FAKE_LAUNCHCTL_FAIL:-} " in *" $1 "*) exit 1 ;; esac   # the subcommands that fail
[ "$1" = print ] && [ -n "${FAKE_PROGRAM:-}" ] && printf '\tprogram = %s\n' "$FAKE_PROGRAM"
exit 0
FAKE
chmod +x "$work/bin/sw_vers" "$work/bin/launchctl"
fake_binary(){ # VERSION PATH: stands in for the release binary; says its version, writes down every other run
  printf '#!/bin/bash\n[ "$1" = version ] && { echo "macup %s"; exit 0; }\necho "$0 $*" >>"$HOME/ran.log"\n' "$1" >"$2"; chmod 755 "$2"
}
publish(){ # FILE REF: FILE as raw/<REF>/macup with its macup.sha256, as 2.9 copies and install.sh read them
  mkdir -p "$FAKE_REMOTE/raw/$2"; cp "$1" "$FAKE_REMOTE/raw/$2/macup"; echo "$(sum256 "$1")  macup" >"$FAKE_REMOTE/raw/$2/macup.sha256"
}
rm -rf "$FAKE_REMOTE"; mkdir -p "$FAKE_REMOTE" "$work/asset"
sed 's/^MACUP_VERSION=.*/MACUP_VERSION="9.9.9"/' macup >"$work/bootstrap"; publish "$work/bootstrap" main
fake_binary 9.9.9 "$work/asset/macup"
# 2.9.2 as released, from its tag (CI checks out with tags)
git cat-file -e v2.9.2:macup 2>/dev/null || { echo "FAIL the v2.9.2 tag is not in this checkout: git fetch --tags"; exit 1; }
git show v2.9.2:macup >"$work/macup-2.9.2"
publish "$work/macup-2.9.2" v2.9.2

home="$work/old"; bin="$home/.local/bin"; plist="$home/Library/LaunchAgents/com.vitaliideveloper.macup.plist"
mkdir -p "$bin" "$home/.config/macup" "${plist%/*}" "$home/tmp"; printf 'language = en\n' >"$home/.config/macup/config"
schedule_29="<array><string>/bin/bash</string><string>$bin/macup</string><string>check</string><string>--quiet</string><string>--notify</string></array>"
fresh(){ # FILE: this home as 2.9.2 left it with a weekly schedule, FILE installed
  cp "$1" "$bin/macup"; chmod 755 "$bin/macup"; rm -f "$home/ran.log" "$home/launchctl.log"; : >"$FAKE_REMOTE/curl.log"
  printf '<plist version="1.0">\n<dict>\n  <key>ProgramArguments</key>\n  %s\n</dict>\n</plist>\n' "$schedule_29" >"$plist"
}
run(){ env HOME="$home" TMPDIR="$home/tmp/" FAKE_MACOS="${macos:-15.1}" "$@" </dev/null 2>&1; }
untouched(){ cmp -s "$bin/macup" "$work/bootstrap" && grep -qF "$schedule_29" "$plist" && [ ! -e "$home/launchctl.log" ] \
  && [ -z "$(ls -A "$home/tmp")" ] && [ "$(ls -A "$bin")" = macup ]; }
urls(){ sed 's|^https://raw.githubusercontent.com/VitaliiDeveloper/macup/||; s|^https://github.com/VitaliiDeveloper/macup/releases/download/||' "$FAKE_REMOTE/curl.log" | paste -sd' ' -; }

/bin/bash -n macup && grep -qE '^MACUP_VERSION="[0-9]+\.[0-9]+\.[0-9]+"$' macup && grep -q '^# macup' macup \
  && grep -qE '^LEGACY_VERSION="2\.9\.[0-9]+"' macup && pass "bootstrap: bash -n, the version line 2.9 reads, found by 2.9's rule" || fail "bootstrap: its lines"

# before the tag: 2.9.2 falls back to main, and the bootstrap waits for the release asset
fresh "$work/macup-2.9.2"
out=$(run /bin/bash "$bin/macup" self-update --no-color); rc=$?
[ $rc = 0 ] && grep -q 'macup updated: 2.9.2 → 9.9.9' <<<"$out" && cmp -s "$bin/macup" "$work/bootstrap" && [ "$(urls)" = "main/macup v9.9.9/macup.sha256 main/macup.sha256" ] \
  && pass "2.9.2 self-update before the tag: the bootstrap from main" || { fail "2.9.2 self-update from main (rc=$rc): $out"; urls; }

# before the release asset, each run uses 2.9.2 from a temporary copy and replaces nothing; a stub stands in for 2.9.2
printf '#!/bin/bash\nMACUP_VERSION="2.9.2"\necho "$0 $*" >>"$HOME/ran.log"\nexit 3\n' >"$work/stub-2.9.2"; publish "$work/stub-2.9.2" v2.9.2
asset_sum=v9.9.9/macup-9.9.9-macos-universal.tar.gz.sha256
fresh "$work/bootstrap"; out=$(run /bin/bash "$bin/macup" check --no-color); rc=$?
[ $rc = 3 ] && grep -q 'macup 9.9.9 is not published yet, or the download failed; this run uses macup 2.9.2, and the next one tries again' <<<"$out" \
  && [ "$(wc -l <"$home/ran.log")" -eq 1 ] && grep -qE "^$bin/\.macup-update\.[A-Za-z0-9]+/macup check --no-color$" "$home/ran.log" && untouched \
  && [ "$(urls)" = "$asset_sum v2.9.2/macup.sha256 v2.9.2/macup" ] && pass "bootstrap before the release asset: the command runs on 2.9.2, its status kept, nothing replaced" \
  || { fail "bootstrap before the asset (rc=$rc): $out"; urls; cat "$home/ran.log"; ls -A "$bin"; }
fresh "$work/bootstrap"; out=$(run env XPC_SERVICE_NAME=com.vitaliideveloper.macup /bin/bash "$bin/macup" check --quiet --notify); rc=$?
[ $rc = 3 ] && grep -q 'this run uses macup 2.9.2' <<<"$out" && grep -qE "^$home/tmp/+macup-update\.[A-Za-z0-9]+/macup check --quiet --notify$" "$home/ran.log" && untouched \
  && pass "bootstrap from launchd before the release asset: the check runs on 2.9.2, nothing replaced or reloaded" || { fail "bootstrap from launchd before the asset (rc=$rc): $out"; cat "$home/ran.log"; }
refused=1
for command in self-update "--lang en schedule weekly" uninstall; do
  fresh "$work/bootstrap"; out=$(run /bin/bash "$bin/macup" $command); rc=$?
  [ $rc = 1 ] && grep -q 'macup 9.9.9 is not published yet, or the download failed: https://github.com/.*/v9.9.9/macup-9.9.9-macos-universal.tar.gz. Nothing' <<<"$out" && untouched && [ ! -e "$home/ran.log" ] \
    && [ "$(urls)" = "$asset_sum" ] || { refused=0; echo "  $command (rc=$rc): $out"; }
done
[ $refused = 1 ] && pass "bootstrap before the release asset: self-update, schedule and uninstall, which act on their own file, are not run from a copy" || fail "bootstrap before the asset, commands on their own file"
rm -rf "$FAKE_REMOTE/raw/v2.9.2"; fresh "$work/bootstrap"; out=$(run /bin/bash "$bin/macup" check --no-color); rc=$?
[ $rc = 1 ] && grep -q 'macup 9.9.9 is not published yet, or the download failed: https://github.com/.*/v9.9.9/macup-9.9.9-macos-universal.tar.gz. Nothing changed' <<<"$out" \
  && ! grep -qE 'this run uses|Download failed' <<<"$out" && untouched && [ ! -e "$home/ran.log" ] && pass "bootstrap before the release asset, without 2.9.2 either: it stays and says so" || { fail "bootstrap without both (rc=$rc): $out"; ls -A "$bin"; }
publish "$work/macup-2.9.2" v2.9.2

# in a source checkout the root macup is the tracked bootstrap: it never replaces itself there
checkout="$work/checkout"; mkdir -p "$checkout"; touch "$checkout/Package.swift" "$checkout/build.sh"; cp "$work/bootstrap" "$checkout/macup"; : >"$FAKE_REMOTE/curl.log"
out=$(cd "$checkout" && run /bin/bash ./macup version); rc=$?
[ $rc = 1 ] && [ "$out" = 'This macup is the bootstrap in a source checkout: build the binary with ./build.sh and run .build/debug/macup.' ] && cmp -s "$checkout/macup" "$work/bootstrap" \
  && [ "$(ls -A "$checkout" | wc -l)" -eq 3 ] && [ ! -s "$FAKE_REMOTE/curl.log" ] && pass "bootstrap in a source checkout: refused, nothing downloaded" || fail "bootstrap in a checkout ($rc): $out"

# the release: 2.9.2 takes the bootstrap from the tag
publish "$work/bootstrap" v9.9.9; release_asset 9.9.9 "$work/asset/macup"
fresh "$work/macup-2.9.2"
out=$(run /bin/bash "$bin/macup" self-update --no-color); rc=$?
[ $rc = 0 ] && grep -q 'macup updated: 2.9.2 → 9.9.9' <<<"$out" && cmp -s "$bin/macup" "$work/bootstrap" && [ "$(urls)" = "main/macup v9.9.9/macup.sha256 v9.9.9/macup" ] \
  && pass "2.9.2 self-update: the bootstrap from the tag, checked by its SHA-256" || { fail "2.9.2 self-update from the tag (rc=$rc): $out"; urls; }

# the schedule's own run: the check runs from a download, the file and the loaded job stay as they are
out=$(run env XPC_SERVICE_NAME=com.vitaliideveloper.macup /bin/bash "$bin/macup" check --quiet --notify); rc=$?
[ $rc = 0 ] && grep -q 'This scheduled check runs macup 9.9.9 from a temporary copy' <<<"$out" && grep -qE "^$home/tmp/+macup-update\.[A-Za-z0-9]+/macup check --quiet --notify$" "$home/ran.log" \
  && untouched && pass "bootstrap from launchd: the check runs from a download, nothing replaced or reloaded" || { fail "bootstrap from launchd (rc=$rc): $out"; cat "$home/ran.log"; }

# a run from a terminal: replaced by rename, the schedule points at the binary and is loaded again, then the command runs
rm -f "$home/ran.log"
out=$(run /bin/bash "$bin/macup" check --no-color); rc=$?
[ $rc = 0 ] && cmp -s "$bin/macup" "$work/asset/macup" && [ "$(cat "$home/ran.log")" = "$bin/macup check --no-color" ] && grep -q "macup 9.9.9 is installed: $bin/macup" <<<"$out" \
  && grep -qF "<array><string>$bin/macup</string><string>check</string><string>--quiet</string><string>--notify</string></array>" "$plist" \
  && [ "$(cat "$home/launchctl.log")" = "bootout gui/$(id -u)/com.vitaliideveloper.macup"$'\n'"bootstrap gui/$(id -u) $plist" ] && [ "$(ls -A "$bin")" = macup ] \
  && pass "bootstrap: replaced by the release binary, the 2.9 schedule rewritten and reloaded, the command run" || { fail "bootstrap swap (rc=$rc): $out"; cat "$plist" "$home/launchctl.log"; ls -A "$bin"; }

# nothing changes when the download is wrong
corrupt(){ # what to check, then the asset's files
  local what=$1; shift; fresh "$work/bootstrap"; release_asset 9.9.9 "$@"; out=$(run /bin/bash "$bin/macup" version); rc=$?
  [ $rc = 1 ] && untouched && grep -q "$what" <<<"$out" && [ "$(grep -c 'macos-universal.tar.gz$' "$FAKE_REMOTE/curl.log")" = 1 ]
}
mkdir -p "$work/wrong"; fake_binary 9.9.8 "$work/wrong/macup"
corrupt 'looks broken; nothing changed' "$work/wrong/macup" && pass "bootstrap: a binary that is not this version is refused" || fail "bootstrap: wrong version ($rc): $out"
mkdir -p "$work/loop"; cp "$work/bootstrap" "$work/loop/macup"
corrupt 'looks broken; nothing changed' "$work/loop/macup" && pass "bootstrap: an asset that is a bootstrap is never run" || fail "bootstrap: bootstrap as the asset ($rc): $out"
release_asset 9.9.9 "$work/asset/macup"; echo "$(printf '%064d' 2)  x" >"$FAKE_REMOTE/releases/v9.9.9/macup-9.9.9-macos-universal.tar.gz.sha256"
fresh "$work/bootstrap"; out=$(run /bin/bash "$bin/macup" version); rc=$?
[ $rc = 1 ] && untouched && grep -q 'does not match its published checksum' <<<"$out" && pass "bootstrap: a checksum mismatch changes nothing" || fail "bootstrap: checksum ($rc): $out"
release_asset 9.9.9 "$work/asset/macup"
fresh "$work/bootstrap"; chmod 555 "$bin"; out=$(run /bin/bash "$bin/macup" version); rc=$?; chmod 755 "$bin"
[ $rc = 1 ] && untouched && grep -q "Couldn't write $bin/macup" <<<"$out" && [ ! -s "$FAKE_REMOTE/curl.log" ] && pass "bootstrap: a folder it cannot write is said" || fail "bootstrap: read-only folder ($rc): $out"

# `bash macup` from another folder: bash found it in PATH, and that file is the one replaced
fresh "$work/bootstrap"; out=$(cd "$home" && run env PATH="$bin:$PATH" /bin/bash macup version); rc=$?
[ $rc = 0 ] && cmp -s "$bin/macup" "$work/asset/macup" && [ ! -e "$home/macup" ] && grep -qx 'macup 9.9.9' <<<"$out" \
  && pass "bootstrap run as bash macup through PATH: the installed file is replaced" || fail "bootstrap through PATH ($rc): $out"

# Homebrew's file is Homebrew's; a Mac older than macOS 13 keeps the last 2.9
cellar="$home/brew/Cellar/macup/9.9.9/bin"; mkdir -p "$cellar" "$home/brew/bin"; cp "$work/bootstrap" "$cellar/macup"; ln -sf ../Cellar/macup/9.9.9/bin/macup "$home/brew/bin/macup"
: >"$FAKE_REMOTE/curl.log"; printf 'language = uk\n' >"$home/.config/macup/config"
out=$(run /bin/bash "$home/brew/bin/macup" version); rc=$?; printf 'language = en\n' >"$home/.config/macup/config"
[ $rc = 1 ] && [ "$out" = "macup встановлено через Homebrew. Онови його так: brew upgrade macup" ] && cmp -s "$cellar/macup" "$work/bootstrap" && [ ! -s "$FAKE_REMOTE/curl.log" ] \
  && pass "bootstrap in a Homebrew Cellar: brew upgrade macup, in the configured language" || fail "bootstrap under Homebrew ($rc): $out"
fresh "$work/bootstrap"; out=$(macos=12.7.4 run /bin/bash "$bin/macup" version); rc=$?
[ $rc = 0 ] && cmp -s "$bin/macup" "$work/macup-2.9.2" && grep -qx 'macup 2.9.2' <<<"$out" && grep -q 'macup 9.9.9 needs macOS 13 or later; this Mac keeps macup 2.9.2' <<<"$out" \
  && [ "$(urls)" = "v2.9.2/macup.sha256 v2.9.2/macup" ] && grep -qF "$schedule_29" "$plist" && pass "bootstrap on macOS 12: the last 2.9 instead" || { fail "bootstrap on macOS 12 ($rc): $out"; urls; }
fresh "$work/bootstrap"; out=$(macos=12.7.4 run /bin/bash "$bin/macup" self-update --no-color); rc=$?
[ $rc = 0 ] && cmp -s "$bin/macup" "$work/macup-2.9.2" && ! grep -q 'macup updated' <<<"$out" && [ "$(urls)" = "v2.9.2/macup.sha256 v2.9.2/macup" ] \
  && pass "bootstrap on macOS 12 asked to self-update: 2.9 stays, no update back to the bootstrap" || { fail "bootstrap on macOS 12, self-update ($rc): $out"; urls; }

# the real binary, packed as the release workflow packs it
real=${MACUP_BIN:-$PWD/.build/debug/macup}
if [ -f "$real" ]; then
  version=$("$real" version | sed -n 's/^macup //p'); mkdir -p "$work/real"; cp "$real" "$work/real/macup"; release_asset "$version" "$work/real/macup"
  sed "s/^MACUP_VERSION=.*/MACUP_VERSION=\"$version\"/" macup >"$work/bootstrap-real"
  fresh "$work/bootstrap-real"; out=$(run /bin/bash "$bin/macup" version); rc=$?
  [ $rc = 0 ] && cmp -s "$bin/macup" "$real" && grep -qx "macup $version" <<<"$out" && pass "bootstrap: replaced by the real binary, which runs" || fail "bootstrap with the real binary ($rc): $out"
else echo "SKIP bootstrap with the real binary: none at $real"; fi

# install.sh as `curl | bash` gets: the bootstrap from the tag, which finishes the install; an older copy goes
ihome="$work/inst"; mkdir -p "$ihome/.npm-global/bin"; printf '\317\372\355\376\n# macup\nMACUP_VERSION="9.9.8"\n' >"$ihome/.npm-global/bin/macup"
install_remote(){ env HOME="$ihome" TMPDIR="$ihome/" MACUP_PREFIX="$ihome/.local/bin" FAKE_MACOS=15.1 /bin/bash -s -- --yes --lang en <install.sh 2>&1; }
release_asset 9.9.9 "$work/asset/macup"; rm -rf "$FAKE_REMOTE/releases/v9.9.9"
mkdir -p "$ihome/.local/bin"; cp "$work/macup-2.9.2" "$ihome/.local/bin/macup"
: >"$FAKE_REMOTE/curl.log"; out=$(install_remote); rc=$?
[ $rc = 1 ] && grep -q 'is not published yet' <<<"$out" && grep -q 'run the installer again in a few minutes' <<<"$out" && cmp -s "$ihome/.local/bin/macup" "$work/macup-2.9.2" \
  && ! grep -q 'this run uses' <<<"$out" && ! grep -q v2.9.2 "$FAKE_REMOTE/curl.log" \
  && [ "$(ls -A "$ihome/.local/bin")" = macup ] && pass "install.sh before the release asset: says so, the copy installed before keeps working" || { fail "install.sh before the asset ($rc): $out"; ls -A "$ihome/.local/bin"; }
release_asset 9.9.9 "$work/asset/macup"
out=$(install_remote); rc=$?
[ $rc = 0 ] && cmp -s "$ihome/.local/bin/macup" "$work/asset/macup" && grep -q 'Installed: macup 9.9.9 → .*/.local/bin/macup$' <<<"$out" && [ ! -e "$ihome/.npm-global/bin/macup" ] \
  && ! grep -qE 'Finishing the update|macup-install|is installed:' <<<"$out" \
  && [ "$(ls -A "$ihome/.local/bin")" = macup ] && pass "install.sh | bash: the release binary through the bootstrap, a 3.0 copy elsewhere removed" || { fail "install.sh remote ($rc): $out"; ls -A "$ihome/.local/bin"; }

# from a checkout: the binary built last, over one that has already run
newest=$PWD/.build/release/macup; [ "$PWD/.build/debug/macup" -nt "$newest" ] && newest=$PWD/.build/debug/macup
older=$PWD/.build/debug/macup; [ "$newest" = "$older" ] && older=$PWD/.build/release/macup
if [ -f "$newest" ] && [ -f "$older" ] && ! cmp -s "$newest" "$older"; then
  lhome="$work/local"; mkdir -p "$lhome/.local/bin"; cp "$older" "$lhome/.local/bin/macup"; env HOME="$lhome" "$lhome/.local/bin/macup" version >/dev/null
  env HOME="$lhome" MACUP_PREFIX="$lhome/.local/bin" /bin/bash ./install.sh --yes --lang en </dev/null >"$work/local.out" 2>&1; rc=$?
  [ $rc = 0 ] && cmp -s "$lhome/.local/bin/macup" "$newest" && env HOME="$lhome" "$lhome/.local/bin/macup" version >/dev/null && [ "$(ls -A "$lhome/.local/bin")" = macup ] \
    && pass "install.sh from a checkout: the binary built last, over one that ran" || { fail "install.sh local ($rc)"; cat "$work/local.out"; }
else echo "SKIP install.sh from a checkout: needs two different builds in .build/release and .build/debug"; fi

# --- the Swift build's self-update and its repair of a 2.9 schedule, on the real binary
if [ -f "$real" ]; then
  current=$("$real" version | sed -n 's/^macup //p')
  shome="$work/swift"; sbin="$shome/bin"; splist="$shome/Library/LaunchAgents/com.vitaliideveloper.macup.plist"; asset_name=macup-9.9.9-macos-universal.tar.gz
  mkdir -p "$shome/.config/macup" "${splist%/*}" "$shome/links"; printf 'language = en\n' >"$shome/.config/macup/config"; ln -sf "$sbin/macup" "$shome/links/macup"
  sfresh(){ chmod 755 "$sbin" 2>/dev/null; rm -rf "$sbin" "$splist" "$shome/launchctl.log" "$shome/Library/Application Support/macup/schedule_checked"; mkdir -p "$sbin"; cp "$real" "$sbin/macup"; : >"$FAKE_REMOTE/curl.log"; }
  srun(){ env HOME="$shome" MACUP_PATH=keep "$@" </dev/null 2>&1; }
  update(){ sfresh; srun "${1:-$sbin/macup}" self-update --no-color; }
  kept(){ cmp -s "$sbin/macup" "$real" && [ "$(ls -A "$sbin")" = macup ] && [ ! -e "$shome/launchctl.log" ]; }
  publish "$work/bootstrap" main; rm -rf "$FAKE_REMOTE/releases/v9.9.9"
  out=$(update); rc=$?
  [ $rc = 1 ] && [ "$out" = "Download failed: https://github.com/VitaliiDeveloper/macup/releases/download/v9.9.9/$asset_name" ] && kept \
    && pass "self-update (Swift): no release asset yet, nothing changed" || fail "self-update (Swift) before the asset ($rc): $out"
  release_asset 9.9.9 "$work/asset/macup"
  out=$(update); rc=$?
  [ $rc = 0 ] && [ "$out" = "macup updated: $current → 9.9.9" ] && cmp -s "$sbin/macup" "$work/asset/macup" && [ "$(ls -A "$sbin")" = macup ] \
    && [ "$(urls)" = "main/macup v9.9.9/$asset_name.sha256 v9.9.9/$asset_name" ] && pass "self-update (Swift): the release asset, checked, renamed over the binary" || { fail "self-update (Swift) ($rc): $out"; urls; }
  out=$(update "$shome/links/macup"); rc=$?
  [ $rc = 0 ] && cmp -s "$sbin/macup" "$work/asset/macup" && [ -L "$shome/links/macup" ] && pass "self-update (Swift) through a symlink: the file it points at is replaced" || fail "self-update (Swift) through a symlink ($rc): $out"
  printf '#!/bin/bash\nMACUP_VERSION="%s"\n' "$current" >"$work/main-current"; publish "$work/main-current" main
  out=$(update); rc=$?; publish "$work/bootstrap" main
  [ $rc = 0 ] && [ "$out" = "macup $current is already the latest." ] && kept && [ "$(urls)" = main/macup ] && pass "self-update (Swift): already the latest, no download" || fail "self-update (Swift), latest ($rc): $out"
  srefused(){ # what it says, then the asset's files
    local what=$1; shift; release_asset 9.9.9 "$@"; out=$(update); rc=$?
    [ $rc = 1 ] && [ "$out" = "$what" ] && kept && [ "$(grep -c 'macos-universal.tar.gz$' "$FAKE_REMOTE/curl.log")" = 1 ]; }
  srefused 'The downloaded file looks broken; nothing changed.' "$work/wrong/macup" && pass "self-update (Swift): a binary that is not this version is refused" || fail "self-update (Swift): wrong version ($rc): $out"
  srefused 'The downloaded file looks broken; nothing changed.' "$work/loop/macup" && pass "self-update (Swift): a bootstrap as the asset is never run" || fail "self-update (Swift): bootstrap as the asset ($rc): $out"
  release_asset 9.9.9 "$work/asset/macup"; echo "$(printf '%064d' 3)  x" >"$FAKE_REMOTE/releases/v9.9.9/$asset_name.sha256"
  out=$(update); rc=$?
  [ $rc = 1 ] && [ "$out" = 'The downloaded file does not match its published checksum; nothing changed.' ] && kept && pass "self-update (Swift): a checksum mismatch changes nothing" || fail "self-update (Swift): checksum ($rc): $out"
  release_asset 9.9.9 "$work/asset/macup"
  sfresh; chmod 555 "$sbin"; out=$(srun "$sbin/macup" self-update --no-color); rc=$?; chmod 755 "$sbin"
  [ $rc = 1 ] && [ "$out" = "Couldn't write $(cd "$sbin" && pwd -P)/macup" ] && kept && [ "$(urls)" = main/macup ] && pass "self-update (Swift): a folder it cannot write is said" || fail "self-update (Swift): read-only folder ($rc): $out"
  sfresh; env HOME="$shome" MACUP_PATH=keep FAKE_SLOW=3 "$sbin/macup" self-update --no-color </dev/null >"$work/term.out" 2>&1 & pid=$!
  sleep 1; kill -TERM $pid; wait $pid; rc=$?
  [ $rc = 1 ] && kept && pass "self-update (Swift) stopped during the download: nothing changed, nothing left next to the binary" || { fail "self-update (Swift) stopped ($rc)"; ls -A "$sbin"; }
  scellar="$shome/brew/Cellar/macup/9.9.9/bin"; mkdir -p "$scellar" "$shome/brew/bin"; cp "$real" "$scellar/macup"; ln -sf ../Cellar/macup/9.9.9/bin/macup "$shome/brew/bin/macup"
  out=$(update "$shome/brew/bin/macup"); rc=$?
  [ $rc = 0 ] && [ "$out" = 'macup was installed with Homebrew. Update it with: brew upgrade macup' ] && cmp -s "$scellar/macup" "$real" && [ ! -s "$FAKE_REMOTE/curl.log" ] \
    && pass "self-update (Swift) in a Homebrew Cellar: brew upgrade macup, no download" || fail "self-update (Swift) under Homebrew ($rc): $out"

  # the first run of the binary: a 2.9 schedule that names it loses /bin/bash and is loaded again, from a terminal only
  schedule29(){ printf '<plist version="1.0">\n<dict>\n  <key>ProgramArguments</key>\n  <array><string>/bin/bash</string><string>%s</string><string>check</string></array>\n</dict>\n</plist>\n' "$1" >"$splist"; }
  reloaded="bootout gui/$(id -u)/com.vitaliideveloper.macup"$'\n'"bootstrap gui/$(id -u) $splist"
  for named in "$sbin/macup" "$shome/links/macup"; do
    sfresh; schedule29 "$named"; out=$(srun "$sbin/macup" version); rc=$?
    [ $rc = 0 ] && [ "$out" = "macup $current" ] && grep -qF "<array><string>$named</string><string>check</string></array>" "$splist" && [ "$(cat "$shome/launchctl.log")" = "$reloaded" ] \
      && [ "$(ls -A "${splist%/*}")" = com.vitaliideveloper.macup.plist ] && [ "$(stat -f %Lp "$splist")" = 644 ] \
      && pass "first run (Swift): the 2.9 schedule of $(basename "$(dirname "$named")")/macup runs the binary, loaded again" || { fail "first run (Swift), 2.9 schedule of $named ($rc): $out"; cat "$splist" "$shome/launchctl.log"; }
  done
  sfresh; schedule29 "$sbin/macup"; out=$(srun env XPC_SERVICE_NAME=com.vitaliideveloper.macup "$sbin/macup" version); rc=$?
  [ $rc = 0 ] && grep -qF '<string>/bin/bash</string>' "$splist" && [ ! -e "$shome/launchctl.log" ] && pass "first run (Swift) started by launchd: the schedule is left alone" || fail "first run (Swift) from launchd ($rc): $out"
  sfresh; cp "$real" "$shome/other"; schedule29 "$shome/other"; out=$(srun "$sbin/macup" version); rc=$?
  [ $rc = 0 ] && grep -qF '<string>/bin/bash</string>' "$splist" && [ ! -e "$shome/launchctl.log" ] && pass "first run (Swift): a schedule of another file is left alone" || fail "first run (Swift), other file ($rc): $out"
  sfresh; schedule29 "$sbin/macup"; sed -i '' 's|<string>/bin/bash</string>||' "$splist"; cp "$splist" "$work/splist"
  out=$(srun env FAKE_PROGRAM=/bin/bash "$sbin/macup" version); rc=$?
  [ $rc = 0 ] && cmp -s "$splist" "$work/splist" && [ "$(cat "$shome/launchctl.log")" = "print gui/$(id -u)/com.vitaliideveloper.macup"$'\n'"$reloaded" ] \
    && pass "first run (Swift): a loaded job that still runs /bin/bash is loaded again" || { fail "first run (Swift), loaded job ($rc): $out"; cat "$shome/launchctl.log"; }
  rm -f "$shome/launchctl.log"; srun env FAKE_PROGRAM="$sbin/macup" "$sbin/macup" version >/dev/null; srun "$sbin/macup" version >/dev/null
  [ "$(cat "$shome/launchctl.log")" = "print gui/$(id -u)/com.vitaliideveloper.macup" ] && pass "first run (Swift): a right schedule is looked at once" || fail "first run (Swift), right schedule: $(cat "$shome/launchctl.log")"
  sfresh; schedule29 "$sbin/macup"; sed -i '' 's|<string>/bin/bash</string>||' "$splist"
  srun env FAKE_LAUNCHCTL_FAIL=print "$sbin/macup" version >/dev/null; srun env FAKE_LAUNCHCTL_FAIL=print "$sbin/macup" version >/dev/null
  [ "$(cat "$shome/launchctl.log")" = "print gui/$(id -u)/com.vitaliideveloper.macup"$'\n'"print gui/$(id -u)/com.vitaliideveloper.macup" ] && [ ! -e "$shome/Library/Application Support/macup/schedule_checked" ] \
    && pass "first run (Swift): a launchctl print that fails proves nothing, the next run looks again" || fail "first run (Swift), print fails: $(cat "$shome/launchctl.log")"
  for lang in en uk; do
    sfresh; schedule29 "$sbin/macup"; printf 'language = %s\n' "$lang" >"$shome/.config/macup/config"
    out=$(env HOME="$shome" MACUP_PATH=keep FAKE_LAUNCHCTL_FAIL="bootstrap load" "$sbin/macup" version </dev/null 2>"$work/reload.err"); rc=$?
    message=$([ $lang = uk ] && echo 'launchd не прийняв оновлений розклад; він запрацює після наступного входу в систему.' || echo 'launchd did not take the updated schedule; it applies after the next login.')
    [ $rc = 0 ] && [ "$out" = "macup $current" ] && [ "$(cat "$work/reload.err")" = "$message" ] && grep -qF "<array><string>$sbin/macup</string>" "$splist" \
      && [ "$(grep -c '^bootstrap ' "$shome/launchctl.log")" = 2 ] && grep -q '^load -w ' "$shome/launchctl.log" \
      && pass "first run (Swift): a reload launchd refuses is said on stderr ($lang)" || { fail "first run (Swift), reload refused ($lang, $rc): $out"; cat "$work/reload.err" "$shome/launchctl.log"; }
  done
  printf 'language = en\n' >"$shome/.config/macup/config"
  sfresh; schedule29 "$sbin/macup"; sed -i '' 's|<string>/bin/bash</string>||' "$splist"; srun env FAKE_PROGRAM="$sbin/macup" "$sbin/macup" version >/dev/null
  rm -f "$shome/launchctl.log"; touch "$splist"; srun "$sbin/macup" version >/dev/null
  [ "$(cat "$shome/launchctl.log")" = "print gui/$(id -u)/com.vitaliideveloper.macup" ] && pass "first run (Swift): a changed schedule is looked at again" || fail "first run (Swift), changed schedule: $(cat "$shome/launchctl.log" 2>/dev/null)"

  # schedule from a relative path names the absolute one; a launchctl that refuses leaves no plist
  sfresh; out=$(cd "$sbin" && srun ./macup schedule weekly --no-color); rc=$?
  [ $rc = 0 ] && grep -qF "<array><string>$(cd "$sbin" && pwd -P)/macup</string><string>check</string>" "$splist" && pass "schedule (Swift) run as ./macup: the absolute path" || { fail "schedule (Swift) relative ($rc): $out"; cat "$splist"; }
  sfresh; out=$(srun env FAKE_LAUNCHCTL_FAIL="bootstrap load" "$sbin/macup" schedule daily --no-color); rc=$?
  [ $rc = 1 ] && [ "$out" = 'launchd did not accept the schedule; nothing changed.' ] && [ ! -e "$splist" ] && pass "schedule (Swift): launchd refuses, no plist left" || fail "schedule (Swift), launchd refuses ($rc): $out"
else echo "SKIP self-update and the schedule repair of the Swift build: no binary at $real"; fi

echo; [ $failed = 0 ] && echo "shipping: ALL PASS" || { echo "shipping: SOME FAILED"; exit 1; }

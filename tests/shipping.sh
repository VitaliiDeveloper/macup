#!/bin/bash
# Shipping: tools/bump-formula.sh against a fake GitHub release. Nothing reaches the network: a fake curl serves
# $FAKE_REMOTE/raw/<ref>/<file> for raw.githubusercontent.com and $FAKE_REMOTE/releases/<tag>/<file> for release assets,
# and writes every URL it was asked for to $FAKE_REMOTE/curl.log. tests/run.sh calls it; it also runs on its own.
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
if [ -n "$out" ]; then cp "$file" "$out"; else cat "$file"; fi
FAKE
# git answers ls-remote from FAKE_TAGS ("v1.0.0 v2.0.0") and leaves everything else to the real git
cat >"$work/bin/git" <<'FAKE'
#!/bin/bash
case " $* " in *" ls-remote "*) for tag in ${FAKE_TAGS:-}; do [ "${!#}" = "refs/tags/$tag" ] && echo "0000000 refs/tags/$tag"; done; exit 0 ;; esac
exec /usr/bin/git "$@"
FAKE
chmod +x "$work/bin/"*
export PATH="$work/bin:$PATH" FAKE_REMOTE="$work/remote"

# release_asset VERSION FILE…: a release of these files as the release workflow packs them, with its published SHA-256
release_asset(){
  local version=$1 dir="$FAKE_REMOTE/releases/v$1" name="macup-$1-macos-universal.tar.gz"; shift
  mkdir -p "$dir" "$work/pack.$version"; cp "$@" "$work/pack.$version/"
  COPYFILE_DISABLE=1 tar -czf "$dir/$name" -C "$work/pack.$version" .
  echo "$(sum256 "$dir/$name")  $name" >"$dir/$name.sha256"
}

# --- tools/bump-formula.sh: the formula points at the release asset, only once it exists and matches its SHA-256
tap="$work/tap"; mkdir -p "$tap/Formula" "$FAKE_REMOTE"
printf 'class Macup < Formula\n  url "https://example.com/old.tar.gz"\n  sha256 "%064d"\n  def install\n    bin.install "macup"\n  end\nend\n' 0 >"$tap/Formula/macup.rb"
git -C "$tap" init -q && git -C "$tap" add . && git -C "$tap" -c user.name=test -c user.email=test@example.com commit -qm init
before=$(cat "$tap/Formula/macup.rb")
bump(){ env FAKE_TAGS="${tags-v9.9.9}" tools/bump-formula.sh "$@" 2>&1; }
asset_url="https://github.com/VitaliiDeveloper/macup/releases/download/v9.9.9/macup-9.9.9-macos-universal.tar.gz"

out=$(bump 9.9.9 "$tap"); rc=$?
[ $rc = 1 ] && grep -q 'no release asset at .*: wait for the release workflow' <<<"$out" && [ "$(cat "$tap/Formula/macup.rb")" = "$before" ] \
  && pass "bump-formula: no release asset yet, the formula stays" || fail "bump-formula before the asset (rc=$rc): $out"
printf 'fake binary\n' >"$work/macup"; release_asset 9.9.9 "$work/macup"
out=$(tags="" bump 9.9.9 "$tap"); rc=$?
[ $rc = 1 ] && grep -q 'tag v9.9.9 is not on origin' <<<"$out" && [ "$(cat "$tap/Formula/macup.rb")" = "$before" ] \
  && pass "bump-formula: no tag, the formula stays" || fail "bump-formula without a tag (rc=$rc): $out"
good_sum=$(cat "$FAKE_REMOTE/releases/v9.9.9/macup-9.9.9-macos-universal.tar.gz.sha256")
echo "$(printf '%064d' 1)  macup-9.9.9-macos-universal.tar.gz" >"$FAKE_REMOTE/releases/v9.9.9/macup-9.9.9-macos-universal.tar.gz.sha256"
out=$(bump 9.9.9 "$tap"); rc=$?
[ $rc = 1 ] && grep -q 'does not match its published SHA-256' <<<"$out" && [ "$(cat "$tap/Formula/macup.rb")" = "$before" ] \
  && pass "bump-formula: an asset that does not match its published SHA-256 is refused" || fail "bump-formula checksum (rc=$rc): $out"
echo "$good_sum" >"$FAKE_REMOTE/releases/v9.9.9/macup-9.9.9-macos-universal.tar.gz.sha256"
: >"$FAKE_REMOTE/curl.log"
out=$(bump --commit 9.9.9 "$tap"); rc=$?
[ $rc = 0 ] && grep -qxF "  url \"$asset_url\"" "$tap/Formula/macup.rb" && grep -qx "  sha256 \"${good_sum%% *}\"" "$tap/Formula/macup.rb" \
  && [ "$(git -C "$tap" log -1 --format=%s)" = "macup 9.9.9" ] && [ -z "$(git -C "$tap" status --porcelain)" ] \
  && [ "$(cat "$FAKE_REMOTE/curl.log")" = "$asset_url"$'\n'"$asset_url.sha256" ] \
  && pass "bump-formula --commit: url and sha256 of the release asset, committed, not pushed" || { fail "bump-formula (rc=$rc): $out"; cat "$tap/Formula/macup.rb"; }

echo; [ $failed = 0 ] && echo "shipping: ALL PASS" || { echo "shipping: SOME FAILED"; exit 1; }

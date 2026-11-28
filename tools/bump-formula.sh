#!/bin/bash
# Points the Homebrew tap's formula at a released macup version: tag check, the release asset (the universal binary that
# .github/workflows/release.yml attaches), its SHA-256 checked against the published one, url + sha256 in Formula/macup.rb,
# and the formula's macOS 13 limit.
#   tools/bump-formula.sh [--commit] VERSION [TAP_DIR]
# It never pushes. Without --commit it only edits the file and prints the commands that finish the release.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SLUG=VitaliiDeveloper/macup
COMMIT=0
if [ "${1:-}" = --commit ]; then COMMIT=1; shift; fi
VERSION=${1:-}; TAP=${2:-$HOME/Documents/Work-Projects/homebrew-macup}
die(){ echo "bump-formula: $*" >&2; exit 1; }
[[ $VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "usage: tools/bump-formula.sh [--commit] VERSION [TAP_DIR]   (VERSION like 3.0.0)"
FORMULA=$TAP/Formula/macup.rb
[ -f "$FORMULA" ] || die "no formula at $FORMULA"
[ "$(grep -c '^  url "' "$FORMULA")" = 1 ] && [ "$(grep -c '^  sha256 "' "$FORMULA")" = 1 ] || die "$FORMULA must have exactly one url and one sha256 line"
# the binary needs macOS 13: without the limit, brew upgrade on macOS 12 installs a macup that cannot start
MACOS='  depends_on macos: :ventura'
if grep -qxF "$MACOS" "$FORMULA"; then HAS_MACOS=1; else HAS_MACOS=0; fi
[ "$HAS_MACOS" = 1 ] || ! grep -q '^  depends_on macos:' "$FORMULA" || die "$FORMULA names another macOS than \"${MACOS#  }\": change it by hand"
[ "$HAS_MACOS" = 1 ] || grep -qE '^  (depends_on |def install)' "$FORMULA" || die "found no place for \"${MACOS#  }\" in $FORMULA (before a depends_on or def install)"
git -C "$TAP" rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "$TAP is not a git repository"
if [ "$COMMIT" = 1 ] && [ -n "$(git -C "$TAP" status --porcelain 2>/dev/null)" ]; then die "$TAP has uncommitted changes; --commit would take them along"; fi

git -C "$ROOT" ls-remote --tags origin "refs/tags/v$VERSION" 2>/dev/null | grep -q . || die "tag v$VERSION is not on origin: push it first"

URL=https://github.com/$SLUG/releases/download/v$VERSION/macup-$VERSION-macos-universal.tar.gz
TMP=$(mktemp -d "${TMPDIR:-/tmp}/bump-formula.XXXXXX"); trap 'rm -rf "$TMP"' EXIT
# downloading the asset is the check that it exists: the release workflow uploads it after CI passes, minutes after the tag
curl -fsSL --retry 2 -o "$TMP/asset.tar.gz" "$URL" || die "no release asset at $URL yet: wait for the release workflow"
[ -s "$TMP/asset.tar.gz" ] || die "the download of $URL is empty"
curl -fsSL --retry 2 -o "$TMP/asset.sha256" "$URL.sha256" || die "no published SHA-256 at $URL.sha256"
if command -v shasum >/dev/null 2>&1; then SHA=$(shasum -a 256 "$TMP/asset.tar.gz" | awk '{print $1}'); else SHA=$(sha256sum "$TMP/asset.tar.gz" | awk '{print $1}'); fi
case "$SHA" in *[!0-9a-f]*|"") die "no SHA-256 computed" ;; esac
[ "${#SHA}" = 64 ] || die "no SHA-256 computed"
[ "$SHA" = "$(awk '{print $1; exit}' "$TMP/asset.sha256")" ] || die "$URL does not match its published SHA-256"

sed -e "s|^  url \".*\"|  url \"$URL\"|" -e "s|^  sha256 \".*\"|  sha256 \"$SHA\"|" "$FORMULA" \
  | awk -v limit="$MACOS" -v has="$HAS_MACOS" '
      $0 == "  depends_on :macos" { if (!has) print limit; has = 1; next }
      !has && /^  depends_on / { print limit; has = 1 }
      !has && /^  def install/ { print limit; print ""; has = 1 }
      { print }
      END { exit !has }' >"$TMP/macup.rb" || die "found no place for \"${MACOS#  }\" in $FORMULA (before a depends_on or def install)"
echo "sha256 $SHA"
cmp -s "$TMP/macup.rb" "$FORMULA" && { echo "$FORMULA already points at v$VERSION"; exit 0; }
cat "$TMP/macup.rb" >"$FORMULA"
git -C "$TAP" --no-pager diff -- Formula/macup.rb

if [ "$COMMIT" = 1 ]; then
  git -C "$TAP" add Formula/macup.rb && git -C "$TAP" commit -q -m "macup $VERSION" || die "commit failed"
  echo "committed in $TAP; not pushed. To publish:"
  echo "  git -C \"$TAP\" push"
else
  echo "Next:"
  echo "  git -C \"$TAP\" add Formula/macup.rb"
  echo "  git -C \"$TAP\" commit -m \"macup $VERSION\""
  echo "  git -C \"$TAP\" push"
fi

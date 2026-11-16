#!/bin/bash
# Points the Homebrew tap's formula at a released macup version: tag check, tarball, SHA-256, url + sha256 in Formula/macup.rb.
#   tools/bump-formula.sh [--commit] VERSION [TAP_DIR]
# It never pushes. Without --commit it only edits the file and prints the commands that finish the release.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SLUG=VitaliiDeveloper/macup
COMMIT=0
if [ "${1:-}" = --commit ]; then COMMIT=1; shift; fi
V=${1:-}; TAP=${2:-$HOME/Documents/Work-Projects/homebrew-macup}
die(){ echo "bump-formula: $*" >&2; exit 1; }
[[ $V =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "usage: tools/bump-formula.sh [--commit] VERSION [TAP_DIR]   (VERSION like 2.9.0)"
F=$TAP/Formula/macup.rb
[ -f "$F" ] || die "no formula at $F"
[ "$(grep -c '^  url "' "$F")" = 1 ] && [ "$(grep -c '^  sha256 "' "$F")" = 1 ] || die "$F must have exactly one url and one sha256 line"
git -C "$TAP" rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "$TAP is not a git repository"
if [ "$COMMIT" = 1 ] && [ -n "$(git -C "$TAP" status --porcelain 2>/dev/null)" ]; then die "$TAP has uncommitted changes; --commit would take them along"; fi

git -C "$ROOT" ls-remote --tags origin "refs/tags/v$V" 2>/dev/null | grep -q . || die "tag v$V is not on origin: push it first"

URL=https://github.com/$SLUG/archive/refs/tags/v$V.tar.gz
TMP=$(mktemp -d "${TMPDIR:-/tmp}/bump-formula.XXXXXX"); trap 'rm -rf "$TMP"' EXIT
curl -fsSL --retry 2 -o "$TMP/src.tar.gz" "$URL" || die "could not download $URL"
[ -s "$TMP/src.tar.gz" ] || die "the download of $URL is empty"
if command -v shasum >/dev/null 2>&1; then SHA=$(shasum -a 256 "$TMP/src.tar.gz" | awk '{print $1}'); else SHA=$(sha256sum "$TMP/src.tar.gz" | awk '{print $1}'); fi
case "$SHA" in *[!0-9a-f]*|"") die "no SHA-256 computed" ;; esac
[ "${#SHA}" = 64 ] || die "no SHA-256 computed"

sed -e "s|^  url \".*\"|  url \"$URL\"|" -e "s|^  sha256 \".*\"|  sha256 \"$SHA\"|" "$F" >"$TMP/macup.rb" || die "could not edit the formula"
echo "sha256 $SHA"
cmp -s "$TMP/macup.rb" "$F" && { echo "$F already points at v$V"; exit 0; }
cat "$TMP/macup.rb" >"$F"
git -C "$TAP" --no-pager diff -- Formula/macup.rb

if [ "$COMMIT" = 1 ]; then
  git -C "$TAP" add Formula/macup.rb && git -C "$TAP" commit -q -m "macup $V" || die "commit failed"
  echo "committed in $TAP; not pushed. To publish:"
  echo "  git -C \"$TAP\" push"
else
  echo "Next:"
  echo "  git -C \"$TAP\" add Formula/macup.rb"
  echo "  git -C \"$TAP\" commit -m \"macup $V\""
  echo "  git -C \"$TAP\" push"
fi

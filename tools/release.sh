#!/bin/bash
# Builds a macup release: the universal binary, stripped and ad hoc signed, packed as macup-VERSION-macos-universal.tar.gz
# next to its SHA-256, then unpacked again and checked as a user gets it. It uploads nothing.
#   tools/release.sh OUTDIR [VERSION]
# VERSION (the release workflow passes the tag without its v) must be the binary's own. CI runs this on every pull request
# without one, so the release path is tested long before a tag exists.
set -eo pipefail
cd "$(dirname "$0")/.."
out=${1:?usage: tools/release.sh OUTDIR [VERSION]}
want=${2:-}
die(){ echo "release: $*" >&2; exit 1; }
sum256(){ shasum -a 256 "$1" | awk '{print $1}'; }

./build.sh >/dev/null
swift build -c release --arch arm64 --arch x86_64
built="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/macup"
version=$("$built" version | sed -n 's/^macup //p')
[ -n "$version" ] || die "$built does not say its version"
[ -z "$want" ] || [ "$want" = "$version" ] || die "the tag says $want, the binary says $version"

# 2.9 copies update themselves from the root macup, the bootstrap: what is checked must be what was committed, name this
# version and match its macup.sha256.
git ls-files --error-unmatch macup macup.sha256 >/dev/null 2>&1 || die "the root macup and macup.sha256 must be committed"
git diff --quiet HEAD -- macup macup.sha256 || die "the root macup differs from the commit"
[ "$(sed -n 's/^MACUP_VERSION="\(.*\)"$/\1/p' macup)" = "$version" ] || die "the root macup does not say MACUP_VERSION=\"$version\""
[ "$(cat macup.sha256)" = "$(sum256 macup)  macup" ] || die "macup.sha256 does not match macup"
/bin/bash -n macup || die "the root macup does not pass bash -n"

work=$(mktemp -d "${TMPDIR:-/tmp}/macup-release.XXXXXX"); trap 'rm -rf "$work"' EXIT
mkdir "$work/stage" "$work/unpacked"
cp "$built" "$work/stage/macup"
strip "$work/stage/macup"
codesign --force --sign - "$work/stage/macup"   # strip drops the linker's signature, and arm64 runs no unsigned code
cp LICENSE "$work/stage/"
name="macup-$version-macos-universal.tar.gz"
mkdir -p "$out"
COPYFILE_DISABLE=1 tar -czf "$out/$name" -C "$work/stage" macup LICENSE
echo "$(sum256 "$out/$name")  $name" >"$out/$name.sha256"

(cd "$out" && shasum -a 256 -c "$name.sha256" >/dev/null) || die "$name does not match its SHA-256"
tar -xzf "$out/$name" -C "$work/unpacked"
binary="$work/unpacked/macup"
for arch in arm64 x86_64; do
  lipo "$binary" -thin "$arch" -output "$work/$arch" || die "no $arch slice"
  codesign -v "$work/$arch" || die "the $arch slice is not signed"
  # install.sh and uninstall recognise macup by these two lines (Env.marker): a literal the compiler must not drop
  LC_ALL=C grep -a -A1 -x '# macup' "$work/$arch" | grep -qx "MACUP_VERSION=\"$version\"" || die "the $arch slice has no marker"
  if arch "-$arch" /usr/bin/true 2>/dev/null; then
    [ "$(arch "-$arch" "$work/$arch" version)" = "macup $version" ] || die "the $arch slice does not run"
  else echo "release: the $arch slice not run: this Mac cannot (no Rosetta)"; fi
done
[ "$("$binary" version)" = "macup $version" ] || die "the packed binary does not run"
echo "$out/$name"
echo "$out/$name.sha256"

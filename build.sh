#!/bin/bash
# Builds the single-file `macup` from src/ (files in name order; `@include` pulls in a file from src/).
# Edit src/, then run ./build.sh. `./build.sh --check` fails if macup is out of date (used by CI).
set -eo pipefail
cd "$(dirname "$0")"
tmp=$(mktemp "${TMPDIR:-/tmp}/macup-build.XXXXXX"); trap 'rm -f "$tmp"' EXIT
for f in src/*.sh; do
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in "@include "*) cat "src/${line#@include }" ;; *) printf '%s\n' "$line" ;; esac
  done <"$f"
done >"$tmp"
/bin/bash -n "$tmp"
if [ "${1:-}" = --check ]; then
  cmp -s "$tmp" macup || { echo "macup is out of date: run ./build.sh and commit it" >&2; exit 1; }
  echo "macup is up to date"
else
  cp "$tmp" macup; chmod 755 macup; echo "built macup ($(wc -l <macup | tr -d ' ') lines)"
fi

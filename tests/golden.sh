#!/bin/bash
# Prints the files a run deletes in a fresh fixture. Usage: golden.sh MACUP FIXDIR [macup args...]
M="$1"; H="$2"; shift 2
"$(dirname "$0")/fixture.sh" "$H"
(cd "$H" && find . \( -type f -o -type l \) | sort) >"$H.before"
# commands that act outside the fake home are always skipped
X='update.*,clean.brew,clean.npm,clean.pnpm,clean.pip,clean.uv,clean.go,clean.sim_unavailable,clean.quicklook,clean.docker,check.*'
env HOME="$H" /bin/bash "$M" "$@" --skip "$X" --no-color </dev/null >"$H.out" 2>&1
(cd "$H" && find . \( -type f -o -type l \) | sort) >"$H.after"
comm -23 "$H.before" "$H.after" | grep -v '^./Library/Logs/macup/' | grep -v '^./Library/Application Support/macup/'

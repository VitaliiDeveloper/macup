#!/bin/bash
# Builds the single-file `macup` from src/. Edit src/, then run ./build.sh.
#   ./build.sh --check   fails if macup or macup.sha256 is out of date (used by tests and CI)
# Translations live in src/i18n/translations.json ({"English": {"uk": …, "ru": …}}) and are
# embedded at build time, so macup itself needs no JSON parser.
# `@py file` embeds a Python file as $MACUP_PY: python3 stays optional and macup stays one file.
set -eo pipefail
cd "$(dirname "$0")"

# bash runs the script top to bottom, so the order matters
ORDER="core help commands translations arguments processes checks updates tools cleanup leftovers cleaners report summary"
for f in src/*.sh; do
  case " $ORDER " in *" $(basename "$f" .sh) "*) ;; *) echo "build.sh: add $f to ORDER" >&2; exit 1 ;; esac
done

i18n(){ # language → "English || translation" lines; fails if any entry lacks the language or a placeholder
  python3 - "$1" src/i18n/translations.json <<'PY'
import json, re, sys
lang, path = sys.argv[1], sys.argv[2]
bad = 0
for en, tr in json.load(open(path, encoding="utf-8")).items():
    t = tr.get(lang)
    if not t:
        print(f"build.sh: no {lang} translation for {en!r}", file=sys.stderr); bad = 1; continue
    if re.findall(r"%[sd%]", en) != re.findall(r"%[sd%]", t):
        print(f"build.sh: {lang} placeholders differ for {en!r}", file=sys.stderr); bad = 1
    if "\n" in en + t or " || " in en + t:
        print(f"build.sh: newline or ' || ' in {en!r}", file=sys.stderr); bad = 1
    print(f"{en} || {t}")
sys.exit(bad)
PY
}

PY_END=MACUP_PY_END
py(){ # Python file → a bash statement that sets MACUP_PY to its text
  python3 -c 'import ast, sys; ast.parse(open(sys.argv[1], encoding="utf-8").read(), sys.argv[1], feature_version=(3, 9))' "$1" || { echo "build.sh: $1 does not compile" >&2; return 1; }
  ! grep -qx "$PY_END" "$1" || { echo "build.sh: $1 has a line $PY_END" >&2; return 1; }
  printf "IFS= read -r -d '' MACUP_PY <<'%s' || :\n" "$PY_END"; awk 1 "$1"; printf '%s\n' "$PY_END"
}

tmp=$(mktemp "${TMPDIR:-/tmp}/macup-build.XXXXXX"); trap 'rm -f "$tmp"' EXIT
for name in $ORDER; do
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in "@i18n "*) i18n "${line#@i18n }" ;; "@py "*) py "${line#@py }" ;; *) printf '%s\n' "$line" ;; esac
  done <"src/$name.sh"
done >"$tmp"
/bin/bash -n "$tmp"

# self-update and the installer compare the download with this before they install it
sum256(){ if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1"; else sha256sum "$1"; fi | awk '{print $1}'; }
SUM="$(sum256 "$tmp")  macup"

if [ "${1:-}" = --check ]; then
  cmp -s "$tmp" macup || { echo "macup is out of date: run ./build.sh and commit it" >&2; exit 1; }
  [ "$(cat macup.sha256 2>/dev/null)" = "$SUM" ] || { echo "macup.sha256 is out of date: run ./build.sh and commit it" >&2; exit 1; }
  echo "macup is up to date"
else
  cp "$tmp" macup; chmod 755 macup; echo "$SUM" >macup.sha256; echo "built macup ($(wc -l <macup | tr -d ' ') lines)"
fi

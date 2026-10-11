#!/bin/bash
# Builds the single-file `macup` from src/. Edit src/, then run ./build.sh.
#   ./build.sh --check   fails if macup is out of date (used by tests and CI)
# Translations live in src/i18n/translations.json ({"English": {"uk": …, "ru": …}}) and are
# embedded at build time, so macup itself needs no JSON parser.
set -eo pipefail
cd "$(dirname "$0")"

# bash runs the script top to bottom, so the order matters
ORDER="core help commands translations arguments checks updates tools cleanup cleaners report summary"
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

tmp=$(mktemp "${TMPDIR:-/tmp}/macup-build.XXXXXX"); trap 'rm -f "$tmp"' EXIT
for name in $ORDER; do
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in "@i18n "*) i18n "${line#@i18n }" ;; *) printf '%s\n' "$line" ;; esac
  done <"src/$name.sh"
done >"$tmp"
/bin/bash -n "$tmp"

if [ "${1:-}" = --check ]; then
  cmp -s "$tmp" macup || { echo "macup is out of date: run ./build.sh and commit it" >&2; exit 1; }
  echo "macup is up to date"
else
  cp "$tmp" macup; chmod 755 macup; echo "built macup ($(wc -l <macup | tr -d ' ') lines)"
fi

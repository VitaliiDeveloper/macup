#!/bin/bash
# Differential harness: the bash build (./macup) and the Swift build (MACUP_BIN, else .build/debug/macup) run the same
# case on the same fake home, and what they leave must be the same after normalising (docs/swift-port-plan.md, "Parity").
#   tests/diff.sh              every case
#   tests/diff.sh tasks help   the cases whose name starts with one of these words
# Every case runs in en, uk and ru (MACUP_LANG), without a terminal and on one (through script). Compared: stdout and
# stderr together as macup writes them (--json included), the exit status, the newest report, the files in the fake home.
cd "$(dirname "$0")/.." || exit 1
W=$(mktemp -d "${TMPDIR:-/tmp}/macup-diff.XXXXXX"); trap 'rm -rf "$W"' EXIT
export MACUP_BIN=${MACUP_BIN:-$PWD/.build/debug/macup}
[ -f macup ] && [ -x "$MACUP_BIN" ] || { echo "build both first: ./build.sh"; exit 1; }
F=0; N=0

# name | fixture | environment | arguments        (the fixture is a fix_* function below; the environment is VAR=value words)
CASES='help|||help
help-no-color|||help --no-color
help-lang||MACUP_LANG=|--lang uk help
help-NO_COLOR||NO_COLOR=1|help
help-config-lang|lang|MACUP_LANG=|help
tasks-config-lang|lang|MACUP_LANG=|tasks
version|||version
version-flag|||-v
tasks|config||tasks
tasks-empty-home|||tasks
tasks-json|config||tasks --json
tasks-only|config||tasks --only check.*,update.brew --skip check.disk
tasks-enable|config||tasks --enable clean.trash,clean.sim_erase --no-color
tasks-pick|config||tasks --pick some:key
tasks-xdg|config|XDG_CONFIG_HOME=@H/xdg|tasks --json
tasks-after-check|config||check tasks'

fix_config(){ mkdir -p "$1/.config/macup" "$1/xdg/macup"
  printf 'language = en\nskip = check.docker, update.*  # not these\nenable = clean.trash\nclean_level = standard\n' >"$1/.config/macup/config"
  printf 'skip = clean.*\n' >"$1/xdg/macup/config"; }
fix_lang(){ mkdir -p "$1/.config/macup"; printf 'language = ru\n' >"$1/.config/macup/config"; }

# what may differ between two runs: dates and times, durations, report names, temporary paths, pids; on a terminal the
# transient step and tick lines
norm(){ # file home
  perl -pe '
    s/\r\e\[K  \e\[2m… [^\r\n]*(?=\r)//g;
    s/\d{4}-\d\d-\d\d[ _]\d\d[:-]\d\d(?:[:-]\d\d)?/DATE/g;
    s/\b\d+m \d+s\b/Tm Ts/g;
    s/"seconds":\d+/"seconds":N/g;
    s/macup_DATE(?:_\d+)?\.md/macup_DATE.md/g;
    s{\Q'"${TMPDIR:-/tmp}"'\E/?macup[.-][A-Za-z0-9.]+}{TMP}g;
    s/\bpid \d+/pid N/g;
  ' "$1" | sed "s|$2|HOME|g"
}

run(){ # build lang tty fixture env args… → $W/<build>.{out,rc,report,files}
  local b=$1 lang=$2 tty=$3 fix=$4 envs=$5 H="$W/home" o="$W/$1"; shift 5
  rm -rf "$H"; mkdir -p "$H"; [ -n "$fix" ] && "fix_$fix" "$H"
  local e=(HOME="$H" MACUP_LANG="$lang" MACUP_BUILD="$b" PATH="$PATH")
  for v in $envs; do e+=("${v//@H/$H}"); done
  if [ "$tty" = tty ]; then
    # the terminal's input stays open, with nothing in it: at its end script would echo a ^D somewhere into the output
    rm -f "$W/in"; mkfifo "$W/in"; sleep 600 >"$W/in" & local hold=$!
    script -q /dev/null env "${e[@]}" tests/macup_run "$@" <"$W/in" >"$o.out" 2>&1; echo $? >"$o.rc"
    kill "$hold" 2>/dev/null; wait "$hold" 2>/dev/null
  else env "${e[@]}" tests/macup_run "$@" </dev/null >"$o.out" 2>&1; echo $? >"$o.rc"; fi
  local r; r=$(ls -t "$H"/Library/Logs/macup/macup_*.md 2>/dev/null | head -1)
  if [ -n "$r" ]; then norm "$r" "$H" >"$o.report"; else : >"$o.report"; fi
  norm "$o.out" "$H" >"$o.norm"; mv "$o.norm" "$o.out"
  (cd "$H" && find . ! -path './Library/Logs/macup/*' \( -type f -o -type l \) -exec cksum {} + | LC_ALL=C sort -k3) >"$o.files"
}

while IFS='|' read -r name fix envs args <&3; do
  if [ $# -gt 0 ]; then m=0; for w in "$@"; do case "$name" in "$w"*) m=1 ;; esac; done; [ $m = 1 ] || continue; fi
  for lang in en uk ru; do
    for tty in pipe tty; do
      N=$((N + 1))
      # shellcheck disable=SC2086 # the arguments are words
      run bash "$lang" "$tty" "$fix" "$envs" $args
      # shellcheck disable=SC2086
      run swift "$lang" "$tty" "$fix" "$envs" $args
      bad=""
      for k in out rc report files; do cmp -s "$W/bash.$k" "$W/swift.$k" || bad="$bad $k"; done
      if [ -z "$bad" ]; then echo "SAME $name $lang $tty"
      else F=1; echo "DIFF $name $lang $tty:$bad"
        for k in $bad; do diff "$W/bash.$k" "$W/swift.$k" | head -10 | sed 's/^/    /'; done
      fi
    done
  done
done 3<<<"$CASES"
echo; [ $N -gt 0 ] || { echo "no case matches: $*"; exit 2; }
[ $F = 0 ] && echo "ALL SAME ($N runs)" || { echo "SOME DIFFER"; exit 1; }

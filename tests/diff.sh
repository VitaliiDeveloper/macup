#!/bin/bash
# Differential harness: the bash build (./macup) and the Swift build (MACUP_BIN, else .build/debug/macup) run the same
# case on the same fake home, and what they leave must be the same after normalising (docs/swift-port-plan.md, "Parity").
#   tests/diff.sh              every case
#   tests/diff.sh tasks help   the cases whose name starts with one of these words
# Every case runs in en, uk and ru (MACUP_LANG), without a terminal and on one (through script). Compared: stdout and
# stderr together as macup writes them (--json included), the exit status, the newest report, the files in the fake home.
cd "$(dirname "$0")/.." || exit 1
work=$(mktemp -d "${TMPDIR:-/tmp}/macup-diff.XXXXXX"); trap 'rm -rf "$work"' EXIT
export MACUP_BIN=${MACUP_BIN:-$PWD/.build/debug/macup}
[ -f macup ] && [ -x "$MACUP_BIN" ] || { echo "build both first: ./build.sh"; exit 1; }
failed=0; runs=0

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
tasks-after-check|config||check tasks
tasks-unicode-blanks|blanks||tasks
tasks-latin1-config|latin1||tasks --json
help-latin1-config|latin1|MACUP_LANG=|help
tasks-step-09|octal||tasks'

fix_config(){ mkdir -p "$1/.config/macup" "$1/xdg/macup"
  printf 'language = en\nskip = check.docker, update.*  # not these\nenable = clean.trash\nclean_level = standard\n' >"$1/.config/macup/config"
  printf 'skip = clean.*\n' >"$1/xdg/macup/config"; }
fix_blanks(){ mkdir -p "$1/.config/macup"; printf 'skip = clean.brew\302\240\nenable = clean.trash\343\200\200 # ideographic space\n' >"$1/.config/macup/config"; }
fix_latin1(){ mkdir -p "$1/.config/macup"; printf 'language = uk\n# caf\351\nskip = clean.*\n' >"$1/.config/macup/config"; }   # sed stops at the byte
fix_octal(){ mkdir -p "$1/.config/macup"; printf 'step_timeout_minutes = 09\n' >"$1/.config/macup/config"; }   # bash's arithmetic fails
fix_lang(){ mkdir -p "$1/.config/macup"; printf 'language = ru\n' >"$1/.config/macup/config"; }

# what may differ between two runs: dates and times, durations, report names, temporary paths, pids; on a terminal the
# transient step and tick lines; the script's name in bash's own diagnostics (the Swift build runs it as /dev/fd/N)
norm(){ # file home
  perl -pe '
    s/\r\e\[K  \e\[2m… [^\r\n]*(?=\r)//g;
    s/\d{4}-\d\d-\d\d[ _]\d\d[:-]\d\d(?:[:-]\d\d)?/DATE/g;
    s/\b\d+m \d+s\b/Tm Ts/g;
    s/"seconds":\d+/"seconds":N/g;
    s/macup_DATE(?:_\d+)?\.md/macup_DATE.md/g;
    s{\Q'"${TMPDIR:-/tmp}"'\E/?macup[.-][A-Za-z0-9.]+}{TMP}g;
    s/\bpid \d+/pid N/g;
    s{^(?:/dev/fd/\d+|\S*macup): line (\d+): }{macup: line $1: }mg;
  ' "$1" | sed "s|$2|HOME|g"
}

run(){ # build lang tty fixture env args… → $work/<build>.{out,rc,report,files}
  local build=$1 lang=$2 tty=$3 fix=$4 envs=$5 home="$work/home" out="$work/$1"; shift 5
  rm -rf "$home"; mkdir -p "$home"; [ -n "$fix" ] && "fix_$fix" "$home"
  local vars=(HOME="$home" MACUP_LANG="$lang" MACUP_BUILD="$build" PATH="$PATH")
  for word in $envs; do vars+=("${word//@H/$home}"); done
  if [ "$tty" = tty ]; then
    # the terminal's input stays open, with nothing in it: at its end script would echo a ^D somewhere into the output
    rm -f "$work/in"; mkfifo "$work/in"; sleep 600 >"$work/in" & local hold=$!
    script -q /dev/null env "${vars[@]}" tests/macup_run "$@" <"$work/in" >"$out.out" 2>&1; echo $? >"$out.rc"
    kill "$hold" 2>/dev/null; wait "$hold" 2>/dev/null
  else env "${vars[@]}" tests/macup_run "$@" </dev/null >"$out.out" 2>&1; echo $? >"$out.rc"; fi
  local report; report=$(ls -t "$home"/Library/Logs/macup/macup_*.md 2>/dev/null | head -1)
  if [ -n "$report" ]; then norm "$report" "$home" >"$out.report"; else : >"$out.report"; fi
  norm "$out.out" "$home" >"$out.norm"; mv "$out.norm" "$out.out"
  (cd "$home" && find . ! -path './Library/Logs/macup/*' \( -type f -o -type l \) -exec cksum {} + | LC_ALL=C sort -k3) >"$out.files"
}

while IFS='|' read -r name fix envs args <&3; do
  if [ $# -gt 0 ]; then matched=0; for prefix in "$@"; do case "$name" in "$prefix"*) matched=1 ;; esac; done; [ $matched = 1 ] || continue; fi
  for lang in en uk ru; do
    for tty in pipe tty; do
      runs=$((runs + 1))
      # shellcheck disable=SC2086 # the arguments are words
      run bash "$lang" "$tty" "$fix" "$envs" $args
      # shellcheck disable=SC2086
      run swift "$lang" "$tty" "$fix" "$envs" $args
      bad=""
      for kind in out rc report files; do cmp -s "$work/bash.$kind" "$work/swift.$kind" || bad="$bad $kind"; done
      if [ -z "$bad" ]; then echo "SAME $name $lang $tty"
      else failed=1; echo "DIFF $name $lang $tty:$bad"
        for kind in $bad; do diff "$work/bash.$kind" "$work/swift.$kind" | head -10 | sed 's/^/    /'; done
      fi
    done
  done
done 3<<<"$CASES"
echo; [ $runs -gt 0 ] || { echo "no case matches: $*"; exit 2; }
[ $failed = 0 ] && echo "ALL SAME ($runs runs)" || { echo "SOME DIFFER"; exit 1; }

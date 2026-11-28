#!/bin/bash
# Differential harness: the bash build (./macup) and the Swift build (MACUP_BIN, else .build/debug/macup) run the same
# case on the same fake home, and what they leave must be the same after normalising (docs/swift-port-plan.md, "Parity").
#   tests/diff.sh              every case
#   tests/diff.sh tasks help   the cases whose name starts with one of these words
#   DIFF_SHARD=1/4 tests/diff.sh   every 4th of those cases, from the second: CI runs them in 4 jobs
# Every case runs in en, uk and ru (MACUP_LANG), without a terminal and on one (through script), unless its last field
# says "pipe". Compared: stdout and stderr together as macup writes them (--json included), the exit status, the newest
# report, the files in the fake home. The system tools a run asks (df, diskutil, tmutil, date, brew, sudo, pgrep, osascript)
# are fakes (tests/fakes.sh), first in PATH and kept there (MACUP_PATH=keep).
cd "$(dirname "$0")/.." || exit 1
work=$(mktemp -d "${TMPDIR:-/tmp}/macup-diff.XXXXXX"); trap 'chmod -R u+rwx "$work" 2>/dev/null; rm -rf "$work"' EXIT
export MACUP_BIN=${MACUP_BIN:-$PWD/.build/debug/macup}
[ -f macup ] && [ -x "$MACUP_BIN" ] || { echo "build both first: ./build.sh"; exit 1; }
failed=0; runs=0; picked=0
# shellcheck source=tests/fakes.sh
. tests/fakes.sh
fakes "$work/bin" pgrep df diskutil tmutil date brew sudo osascript; export PATH="$work/bin:$PATH"

# The cases are in tests/diff_cases/NN_<unit>.sh, one file per unit, read in name order. Each adds lines to CASES:
# name | fixture | environment | arguments [| pipe | tty]   (the fixture is a fix_* function there; the environment is VAR=value words)
# ANSWERS=a/b in the environment is typed into the terminal, each answer when macup asks (bash's ask reads /dev/tty);
# ANSWERS=/ is one empty answer. A case that asks without answers waits for ever on a terminal: make it pipe.
# A check of a clean task on a terminal ends with the pick, which waits for an answer: such cases run without one.
for cases in tests/diff_cases/*.sh; do
  # shellcheck source=/dev/null
  . "$cases"
done

# what may differ between two runs: dates and times, durations, report names, temporary paths, pids; on a terminal the
# transient step and tick lines, and the extra \r a terminal adds to a newline when a long write fills it; the script's name
# in bash's own diagnostics (the Swift build runs it as /dev/fd/N)
norm(){ # file home
  perl -pe '
    s/\r\e\[K  \e\[2m… [^\r\n]*(?=\r)//g;
    s/\r+\n/\r\n/g;
    s/\d{4}-\d\d-\d\d[ _]\d\d[:-]\d\d(?:[:-]\d\d)?/DATE/g;
    s/\b\d+m \d+s\b/Tm Ts/g;
    s/"seconds":\d+/"seconds":N/g;
    s/macup_DATE(?:_\d+)?\.md/macup_DATE.md/g;
    s{\Q'"${TMPDIR:-/tmp}"'\E/?macup[.-][A-Za-z0-9.]+}{TMP}g;
    s/\bpid \d+/pid N/g;
    s{^(?:/dev/fd/\d+|\S*macup): line (\d+): }{macup: line $1: }mg;
  ' "$1" | sed "s|$2|HOME|g"
}

# a run that printed the harness's own error (script, env, perl, macup_run, bash unable to open the build) compared nothing:
# script on macOS 27 once failed every terminal run that way, the same for both builds
harness_error(){ # output-file
  grep -aE '^(script|env|perl|/bin/bash|[^[:space:]]*macup_run|[^[:space:]]*diff\.sh)(: line [0-9]+)?: ' "$1" | head -1
}

type_answers(){ # a/b output-file done-file
  local answer list=() size=0 now end=$((SECONDS + 300))   # past the end the input closes: a question too many reads nothing
  IFS=/ read -ra list <<<"$1"
  for answer in ${list[@]+"${list[@]}"}; do
    # typed once the output has grown since the last answer (its echo), ends with a question ("[y/N] ", "Choose [1]: ", "[1]:")
    # and stays so for a moment: bash writes "removes:" and its newline apart
    while :; do
      { [ -e "$3" ] || [ $SECONDS -gt $end ]; } && return
      now=$(wc -c <"$2")
      if [ "$now" -gt "$size" ] && tail -c 2 "$2" | grep -qE '[]:] ?$'; then sleep 0.3; [ "$(wc -c <"$2")" = "$now" ] && break
      else sleep 0.1; fi
    done
    # a control character alone (^C, ^D) is a key, not a line: no newline after it
    size=$now; case "$answer" in [[:cntrl:]]) printf '%s' "$answer" ;; *) printf '%s\n' "$answer" ;; esac
  done
  until [ -e "$3" ] || [ ! -d "${3%/*}" ] || [ $SECONDS -gt $end ]; do sleep 0.1; done   # the work folder goes when diff.sh ends
}

run(){ # build lang tty fixture env args… → $work/<build>.{out,rc,report,files}
  local build=$1 lang=$2 tty=$3 fix=$4 envs=$5 home="$work/home" out="$work/$1"; shift 5
  # a case may leave a folder macup cannot write or read
  [ -d "$home" ] && chmod -R u+rwx "$home"; rm -rf "$home"; mkdir -p "$home"; [ -n "$fix" ] && "fix_$fix" "$home"
  # bash runs python3, which on some Macs (Xcode's 3.9) leaves its bytecode in the fake home's Library/Caches/com.apple.python
  local vars=(HOME="$home" MACUP_LANG="$lang" MACUP_BUILD="$build" PATH="$PATH" MACUP_PATH=keep PYTHONDONTWRITEBYTECODE=1)
  local answers=""
  for word in $envs; do case "$word" in ANSWERS=*) answers=${word#ANSWERS=} ;; *) vars+=("${word//@H/$home}") ;; esac; done
  if [ "$tty" = tty ]; then
    # the terminal's input stays open until macup is done: at its end script would echo a ^D somewhere into the output.
    # A pipe, not a fifo: script on macOS 27 cannot take a fifo as its input.
    runs_done="$work/done.$runs.$build.$tty"
    script -q /dev/null env "${vars[@]}" tests/macup_run "$@" < <(type_answers "$answers" "$out.out" "$runs_done") >"$out.out" 2>&1; echo $? >"$out.rc"
    : >"$runs_done"
  else   # a session of its own: no /dev/tty either, as in CI, even when diff.sh runs from a terminal
    env "${vars[@]}" PERL_BADLANG=0 perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV or die "$ARGV[0]: $!\n"' tests/macup_run "$@" </dev/null >"$out.out" 2>&1; echo $? >"$out.rc"; fi
  local report; report=$(ls -t "$home"/Library/Logs/macup/macup_*.md 2>/dev/null | head -1)
  if [ -n "$report" ]; then norm "$report" "$home" >"$out.report"; else : >"$out.report"; fi
  norm "$out.out" "$home" >"$out.norm"; mv "$out.norm" "$out.out"
  # the history's lines start with the date and time of the run
  local history="$home/Library/Application Support/macup/history.csv"
  { (cd "$home" && { find . ! -path './Library/Logs/macup/*' ! -path './Library/Application Support/macup/history.csv' -type f -exec cksum {} + 2>/dev/null
      find . -type l -exec sh -c 'for link; do echo "link $link -> $(readlink "$link")"; done' sh {} +; } | LC_ALL=C sort -k3)
    [ -f "$history" ] && norm "$history" "$home" | cksum; } >"$out.files"
}

while IFS='|' read -r name fix envs args modes <&3; do
  if [ $# -gt 0 ]; then matched=0; for prefix in "$@"; do case "$name" in "$prefix"*) matched=1 ;; esac; done; [ $matched = 1 ] || continue; fi
  picked=$((picked + 1))
  [ -z "${DIFF_SHARD:-}" ] || [ $(((picked - 1) % ${DIFF_SHARD#*/})) = "${DIFF_SHARD%/*}" ] || continue
  for lang in en uk ru; do
    for tty in ${modes:-pipe tty}; do
      runs=$((runs + 1))
      # shellcheck disable=SC2086 # the arguments are words
      run bash "$lang" "$tty" "$fix" "$envs" $args
      # shellcheck disable=SC2086
      run swift "$lang" "$tty" "$fix" "$envs" $args
      # an intended difference (docs/swift-port-plan.md): the case's known_<name> turns bash's output and report into Swift's
      # a filter that changes nothing any more is stale: the case then fails
      known="known_${name//-/_}"; note=""; bad=""
      if type "$known" >/dev/null 2>&1; then
        note=" (known difference)"; bad=" known-unused"
        for kind in out report; do
          "$known" <"$work/bash.$kind" >"$work/bash.$kind.known"
          cmp -s "$work/bash.$kind" "$work/bash.$kind.known" || bad=""
          mv "$work/bash.$kind.known" "$work/bash.$kind"
        done
      fi
      for kind in out rc report files; do cmp -s "$work/bash.$kind" "$work/swift.$kind" || bad="$bad $kind"; done
      for side in bash swift; do error=$(harness_error "$work/$side.out"); [ -z "$error" ] || bad="$bad harness:$side"; done
      if [ -z "$bad" ]; then echo "SAME $name $lang $tty$note"
      else failed=1; echo "DIFF $name $lang $tty:$bad"
        for kind in $bad; do
          case "$kind" in harness:*) harness_error "$work/${kind#harness:}.out" ;; known-unused) echo "$known changes nothing" ;; *) diff "$work/bash.$kind" "$work/swift.$kind" | head -10 ;; esac | sed 's/^/    /'
        done
      fi
    done
  done
done 3<<<"$CASES"
echo; [ $runs -gt 0 ] || { echo "no case matches: $*"; exit 2; }
[ $failed = 0 ] && echo "ALL SAME ($runs runs)" || { echo "SOME DIFFER"; exit 1; }

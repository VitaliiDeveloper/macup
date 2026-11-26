#!/bin/bash
# Differential harness: the bash build (./macup) and the Swift build (MACUP_BIN, else .build/debug/macup) run the same
# case on the same fake home, and what they leave must be the same after normalising (docs/swift-port-plan.md, "Parity").
#   tests/diff.sh              every case
#   tests/diff.sh tasks help   the cases whose name starts with one of these words
# Every case runs in en, uk and ru (MACUP_LANG), without a terminal and on one (through script), unless its last field
# says "pipe". Compared: stdout and stderr together as macup writes them (--json included), the exit status, the newest
# report, the files in the fake home. The system tools a run asks (df, diskutil, tmutil, brew, sudo, pgrep, osascript)
# are fakes (tests/fakes.sh), first in PATH and kept there (MACUP_PATH=keep).
cd "$(dirname "$0")/.." || exit 1
work=$(mktemp -d "${TMPDIR:-/tmp}/macup-diff.XXXXXX"); trap 'rm -rf "$work"' EXIT
export MACUP_BIN=${MACUP_BIN:-$PWD/.build/debug/macup}
[ -f macup ] && [ -x "$MACUP_BIN" ] || { echo "build both first: ./build.sh"; exit 1; }
failed=0; runs=0
# shellcheck source=tests/fakes.sh
. tests/fakes.sh
fakes "$work/bin" pgrep df diskutil tmutil brew sudo osascript; export PATH="$work/bin:$PATH"

# name | fixture | environment | arguments [| pipe]   (the fixture is a fix_* function below; the environment is VAR=value words)
# A check of a clean task on a terminal ends with the pick, which waits for an answer: such cases run without one.
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
tasks-step-09|octal||tasks
disk|||check --only check.disk
disk-low||FAKE_DF_FREE=75000000 FAKE_SWAP_KB=2097152 FAKE_SNAPS=3|check --only check.disk
disk-critical||FAKE_DF_FREE=10000000 FAKE_SMART=Failing|check --only check.disk
disk-no-smart||FAKE_SMART=|check --only check.disk --no-color
disk-json|||check --only check.disk --json
disk-quiet|||check --only check.disk --quiet
disk-unknown-in-config|badconf||check --only check.disk
disk-locked|locked||check --only check.disk
brew-check|brew||check --only update.brew
brew-check-current|brewcurrent||check --only update.brew
brew-check-json|brew||check --only update.brew --json
brew-update|brew||update --only update.brew
brew-update-current|brewcurrent||update --only update.brew
brew-upgrade-fails|brew|FAKE_BREW_FAIL=1 FAKE_SUDO_RC=0|update --only update.brew
brew-timeout|brew|MACUP_STEP_SECS=2 FAKE_BREW_SLEEP=30|update --only update.brew
brew-not-utf8|brew|FAKE_BREW_BYTES=1|update --only update.brew
brew-not-utf8-c|brew|FAKE_BREW_BYTES=1 LC_ALL=C|update --only update.brew
dd-check|dd||check --only clean.derived_data|pipe
dd-check-json|dd||check --only clean.derived_data --json
dd-clean|dd||clean --only clean.derived_data
dd-standard|dd||clean --level standard --only clean.derived_data
dd-aggressive|dd||all --level aggressive --only clean.derived_data
dd-busy|dd|FAKE_RUNNING=/Applications/Xcode.app/Contents/MacOS/Xcode|clean --only clean.derived_data
dd-busy-check|dd|FAKE_RUNNING=/Applications/Xcode.app/Contents/MacOS/Xcode|check --only clean.derived_data|pipe
dd-none|||clean --only clean.derived_data
dd-none-check|||check --only clean.derived_data
dd-small|ddsmall||check --only clean.derived_data
dd-symlink|ddlink||clean --only clean.derived_data
slice-all|slice|FAKE_SUDO_RC=0|all --only check.disk,update.brew,clean.derived_data --notify
slice-quiet-notify|dd|FAKE_DF_FREE=10000000|check --only check.disk,clean.derived_data --quiet --notify
trends|history||check --only check.trends,check.disk
trends-filling|historyfilling||check --only check.trends
reports|reports||check --only clean.reports'

fix_config(){ mkdir -p "$1/.config/macup" "$1/xdg/macup"
  printf 'language = en\nskip = check.docker, update.*  # not these\nenable = clean.trash\nclean_level = standard\n' >"$1/.config/macup/config"
  printf 'skip = clean.*\n' >"$1/xdg/macup/config"; }
fix_blanks(){ mkdir -p "$1/.config/macup"; printf 'skip = clean.brew\302\240\nenable = clean.trash\343\200\200 # ideographic space\n' >"$1/.config/macup/config"; }
fix_latin1(){ mkdir -p "$1/.config/macup"; printf 'language = uk\n# caf\351\nskip = clean.*\n' >"$1/.config/macup/config"; }   # sed stops at the byte
fix_octal(){ mkdir -p "$1/.config/macup"; printf 'step_timeout_minutes = 09\n' >"$1/.config/macup/config"; }   # bash's arithmetic fails
fix_lang(){ mkdir -p "$1/.config/macup"; printf 'language = ru\n' >"$1/.config/macup/config"; }
fix_badconf(){ mkdir -p "$1/.config/macup"; printf 'skip = check.bogus\nenable = clean.nope\n' >"$1/.config/macup/config"; }
fix_locked(){ mkdir -p "$1/Library/Application Support/macup/lock"; echo $$ >"$1/Library/Application Support/macup/lock/pid"; }   # this script runs
blob(){ mkdir -p "$1"; dd if=/dev/zero of="$1/blob" bs=1024 count="$2" 2>/dev/null; }
fix_dd(){ blob "$1/Library/Developer/Xcode/DerivedData/App-abc" 6144; blob "$1/Library/Developer/Xcode/DerivedData/Other-def/Build" 2048; }
fix_ddsmall(){ blob "$1/Library/Developer/Xcode/DerivedData/App-abc" 1024; }
fix_ddlink(){ fix_dd "$1"; blob "$1/elsewhere" 64; ln -s "$1/elsewhere" "$1/Library/Developer/Xcode/DerivedData/linked"; }
fix_brew(){ mkdir -p "$1/.fake/brewrepo/.git" "$1/.fake/brewcache/api"; : >"$1/.fake/brewrepo/.git/FETCH_HEAD"; touch -t 202001010000 "$1/.fake/brewrepo/.git/FETCH_HEAD"
  printf 'node (24.1.0) < 24.2.0\nwget (1.24) < 1.25\n' >"$1/.fake/brew-formulae"; printf 'firefox (140.0) != 141.0\n' >"$1/.fake/brew-casks"
  printf 'firefox\n' >"$1/.fake/brew-greedy"; for cask in a b c d e f g h i j k; do printf 'cask-%s\n' "$cask" >>"$1/.fake/brew-greedy"; done; }
fix_brewcurrent(){ mkdir -p "$1/.fake/brewcache/api"; : >"$1/.fake/brewcache/api/cask.jws.json"; }
fix_slice(){ fix_dd "$1"; fix_brew "$1"; }
fix_history(){ mkdir -p "$1/Library/Application Support/macup"; echo "2026-11-01 10:00,check,199000000,500000000,50,0,,,0,0,0" >"$1/Library/Application Support/macup/history.csv"; }
fix_historyfilling(){ mkdir -p "$1/Library/Application Support/macup"; echo "2026-11-01 10:00,check,250000000,500000000,50,0,612,80,0,0,0" >"$1/Library/Application Support/macup/history.csv"; }
fix_reports(){ local log="$1/Library/Logs/macup" state="$1/Library/Application Support/macup" day; mkdir -p "$log" "$state"
  for day in 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25; do : >"$log/macup_2026-10-${day}_10-00-00.md"; touch -t "202610${day}1000" "$log/macup_2026-10-${day}_10-00-00.md"; done
  for day in $(seq 1 1200); do echo "2026-10-01 10:00,check,$day,500000000,50,0,,,0,0,0"; done >"$state/history.csv"; }

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
  local vars=(HOME="$home" MACUP_LANG="$lang" MACUP_BUILD="$build" PATH="$PATH" MACUP_PATH=keep)
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
  # the history's lines start with the date and time of the run
  local history="$home/Library/Application Support/macup/history.csv"
  { (cd "$home" && { find . ! -path './Library/Logs/macup/*' ! -path './Library/Application Support/macup/history.csv' -type f -exec cksum {} +
      find . -type l -exec sh -c 'for link; do echo "link $link -> $(readlink "$link")"; done' sh {} +; } | LC_ALL=C sort -k3)
    [ -f "$history" ] && norm "$history" "$home" | cksum; } >"$out.files"
}

while IFS='|' read -r name fix envs args modes <&3; do
  if [ $# -gt 0 ]; then matched=0; for prefix in "$@"; do case "$name" in "$prefix"*) matched=1 ;; esac; done; [ $matched = 1 ] || continue; fi
  for lang in en uk ru; do
    for tty in ${modes:-pipe tty}; do
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

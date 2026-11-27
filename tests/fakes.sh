# shellcheck shell=bash
# Fake system tools for tests/run.sh and tests/diff.sh, so results never depend on this machine.
#   fakes DIR tool…   writes those fakes into DIR; each answers from FAKE_* variables or files in $HOME/.fake
fakes(){
  local dir=$1 tool; shift; mkdir -p "$dir"
  for tool in "$@"; do
    case "$tool" in
      # `running` asks pgrep which apps are open: FAKE_RUNNING holds command lines, FAKE_PROCS process names, one per line
      pgrep) cat <<'FAKE' ;;
#!/bin/bash
[ "$1" = "-x" ] && { printf '%s\n' "${FAKE_PROCS:-}" | grep -qx -- "$2"; exit; }
[ "$1" = "-f" ] && [ -n "$2" ] && printf '%s\n' "${FAKE_RUNNING:-}" | grep -qE -- "$2"
FAKE
      # which app folders have open files: FAKE_OPEN paths (one per line), or a failure with FAKE_LSOF_FAIL
      lsof) cat <<'FAKE' ;;
#!/bin/bash
[ -n "$FAKE_LSOF_FAIL" ] && exit 1
printf 'p1\nc%s\nn/\n' "${FAKE_LSOF_CMD:-SomeApp}"; printf '%s\n' "${FAKE_OPEN:-}" | sed '/^$/d; s/^/n/'
FAKE
      # only record what macup asked for: no test loads a LaunchAgent or shows a notification
      # (print-disabled is a question, not a change: it answers from FAKE_SHARING and is not recorded)
      launchctl|osascript) printf '#!/bin/bash\n[ "$1" = print-disabled ] && { printf "%%s\\n" "${FAKE_SHARING:-}"; exit 0; }\necho "$*" >>"$HOME/%s.log"\n' "$tool" ;;
      # the data volume: FAKE_DF_TOTAL and FAKE_DF_FREE in KB; the swap volume: FAKE_SWAP_KB used
      df) cat <<'FAKE' ;;
#!/bin/bash
echo 'Filesystem 1024-blocks Used Available Capacity iused ifree %iused Mounted on'
case "$*" in
  *VM*) echo "/dev/disk3s6 500000000 ${FAKE_SWAP_KB:-0} 400000000 1% 0 0 100% /System/Volumes/VM" ;;
  *) echo "/dev/disk3s5 ${FAKE_DF_TOTAL:-500000000} 1000 ${FAKE_DF_FREE:-200000000} 60% 0 0 100% /System/Volumes/Data" ;;
esac
FAKE
      diskutil) cat <<'FAKE' ;;
#!/bin/bash
printf '   Device Identifier:        disk0\n   SMART Status:             %s\n' "${FAKE_SMART-Verified}"
FAKE
      # Time Machine: FAKE_SNAPS local snapshots; a destination named FAKE_TM_DEST whose last backup is FAKE_TM_DAYS days old
      tmutil) cat <<'FAKE' ;;
#!/bin/bash
case "$1" in
  destinationinfo) [ -z "${FAKE_TM_DEST:-}" ] || printf '====\nName          : %s\nKind          : Local\n' "$FAKE_TM_DEST"; exit 0 ;;
  latestbackup) [ -z "${FAKE_TM_DAYS:-}" ] || { day=$(date -v-"$FAKE_TM_DAYS"d +%Y-%m-%d); echo "/Volumes/.timemachine/Disk/$day-101010.backup/$day-101010.backup"; }; exit 0 ;;
esac
snap=0; while [ "$snap" -lt "${FAKE_SNAPS:-0}" ]; do snap=$((snap + 1)); echo "com.apple.TimeMachine.2026-11-0$snap-101010.local"; done
FAKE
      # BSD date gives a date without a time now's time of day: a second that ticks between the backup age's two calls
      # makes an N-day-old backup N-1 days old in one build only. That date reads as its midnight; every other call is /bin/date
      date) cat <<'FAKE' ;;
#!/bin/bash
[ $# = 4 ] && [ "$1 $2 $4" = "-j -f %Y-%m-%d +%s" ] && exec /bin/date -j -f '%Y-%m-%d %H:%M:%S' "$3 00:00:00" +%s
exec /bin/date "$@"
FAKE
      # Homebrew: every call is logged in the home; outdated and list answer from $HOME/.fake/brew-{formulae,casks,greedy,list},
      # `update` prints a line that is not UTF-8 with FAKE_BREW_BYTES and sleeps FAKE_BREW_SLEEP seconds, `upgrade` exits with FAKE_BREW_FAIL
      brew) cat <<'FAKE' ;;
#!/bin/bash
echo "brew $* NO_AUTO_UPDATE=${HOMEBREW_NO_AUTO_UPDATE:-}" >>"$HOME/brew.log"
case "$1" in
  --repository) echo "$HOME/.fake/brewrepo" ;;
  --cache) echo "$HOME/.fake/brewcache" ;;
  update) echo '==> Updating Homebrew...'; [ -z "${FAKE_BREW_BYTES:-}" ] || printf 'caf\351 is not UTF-8\nafter it\n'; [ -z "${FAKE_BREW_SLEEP:-}" ] || exec sleep "$FAKE_BREW_SLEEP" ;;   # exec: no shell left to report the kill
  upgrade) printf '==> Upgrading \033[1m2\033[0m outdated packages\r\n'; exit "${FAKE_BREW_FAIL:-0}" ;;
  outdated) case "$*" in *greedy*) list=greedy ;; *--cask*) list=casks ;; *) list=formulae ;; esac; cat "$HOME/.fake/brew-$list" 2>/dev/null ;;
  list) cat "$HOME/.fake/brew-list" 2>/dev/null ;;   # the casks brew installed (update.apps)
esac
exit 0
FAKE
      # sudo: logged in the home; `sudo -n true` (a password is cached) exits with FAKE_SUDO_RC, 1 by default;
      # `sudo -v` (the password asked for) with FAKE_SUDO_ASK_RC, 0 by default
      sudo) cat <<'FAKE' ;;
#!/bin/bash
echo "sudo $*" >>"$HOME/sudo.log"
[ "$1 $2" = "-n true" ] && exit "${FAKE_SUDO_RC:-1}"
[ "$1" = -v ] && exit "${FAKE_SUDO_ASK_RC:-0}"
exit 0
FAKE
      *) echo "fakes: no fake $tool" >&2; return 1 ;;
    esac >"$dir/$tool"
    chmod +x "$dir/$tool"
  done
}

# updates unit: fakes for the updaters (claude, npm, mas, pipx…), written into DIR
#   answering DIR tool…   each answers from $HOME/.fake/<tool>/<key>, where the key is all its arguments ("/" read as "_")
#                         or, when nothing is there for those, the first one: <key> is printed, <key>.rc is the exit status,
#                         <key>.then is sourced afterwards (to change later answers), <key>.sleep holds seconds to wait.
#                         A call with nothing to print is an action and goes into $HOME/calls.log, so the files a run
#                         leaves say what it changed; "(in ~)" marks a call run from the home folder, PWD included. curl copies $HOME/.fake/cask.json to its -o file, or fails.
answering(){
  local dir=$1 tool; shift; mkdir -p "$dir"
  for tool in "$@"; do
    if [ "$tool" = curl ]; then cat <<'FAKE'
#!/bin/bash
echo "curl $*" >>"$HOME/calls.log"
while [ $# -gt 0 ]; do [ "$1" = -o ] && target=$2; shift; done
[ -f "$HOME/.fake/cask.json" ] && [ -n "$target" ] && cp "$HOME/.fake/cask.json" "$target" || exit 22
FAKE
    else cat <<'FAKE'
#!/bin/bash
tool=${0##*/} all="$*"; dir="$HOME/.fake/$tool" key=$1
for try in "${all//\//_}" "$1"; do
  for suffix in '' .rc .then .sleep; do [ -e "$dir/$try$suffix" ] && { key=$try; break 2; }; done
done
if [ -f "$dir/$key" ]; then cat "$dir/$key"
else where=""; [ "$PWD" = "$HOME" ] && [ "$(pwd -P)" = "$(cd "$HOME" && pwd -P)" ] && where=" (in ~)"; echo "$tool $*$where" >>"$HOME/calls.log"; fi
[ -f "$dir/$key.then" ] && . "$dir/$key.then"
[ -f "$dir/$key.sleep" ] && exec sleep "$(cat "$dir/$key.sleep")"
exit "$(cat "$dir/$key.rc" 2>/dev/null || echo 0)"
FAKE
    fi >"$dir/$tool"
    chmod +x "$dir/$tool"
  done
}
# answer HOME tool key text: what the fake <tool> prints for <key> (see answering)
answer(){ mkdir -p "$1/.fake/$2"; printf '%s\n' "$4" >"$1/.fake/$2/$3"; }

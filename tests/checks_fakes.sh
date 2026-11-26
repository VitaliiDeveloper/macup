# shellcheck shell=bash
# Fakes of the tools the system and security checks read (tests/diff.sh). With FAKE_SYSTEM set they answer from FAKE_*
# variables (a variable set to nothing leaves its line out); without it they run the real tool, as they do for ps's other
# questions (the step watchdog asks ps for the process tree).
#   checks_fakes DIR
checks_fakes(){
  local dir=$1 tool real
  for tool in uptime sysctl sw_vers memory_pressure ps pmset system_profiler fdesetup csrutil spctl defaults; do
    real=$(PATH=/usr/bin:/bin:/usr/sbin:/sbin command -v "$tool")
    { printf '#!/bin/bash\n[ -n "${FAKE_SYSTEM:-}" ] || exec %s "$@"\n' "$real"; checks_fake_body "$tool"; } >"$dir/$tool"
    chmod +x "$dir/$tool"
  done
}

checks_fake_body(){ # tool
  case "$1" in
    uptime) echo 'echo "10:00  up ${FAKE_UPTIME-3 days,  4:05}, 2 users, load averages: 1.00 1.20 1.30"' ;;
    sysctl) cat <<'FAKE' ;;
case "$2" in
  kern.boottime) echo "{ sec = $(( $(date +%s) - ${FAKE_UP_DAYS:-3} * 86400 - 3600 )), usec = 16 } Mon Nov 23 10:00:00 2026" ;;
  hw.model) echo "${FAKE_MODEL-Mac15,3}" ;;
  hw.memsize) echo "${FAKE_MEMSIZE-17179869184}" ;;
  hw.ncpu) echo "${FAKE_CORES-8}" ;;
  vm.loadavg) echo "{ ${FAKE_LOAD-2.50} 2.10 1.90 }" ;;
  vm.swapusage) echo "total = 2048.00M  used = ${FAKE_SWAP_USED-512.25M}  free = 1535.75M  (encrypted)" ;;
  *) exec /usr/sbin/sysctl "$@" ;;
esac
FAKE
    sw_vers) echo 'case "$*" in -productVersion) echo 15.1 ;; -buildVersion) echo 24B83 ;; *) exec /usr/bin/sw_vers "$@" ;; esac' ;;
    memory_pressure) echo 'printf "The system has 17179869184 (1048576 pages with a page size of 16384).\n\n"; [ -z "${FAKE_MEMFREE-42}" ] || echo "System-wide memory free percentage: ${FAKE_MEMFREE-42}%"' ;;
    # the first three lines matter: odd spacing, a comma in a name, a fourth line that is cut
    ps) cat <<'FAKE' ;;
case "$*" in
  "-Aceo pcpu=,comm= -r") printf ' 35.2 Xcode\n  4.0 Google  Chrome Helper\n  1.5 odd,name\n  0.1 later\n' ;;
  "-Aceo rss=,comm= -m") printf '4194304 Xcode\n 1572864 com.apple.WebKit.WebContent\n  524288 Slack\n  1024 later\n' ;;
  *) exec /bin/ps "$@" ;;
esac
FAKE
    pmset) cat <<'FAKE' ;;
case "$2" in
  therm) printf '%s\n' "${FAKE_THERM-Note: No thermal warning level has been recorded}" ;;
  batt) if [ -n "${FAKE_BATT:-}" ]; then printf "Now drawing from 'Battery Power'\n -InternalBattery-0 (id=4653155)\t%s; discharging; 4:10 remaining present: true\n" "$FAKE_BATT"
        else echo "Now drawing from 'AC Power'"; fi ;;
  *) exec /usr/bin/pmset "$@" ;;
esac
FAKE
    system_profiler) cat <<'FAKE' ;;
printf 'Power:\n\n    Battery Information:\n\n      Health Information:\n'
[ -z "${FAKE_CYCLES-612}" ] || echo "          Cycle Count: ${FAKE_CYCLES-612}"
[ -z "${FAKE_CONDITION-Normal}" ] || echo "          Condition: ${FAKE_CONDITION-Normal}"
[ -z "${FAKE_CAPACITY-91%}" ] || echo "          Maximum Capacity: ${FAKE_CAPACITY-91%}"
FAKE
    fdesetup) echo '[ -z "${FAKE_FILEVAULT-On}" ] || echo "FileVault is ${FAKE_FILEVAULT-On}."' ;;
    csrutil) echo '[ -z "${FAKE_SIP-enabled}" ] || echo "System Integrity Protection status: ${FAKE_SIP-enabled}."' ;;
    spctl) echo '[ -z "${FAKE_GATEKEEPER-enabled}" ] || echo "assessments ${FAKE_GATEKEEPER-enabled}"' ;;
    # only the two Software Update keys are faked; unset, defaults says the key is not there
    defaults) cat <<'FAKE' ;;
case "$*" in
  "read /Library/Preferences/com.apple.SoftwareUpdate AutomaticCheckEnabled") value=${FAKE_AUTO_CHECK:-} ;;
  "read /Library/Preferences/com.apple.SoftwareUpdate CriticalUpdateInstall") value=${FAKE_CRITICAL:-} ;;
  *) exec /usr/bin/defaults "$@" ;;
esac
[ -n "$value" ] && echo "$value" || { echo "The domain/default pair does not exist" >&2; exit 1; }
FAKE
  esac
}

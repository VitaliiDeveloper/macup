# ---------------------------------------------------------------- arguments
DRY=0; DO_UPDATE=1; DO_CLEAN=1; DEEP=0; ACTION=""; CMD=""; LANG_ARG=""; SCHED_ARG=""; REP_ARG=""; YES=0; QUIET=0; JSON=0; NOTIFY=0
cleanup_lang(){ [ -n "$LANGFILE" ] && rm -f "$LANGFILE"; }
trap cleanup_lang EXIT
set_lang(){ case "$1" in en|uk|ru) MSG_LANG=$1 ;; ua) MSG_LANG=uk ;; *) echo "--lang: en | uk | ru"; exit 2 ;; esac; load_lang; }
while [ $# -gt 0 ]; do case "$1" in
  check|-n|--dry-run)   DRY=1; ACTION=check ;;
  all|run)              ACTION=all ;;
  update|--no-clean)    DO_CLEAN=0; ACTION=update ;;
  clean|--no-update)    DO_UPDATE=0; ACTION=clean ;;
  deep|--deep)          DEEP=1 ;;
  --skip)               CLI_SKIP="$CLI_SKIP,$2"; shift ;;
  --skip=*)             CLI_SKIP="$CLI_SKIP,${1#*=}" ;;
  --only)               CLI_ONLY="$CLI_ONLY,$2"; shift ;;
  --only=*)             CLI_ONLY="$CLI_ONLY,${1#*=}" ;;
  --enable)             CLI_ENABLE="$CLI_ENABLE,$2"; shift ;;
  --enable=*)           CLI_ENABLE="$CLI_ENABLE,${1#*=}" ;;
  --pick)               PICK="$PICK,$2"; shift ;;
  --pick=*)             PICK="$PICK,${1#*=}" ;;
  --level)              LEVEL=$(level_num "$2"); [ -z "$LEVEL" ] && { echo "--level: safe | standard | aggressive"; exit 2; }; shift ;;
  --level=*)            LEVEL=$(level_num "${1#*=}"); [ -z "$LEVEL" ] && { echo "--level: safe | standard | aggressive"; exit 2; } ;;
  --lang)               set_lang "$2"; shift ;;
  --lang=*)             set_lang "${1#*=}" ;;
  --no-color)           B=; G=; Y=; R=; C=; D=; N=; CL= ;;
  -y|--yes)             YES=1 ;;
  -q|--quiet)           QUIET=1 ;;
  --json)               JSON=1; QUIET=1 ;;
  --notify)             NOTIFY=1 ;;
  schedule)             CMD=schedule; case "${2:-}" in ""|-*) ;; *) SCHED_ARG=$2; shift ;; esac ;;
  lang|language)        CMD=lang; case "${2:-}" in ""|-*) ;; *) LANG_ARG=$2; shift ;; esac ;;
  last|--last)          CMD=last ;;
  history|--history)    CMD=history ;;
  reports|--reports)    CMD=reports; case "${2:-}" in ""|-*) ;; *) REP_ARG=$2; shift ;; esac ;;
  tasks|--tasks)        CMD=tasks ;;
  config|--config)      CMD=config ;;
  self-update|selfupdate|upgrade) CMD=self_update ;;
  uninstall)            CMD=uninstall ;;
  help|-h|--help)       CMD=help ;;
  version|-v|--version) CMD=version ;;
  *) _f 'Unknown command: %s' "$1"; echo; _ 'Type  macup  for the menu or  macup help  for all commands.'; echo; exit 1 ;;
esac; shift; done

# under sudo the config, the reports and the history would become root's, and the next plain run could not write them
case "$CMD" in help|version|uninstall) ;; *)
  if [ "$(id -u)" = 0 ] && [ -n "${SUDO_USER:-}" ]; then _ 'macup does not need sudo: run it as yourself.'; echo; exit 1; fi ;;
esac
# --pick: clean exactly the items a check listed (their "key" in --json), nothing else
# and runs no check either, unless --only names some
if [ -n "$PICK" ]; then PICK=",$(echo "$PICK" | tr -d ' '),"; DRY=0; DO_UPDATE=0; DO_CLEAN=1; ACTION=clean; [ -n "$CLI_ONLY" ] || CLI_ONLY='clean.*'; fi

# one-off commands run after all options are read, so `macup help --lang uk` works
case "$CMD" in
  lang)        choose_lang "$LANG_ARG"; exit $? ;;
  last)        show_last; exit 0 ;;
  history)     if [ "$JSON" = 1 ]; then history_json; else show_history; fi; exit 0 ;;
  reports)     reports "$REP_ARG"; exit $? ;;
  tasks)       if [ "$JSON" = 1 ]; then tasks_json; else list_tasks; fi; exit 0 ;;
  config)      open_conf; exit 0 ;;
  self_update) self_update; exit 0 ;;
  uninstall)   uninstall; exit 0 ;;
  schedule)    schedule "$SCHED_ARG"; exit $? ;;
  help)        usage; exit 0 ;;
  version)     echo "macup $MACUP_VERSION"; exit 0 ;;
esac

# Changing anything needs an explicit command (all, update, clean). Without one:
# a terminal gets the menu, `macup --deep` is a deep check, anything else gets the help.
if [ -z "$ACTION" ]; then
  if [ "$DEEP" = 1 ]; then DRY=1
  elif [ -t 0 ] && [ -t 1 ]; then menu
  else usage; exit 2; fi
fi

load_conf
# a mistyped id used to match nothing without a word: `--only chek.disk` ran no task and said all was fine
unknown_tasks(){ # comma list → the ids that are neither a task nor a group
  printf '%s\n' "$1" | tr ',' '\n' | while IFS= read -r id; do
    case "$id" in ""|check.\*|update.\*|clean.\*) continue ;; esac
    [ -n "$(task_default "$id")" ] || printf '%s\n' "$id"
  done | paste -sd, - | sed 's/,/, /g'
}
BADIDS=$(unknown_tasks "$CLI_ONLY,$CLI_SKIP,$CLI_ENABLE")
[ -n "$BADIDS" ] && { _f 'Unknown task: %s (see every id with: macup tasks)' "$BADIDS"; echo; exit 2; }
BADCONF=$(unknown_tasks "$(conf skip "" | tr -d ' '),$(conf enable "" | tr -d ' ')")
mkdir -p "$LOGDIR" "$STATE_DIR"
# one run at a time: two would update the same tools and delete the same folders
RUNLOCK="$STATE_DIR/lock"; HAVE_LOCK=0
if ! mkdir "$RUNLOCK" 2>/dev/null; then
  OTHER=$(cat "$RUNLOCK/pid" 2>/dev/null)
  if [ -n "$OTHER" ] && kill -0 "$OTHER" 2>/dev/null; then
    _f 'macup is already running (pid %s). If it is not, remove %s' "$OTHER" "$(tildify "$RUNLOCK")"; echo; exit 1
  fi
  rm -rf "$RUNLOCK"; mkdir "$RUNLOCK" 2>/dev/null   # left by a run that was killed
fi
echo $$ >"$RUNLOCK/pid" && HAVE_LOCK=1
unlock(){ [ "$HAVE_LOCK" = 1 ] && rm -rf "$RUNLOCK"; HAVE_LOCK=0; }
# macup tidies up after itself on every run, a check too: its reports are its own files, not the Mac's.
# Reports older than keep_reports_days go, and never more than keep_reports runs stay; the history keeps its last 500 lines,
# the schedule's log its last 200; temp files a killed run left behind go after a day.
tidy_own(){
  local f
  case "$SKIP" in *",clean.reports,"*) return 0 ;; esac   # only an explicit skip: --only check.disk still tidies up
  # .log: the command output that versions before 2.9.0 kept next to each report
  find "$LOGDIR" -maxdepth 1 -type f \( -name 'macup_*.md' -o -name 'macup_*.log' \) -mtime +"$KEEP_DAYS" -delete 2>/dev/null
  # this run's report is not written yet: it makes keep_reports
  ls -r "$LOGDIR"/macup_*.md 2>/dev/null | tail -n +"$KEEP_RUNS" | while IFS= read -r f; do rm -f "$f" "${f%.md}.log"; done
  trim(){ [ -f "$1" ] && [ "$(wc -l <"$1")" -gt $(($2 * 2)) ] && tail -n "$2" "$1" >"$1.tmp" && cat "$1.tmp" >"$1"; rm -f "$1.tmp"; }
  trim "$HISTORY" 500; trim "$LOGDIR/schedule.log" 200
  find "${TMPDIR:-/tmp}/" -maxdepth 1 -type f -user "$(id -u)" \( -name 'macup.[A-Za-z0-9][A-Za-z0-9][A-Za-z0-9][A-Za-z0-9][A-Za-z0-9][A-Za-z0-9]' -o -name 'macup.[A-Za-z0-9][A-Za-z0-9][A-Za-z0-9][A-Za-z0-9][A-Za-z0-9][A-Za-z0-9].*' -o -name 'macup-lang.??????' -o -name 'macup-rc.??????' \) ! -name macup.sha256 -mtime +1 -delete 2>/dev/null
}
tidy_own
STAMP=$(date +%Y-%m-%d_%H-%M-%S)
REPORT="$LOGDIR/macup_$STAMP.md"
[ -e "$REPORT" ] && REPORT="$LOGDIR/macup_${STAMP}_$$.md"   # two runs in one second
BODY=$(mktemp "${TMPDIR:-/tmp}/macup.XXXXXX")
# what the commands print; it goes to the bottom of the report, so one run leaves one file
RAW="$BODY.raw"
# the cleaners keep lists in $BODY.rt and $BODY.caches while they run, background du results and lsof's output in $BODY.du.* (only their own du jobs still running are stopped: a finished job's PID may belong to another process by then); tl keeps $BODY.pid and $BODY.to; --json keeps $BODY.det
cleanup_body(){ [ -n "$BODY" ] || return 0; local j; for j in ${KBP_PID[@]+"${KBP_PID[@]}"}; do case " $(jobs -p | tr '\n' ' ') " in *" $j "*) kill "$j" 2>/dev/null ;; esac; done; rm -f "$BODY" "$BODY.rt" "$BODY.caches" "$BODY.pid" "$BODY.to" "$BODY.det" "$BODY".du.* "$RAW"; }
raw_section(){ # ~~~~ and not backticks: brew prints backtick fences of its own
  [ -s "$RAW" ] || return 0
  printf '\n## %s\n\n~~~~\n' "$(_ 'Command output')"; nocolor <"$RAW" | tr -d '\r'; printf '~~~~\n'
}
# Ctrl-C: what the run did so far and what its commands printed still land in the report
interrupted(){
  [ -n "$TICK" ] && kill "$TICK" 2>/dev/null
  [ "${REPORT_DONE:-0}" = 1 ] || { echo "# $(_f 'macup report — %s' "$(date '+%Y-%m-%d %H:%M')")"; echo
    _f 'Mode: %s · macup %s · took %s' "${MODE:-?}" "$MACUP_VERSION" "$((SECONDS / 60))m $((SECONDS % 60))s"; echo; echo
    echo "**$(_ 'Interrupted: this report is incomplete.')**"; echo
    cat "$BODY" 2>/dev/null; raw_section; } >"$REPORT" 2>/dev/null
  printf '\n%s%s%s\n' "$Y" "$(_f 'Interrupted. Report: %s' "$(tildify "$REPORT")")" "$N" >&4
  cleanup_body; cleanup_lang; stop_sudo_keep; unlock; exit 130
}
# 4: the terminal's stderr; the trap can fire inside run, where stdout and stderr go to $RAW
exec 4>&2
trap interrupted INT TERM HUP   # Ctrl-C, a kill, a terminal that closes: the report keeps what was printed
# the loop that keeps sudo's password fresh during App Store updates. A password macup asked for is forgotten
# right after them: the updaters that run next (pipx, Oh My Zsh, gh extensions, …) must not find sudo unlocked.
stop_sudo_keep(){
  [ -n "${SUDO_KEEP:-}" ] && kill "$SUDO_KEEP" 2>/dev/null; SUDO_KEEP=""
  [ "${SUDO_ASKED:-}" = 1 ] && sudo -k 2>/dev/null; SUDO_ASKED=""
}
trap 'cleanup_body; cleanup_lang; stop_sudo_keep; unlock' EXIT
[ "$JSON" = 1 ] && { B=; G=; Y=; R=; C=; D=; N=; CL=; }
# --quiet: only the summary is printed (--json: only the JSON); everything is still in the report
[ "$QUIET" = 1 ] && exec 3>&1 >/dev/null

if [ "$DRY" = 1 ]; then MODE="check"; elif [ "$DO_UPDATE" = 0 ]; then MODE="clean"; elif [ "$DO_CLEAN" = 0 ]; then MODE="update"; else MODE="all"; fi
[ "$DEEP" = 1 ] && MODE="$MODE+deep"
printf '%smacup %s%s · %s%s\n' "$B" "$MACUP_VERSION" "$N" "$MODE" "$( [ "$DRY" = 1 ] && printf ' · %s' "$(_ 'nothing is installed or deleted unless you pick it')")"

[ -n "$BADCONF" ] && warn 'Unknown task in %s: %s (see every id with: macup tasks)' "$(tildify "$CONF")" "$BADCONF"

PREV=$( [ -s "$HISTORY" ] && tail -n 1 "$HISTORY")


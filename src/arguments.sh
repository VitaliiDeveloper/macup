# ---------------------------------------------------------------- arguments
DRY=0; DO_UPDATE=1; DO_CLEAN=1; DEEP=0; ACTION=""; CMD=""; LANG_ARG=""; SCHED_ARG=""; YES=0; QUIET=0; JSON=0; NOTIFY=0
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
  reports|--reports)    CMD=reports ;;
  tasks|--tasks)        CMD=tasks ;;
  config|--config)      CMD=config ;;
  self-update|selfupdate|upgrade) CMD=self_update ;;
  uninstall)            CMD=uninstall ;;
  help|-h|--help)       CMD=help ;;
  version|-v|--version) CMD=version ;;
  *) _f 'Unknown command: %s' "$1"; echo; _ 'Type  macup  for the menu or  macup help  for all commands.'; echo; exit 1 ;;
esac; shift; done

# one-off commands run after all options are read, so `macup help --lang uk` works
case "$CMD" in
  lang)        choose_lang "$LANG_ARG"; exit $? ;;
  last)        show_last; exit 0 ;;
  history)     show_history; exit 0 ;;
  reports)     mkdir -p "$LOGDIR"; open "$LOGDIR"; exit 0 ;;
  tasks)       list_tasks; exit 0 ;;
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
STAMP=$(date +%Y-%m-%d_%H-%M-%S)
REPORT="$LOGDIR/macup_$STAMP.md"
RAW="$LOGDIR/macup_$STAMP.log"
BODY=$(mktemp "${TMPDIR:-/tmp}/macup.XXXXXX")
# the cleaners keep lists in $BODY.rt and $BODY.caches while they run; tl keeps $BODY.pid and $BODY.to
cleanup_body(){ [ -n "$BODY" ] && rm -f "$BODY" "$BODY.rt" "$BODY.caches" "$BODY.pid" "$BODY.to"; }
trap '[ -n "$TICK" ] && kill "$TICK" 2>/dev/null; printf "\n%s%s%s\n" "$Y" "$(_f "Interrupted. Log: %s" "$(tildify "$RAW")")" "$N" >&2; cleanup_body; cleanup_lang; stop_sudo_keep; unlock; exit 130' INT
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

PREV=$( [ -s "$HISTORY" ] && tail -n 1 "$HISTORY")


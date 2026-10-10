# ---------------------------------------------------------------- arguments
DRY=0; DO_UPDATE=1; DO_CLEAN=1; DEEP=0; ACTION=""; CMD=""; LANG_ARG=""
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
STAMP=$(date +%Y-%m-%d_%H-%M)
REPORT="$LOGDIR/macup_$STAMP.md"
RAW="$LOGDIR/macup_$STAMP.log"
BODY=$(mktemp "${TMPDIR:-/tmp}/macup.XXXXXX")
trap 'printf "\n%s%s%s\n" "$Y" "$(_f "Interrupted. Log: %s" "$(tildify "$RAW")")" "$N"; rm -f "$BODY"; cleanup_lang; exit 130' INT
trap 'rm -f "$BODY"; cleanup_lang' EXIT

if [ "$DRY" = 1 ]; then MODE="check"; elif [ "$DO_UPDATE" = 0 ]; then MODE="clean"; elif [ "$DO_CLEAN" = 0 ]; then MODE="update"; else MODE="all"; fi
[ "$DEEP" = 1 ] && MODE="$MODE+deep"
printf '%smacup %s%s · %s%s\n' "$B" "$MACUP_VERSION" "$N" "$MODE" "$( [ "$DRY" = 1 ] && printf ' · %s' "$(_ 'nothing is installed or deleted unless you pick it')")"

PREV=$( [ -s "$HISTORY" ] && tail -n 1 "$HISTORY")


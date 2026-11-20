# ================================================================ LEFTOVERS of deleted apps
# An updater lives outside its app (Application Support), so deleting the app leaves it registered and its program
# intact. The owner is found by signing team, then by bundle-id vendor; a vendor that does not match is a miss, not a removal.
LO_APPS="${MACUP_APPS:-/Applications:$HOME/Applications}"
LO_SYS="${MACUP_SYSLIB:-/Library}"
APPS=""; APPS_TEAMS=0; O_N=0; O_SCANNED=0
O_PLIST=(); O_LABEL=(); O_PROG=(); O_REASON=(); O_SYS=(); O_VENDOR=(); O_NAME=(); O_DIR=()

lc(){ printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
apps_scan(){ # APPS: one line per installed app — bundle id (lowercase) | team id (filled by apps_teams) | path
  local r a id
  APPS=$(printf '%s\n' "$LO_APPS" | tr ':' '\n' | while IFS= read -r r; do
      [ -d "$r" ] && find "$r" -maxdepth 3 -type d -name '*.app' -prune 2>/dev/null
    done | while IFS= read -r a; do
      id=$(plutil -extract CFBundleIdentifier raw -o - "$a/Contents/Info.plist" 2>/dev/null) || continue
      printf '%s||%s\n' "$(lc "$id")" "$a"
    done)
  APPS_TEAMS=0
}
apps_teams(){ # codesign is slow: only once there is a suspect
  [ "$APPS_TEAMS" = 1 ] && return; APPS_TEAMS=1
  local id t p
  APPS=$(printf '%s\n' "$APPS" | while IFS='|' read -r id t p; do [ -n "$id" ] && printf '%s|%s|%s\n' "$id" "$(team_of "$p")" "$p"; done)
}
vendor_of(){ lc "$1" | awk -F. 'NF >= 2 && $1 != "" && $2 != "" {print $1 "." $2}'; }
vendor_installed(){ [ -n "$1" ] && printf '%s\n' "$APPS" | awk -F'|' -v v="$1" '$1 == v || index($1, v ".") == 1 {f = 1} END {exit !f}'; }
team_installed(){ [ -n "$1" ] || return 1; apps_teams; printf '%s\n' "$APPS" | awk -F'|' -v t="$1" '$2 == t {f = 1} END {exit !f}'; }
team_of(){ codesign -dv --verbose=2 "$1" 2>&1 | sed -n 's/^TeamIdentifier=//p' | grep -v '^not set$' | head -1; }
signer_of(){ codesign -dv --verbose=2 "$1" 2>&1 | sed -n 's/^Authority=Developer ID Application: \(.*\) ([A-Z0-9]*)$/\1/p' | head -1 | sed -E 's/,? (Inc\.?|LLC|Ltd\.?)$//'; }
assoc_ids(){ plutil -extract AssociatedBundleIdentifiers json -o - "$1" 2>/dev/null | tr -d '[]"' | tr ',' '\n' | sed '/^$/d'; }
in_owner_place(){ # program label — places an app keeps its own helpers; /opt/homebrew, ~/.local, scripts are never judged by owner
  local n
  case "$1" in
    */*.app/*|"$HOME/Library/Application Support/"*|"$LO_SYS/Application Support/"*) return 0 ;;
    "$HOME/Library/"*) n=${1#"$HOME/Library/"}; n=$(lc "${n%%/*}")
                       printf '%s\n' "$(lc "$2")" | tr '.' '\n' | grep -qxF "$n" ;;
    *) return 1 ;;
  esac
}
cap(){ printf '%s' "$1" | awk '{print toupper(substr($0, 1, 1)) substr($0, 2)}'; }
lo_add(){ # plist label program reason sys vendor name
  O_PLIST[O_N]=$1; O_LABEL[O_N]=$2; O_PROG[O_N]=$3; O_REASON[O_N]=$4; O_SYS[O_N]=$5; O_VENDOR[O_N]=$6
  O_NAME[O_N]=${7:-$(cap "${6#*.}")}; O_DIR[O_N]=""
  O_N=$((O_N + 1))
}
leftovers_scan(){
  [ "$O_SCANNED" = 1 ] && return; O_SCANNED=1
  local f b sys label prog id v ids team owned i j
  apps_scan
  for f in "$HOME/Library/LaunchAgents"/*.plist "$LO_SYS/LaunchAgents"/*.plist "$LO_SYS/LaunchDaemons"/*.plist; do
    [ -f "$f" ] && [ ! -L "$f" ] || continue
    b=$(basename "$f" .plist); case "$b" in com.apple.*|"$SCHED_LABEL") continue ;; esac
    sys=0; case "$f" in "$LO_SYS"/*) sys=1 ;; esac
    if ! plutil -lint "$f" >/dev/null 2>&1; then lo_add "$f" "" "" broken "$sys" "$(vendor_of "$b")"; continue; fi
    label=$(plutil -extract Label raw -o - "$f" 2>/dev/null)
    case "$label" in com.apple.*|"$SCHED_LABEL") continue ;; esac
    prog=$(plutil -extract Program raw -o - "$f" 2>/dev/null || plutil -extract ProgramArguments.0 raw -o - "$f" 2>/dev/null)
    if [ -z "$label" ] && [ -z "$prog" ]; then
      [ "$(plutil -convert json -o - "$f" 2>/dev/null)" = "{}" ] || continue
      case ",$(stat -f %Sf "$f" 2>/dev/null)," in *,uchg,*) continue ;; esac   # locked empty file: some tools block an updater this way
      lo_add "$f" "" "" empty "$sys" "$(vendor_of "$b")"; continue
    fi
    ids=$(assoc_ids "$f"); v=$(vendor_of "$(printf '%s\n' "$ids" | head -1)"); [ -z "$v" ] && v=$(vendor_of "${label:-$b}")
    case "$prog" in /*) ;; *) continue ;; esac
    if [ ! -e "$prog" ]; then lo_add "$f" "$label" "$prog" missing "$sys" "$v" "$(signer_of "$prog")"; continue; fi
    in_owner_place "$prog" "$label" || continue
    team=$(team_of "$prog"); team_installed "$team" && continue
    owned=0
    for id in $ids $label; do vendor_installed "$(vendor_of "$id")" && { owned=1; break; }; done
    [ "$owned" = 1 ] && continue
    lo_add "$f" "$label" "$prog" gone "$sys" "$v" "$(signer_of "$prog")"
  done
  for ((i = 0; i < O_N; i++)); do   # an empty plist has no signer: name it like its vendor's other items
    for ((j = 0; j < O_N; j++)); do
      [ "${O_VENDOR[j]}" = "${O_VENDOR[i]}" ] && [ -n "${O_PROG[j]}" ] && [ -e "${O_PROG[j]}" ] && { O_NAME[i]=${O_NAME[j]}; break; }
    done
  done
}

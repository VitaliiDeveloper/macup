# ================================================================ LEFTOVERS of deleted apps
# An updater lives outside its app (Application Support), so deleting the app leaves it registered and its program
# intact. The owner is found by signing team, then by bundle-id vendor; a vendor that does not match is a miss, not a removal.
LO_APPS="${MACUP_APPS:-/Applications:$HOME/Applications}"
LO_SYS="${MACUP_SYSLIB:-/Library}"
APPS=""; APPS_TEAMS=0; O_N=0; O_SCANNED=0; LO_RESCANNED=0
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
LO_SHARED=" uk.co uk.org au.com jp.co nz.co br.com cn.com io.github com.github io.gitlab com.gitlab org.gitlab net.sourceforge com.googlecode app.netlify "
vendor_of(){ # first two id components; three under a shared prefix (io.github.<owner>), where two would mean many publishers
  local v; v=$(lc "$1" | awk -F. 'NF >= 2 && $1 != "" && $2 != "" {print $1 "." $2}')
  case "$LO_SHARED" in *" $v "*) lc "$1" | awk -F. 'NF >= 3 && $3 != "" {print $1 "." $2 "." $3}' ;; *) echo "$v" ;; esac
}
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
                       printf '%s\n' "$(lc "$2")" | tr '.' '\n' | grep -xF "$n" >/dev/null ;;
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
    [ -r "$f" ] || continue   # root-only: macup cannot judge it, which is not the same as broken
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
    [ -n "$v" ] || continue   # a label like "mybackup" names no vendor: never judged
    if [ ! -e "$prog" ]; then lo_add "$f" "$label" "$prog" missing "$sys" "$v" "$(signer_of "$prog")"; continue; fi
    in_owner_place "$prog" "$label" || continue
    owned=0
    while IFS= read -r id; do [ -n "$id" ] && vendor_installed "$(vendor_of "$id")" && owned=1; done <<EOF2
$ids
$label
EOF2
    [ "$owned" = 1 ] && continue
    team=$(team_of "$prog"); team_installed "$team" && continue
    lo_add "$f" "$label" "$prog" gone "$sys" "$v" "$(signer_of "$prog")"
  done
  for ((i = 0; i < O_N; i++)); do   # an empty plist has no signer: name it like its vendor's other items
    for ((j = 0; j < O_N; j++)); do
      [ "${O_VENDOR[j]}" = "${O_VENDOR[i]}" ] && [ -n "${O_PROG[j]}" ] && [ -e "${O_PROG[j]}" ] && { O_NAME[i]=${O_NAME[j]}; break; }
    done
  done
}

lo_dir(){ # program → its own folder one level below the vendor's (…/Application Support/Perplexity/CometUpdater); empty when there is none
  local p=$1 base rest v sub
  for base in "$HOME/Library/Application Support" "$LO_SYS/Application Support" "$HOME/Library"; do
    case "$p" in "$base"/*) ;; *) continue ;; esac
    case "$p" in "$base"/*/*/*) ;; *) return ;; esac   # right in the vendor folder: that folder may hold other data
    rest=${p#"$base"/}; v=${rest%%/*}; rest=${rest#*/}; sub=${rest%%/*}
    [ -d "$base/$v/$sub" ] && [ ! -L "$base/$v/$sub" ] && [ ! -L "$base/$v" ] && echo "$base/$v/$sub"
    return
  done
}
O_ALLOW=""; C_LOP=()
outer(){ # paths → the same set without paths inside another one of them
  printf '%s\n' "$1" | sed '/^$/d' | LC_ALL=C sort -u | awk 'k != "" && index($0, k "/") == 1 {next} {print; k = $0}'
}
lo_total(){ # size of every leftover entry together, each folder once
  local i all=""
  for ((i = 0; i < C_N; i++)); do case "${C_TASK[i]}" in clean.orphan_*) all="$all${C_LOP[i]}"$'\n' ;; esac; done
  kbl "$(outer "$all")"
}
to_trash(){ # path [sudo] — the only way leftovers leave: into the Trash, under a free name, and only paths found by the scan
  local p=$1 b t i=2
  case "$p" in ""|*/../*|*/..) echo "macup refused to move: $p" >>"$RAW"; return 1 ;; esac
  [ -L "$p" ] && { echo "macup refused a symlink: $p" >>"$RAW"; return 1; }
  [ -e "$p" ] || return 0
  printf '%s\n' "$O_ALLOW" | grep -xF -- "$p" >/dev/null || { echo "macup refused to move: $p" >>"$RAW"; return 1; }
  mkdir -p "$HOME/.Trash"; b=$(basename "$p"); t="$HOME/.Trash/$b"
  while [ -e "$t" ] || [ -L "$t" ]; do t="$HOME/.Trash/$b $i"; i=$((i + 1)); done
  if [ -n "$2" ]; then sudo mv "$p" "$t" 2>>"$RAW" && sudo chown -R "$(id -u)" "$t" 2>>"$RAW"
  else mv "$p" "$t" 2>>"$RAW"; fi
}
re_esc(){ printf '%s' "$1" | sed 's/[][\.*^$+?(){}|/]/\\&/g'; }
orph_still(){ # n — re-checked right before moving: an app may have come back or the program may be running
  local n=$1 f=${O_PLIST[$1]} id owned=0
  [ -e "$f" ] || return 1
  [ -n "${O_PROG[n]}" ] && running "$(re_esc "${O_PROG[n]}")" && return 1
  case "${O_REASON[n]}" in
    empty)   [ "$(plutil -convert json -o - "$f" 2>/dev/null)" = "{}" ] ;;
    missing) [ ! -e "${O_PROG[n]}" ] ;;
    gone)    [ "$LO_RESCANNED" = 1 ] || { apps_scan; LO_RESCANNED=1; }; team_installed "$(team_of "${O_PROG[n]}")" && return 1
             while IFS= read -r id; do [ -n "$id" ] && vendor_installed "$(vendor_of "$id")" && owned=1; done <<EOF2
$(assoc_ids "$f")
${O_LABEL[n]}
EOF2
             [ "$owned" = 0 ] ;;
    *)       return 1 ;;
  esac
}
lo_kind(){ # n → short name of what it is
  case "${O_REASON[$1]}" in empty) _ 'empty startup file'; return ;; esac
  [ "${O_SYS[$1]}" = 1 ] && { _ 'system service'; return; }
  case "$(lc "${O_LABEL[$1]} ${O_PROG[$1]}")" in *update*|*keystone*) _ 'update program' ;; *) _ 'background program' ;; esac
}
lo_info(){ # n → What / Why / Safe lines
  local n=$1 every
  if [ "${O_REASON[n]}" = empty ]; then _ 'What: a startup file with nothing in it.'; echo
  elif [ "${O_SYS[n]}" = 1 ]; then _ 'What: a service that starts for every user of this Mac.'; echo
  else
    every=$(plutil -extract StartInterval raw -o - "${O_PLIST[n]}" 2>/dev/null)
    case "$(lo_kind "$n")" in "$(_ 'update program')")
      if [ "$every" = 3600 ]; then _ 'What: a background program that checked for updates every hour.'; else _ 'What: a background program that checks for updates.'; fi ;;
      *) _ 'What: a background program that starts with your Mac.' ;; esac; echo
  fi
  case "${O_REASON[n]}" in
    gone)    _f 'Why: no app from %s is installed anymore.' "${O_NAME[n]}" ;;
    missing) _ 'Why: its program was deleted.' ;;
    empty)   _ 'Why: the file is empty and does nothing.' ;;
  esac; echo
  _ 'Safe: yes, it goes to the Trash.'; echo
  [ "${O_SYS[n]}" = 1 ] && { _ 'Needs your Mac password (asked once for all such items).'; echo; }
}
lo_domain(){ case "${O_PLIST[$1]}" in */LaunchDaemons/*) echo system ;; *) echo "gui/$(id -u)" ;; esac; }
lo_helper(){ local h="$LO_SYS/PrivilegedHelperTools/${O_LABEL[$1]}"; [ "${O_SYS[$1]}" = 1 ] && [ -n "${O_LABEL[$1]}" ] && [ -f "$h" ] && [ ! -L "$h" ] && echo "$h"; }
sudo_cmds(){ # n → what removing a system item runs
  local n=$1 h
  [ -n "${O_LABEL[n]}" ] && echo "sudo launchctl bootout $(lo_domain "$n")/${O_LABEL[n]}"
  echo "sudo mv \"$(tildify "${O_PLIST[n]}")\" ~/.Trash/"
  h=$(lo_helper "$n"); [ -n "$h" ] && echo "sudo mv \"$h\" ~/.Trash/"
  [ -n "${O_DIR[n]}" ] && echo "sudo mv \"${O_DIR[n]}\" ~/.Trash/"
  return 0
}
lo_sys_ok(){ # n — a system item is offered only on strong evidence: the program is gone, or its signing team owns no installed app
  [ "${O_REASON[$1]}" = missing ] && return 0
  [ "${O_REASON[$1]}" = gone ] && [ -n "$(team_of "${O_PROG[$1]}")" ]
}
leftovers_cands(){
  task_allowed clean.orphan_agents || task_allowed clean.orphan_data || return 0
  leftovers_scan
  local i d s
  task_allowed clean.orphan_data && data_cands
  task_allowed clean.orphan_agents || return 0
  for ((i = 0; i < O_N; i++)); do
    if [ "${O_SYS[i]}" = 1 ]; then lo_interactive && lo_sys_ok "$i" || continue; fi
    case "${O_REASON[i]}" in empty|missing|gone) ;; *) continue ;; esac
    d=""; [ "${O_REASON[i]}" = gone ] && d=$(lo_dir "${O_PROG[i]}"); O_DIR[i]=$d   # a missing program proves nothing about its folder
    O_ALLOW="$O_ALLOW${O_PLIST[i]}"$'\n'"$(lo_helper "$i")"$'\n'
    s=0; [ -n "$d" ] && { O_ALLOW="$O_ALLOW$d"$'\n'"$(dirname "$d")"$'\n'; s=$(kb "$d"); }
    CL_MANUAL=1 cand clean.orphan_agents 3 "${O_NAME[i]} · $(lo_kind "$i")$([ "${O_SYS[i]}" = 1 ] && echo ' 🔑')" "$s" cmd "orph:$i" "" "" "" "$(lo_info "$i"; echo "@$(tildify "${O_PLIST[i]}")"; [ -n "$d" ] && echo "@$(tildify "$d")")"
    [ "${O_SYS[i]}" = 1 ] && C_SUDO[C_N - 1]=1
    C_LOP[C_N - 1]="${O_PLIST[i]}${d:+$'\n'$d}"
  done
}
run_orph(){ # n
  local n=$1 l=${O_LABEL[$1]} d=${O_DIR[$1]} s=0 p h su
  if ! orph_still "$n"; then info '%s: still in use, skipped' "${O_NAME[n]} · $(lo_kind "$n")"; return 2; fi
  su=""; [ "${O_SYS[n]}" = 1 ] && su=sudo
  if [ "${O_REASON[n]}" != empty ] && printf '%s' "$l" | grep -E '^[A-Za-z0-9._-]+$' >/dev/null && launchctl print "$(lo_domain "$n")/$l" >/dev/null 2>&1; then
    $su launchctl bootout "$(lo_domain "$n")/$l" 2>>"$RAW"
  fi
  [ -n "$d" ] && s=$(kb "$d")
  to_trash "${O_PLIST[n]}" $su || return 1
  h=$(lo_helper "$n"); [ -n "$h" ] && { to_trash "$h" $su || return 1; }
  if [ -n "$d" ]; then
    to_trash "$d" $su || return 1
    p=$(dirname "$d"); [ -d "$p" ] && [ -z "$(ls -A "$p" 2>/dev/null)" ] && to_trash "$p" $su
  fi
  KEY_FREED=$s
}

# --- data of a deleted app: only for vendors whose agent was found orphaned, so SDK ids and test bundles are never guessed at
D_N=0; D_VENDOR=(); D_NAME=(); D_PATHS=()
LO_LIBRARY="accounts assistants audio autosave biome caches calendars colorsync colors compositions containers contacts cookies developer favorites fileprovider fonts frontboard gamekit homekit intents keyboard keychains logs mail maps messages metadata news passes photos preferences printers reminders safari scripts services sharing shortcuts sounds spelling spotlight suggestions translation trial weather webkit"
LO_GENERIC=" app mac helper helpers agent code updater update service services daemon data cache caches support shared common "
LO_TTY=0; [ -t 0 ] && [ -t 1 ] && [ "$QUIET" = 0 ] && LO_TTY=1   # decided here: helpers run in $(…), where stdout is never a terminal
lo_interactive(){ [ "$LO_TTY" = 1 ]; }
app_names(){ local id t p; printf '%s\n' "$APPS" | while IFS='|' read -r id t p; do [ -n "$id" ] && { echo "${id##*.}"; p=${p##*/}; lc "${p%.app}"; echo; }; done; }
name_ok(){ # name — a folder named like this may belong to the deleted app, not to another app or to macOS
  [ -n "$1" ] || return 1
  case "$LO_GENERIC" in *" $1 "*) return 1 ;; esac
  printf '%s\n' "$LO_NAMES" | grep -xF -- "$1" >/dev/null && return 1   # never grep -q on a pipe here: with pipefail an early exit reads as "no"
  ! printf '%s\n' "$LO_APPLE" | grep -xF -- "$1" >/dev/null
}
apple_names(){ # Apple's own app and folder names, so ~/Library/Mail or Application Support/AddressBook are never taken
  local e
  for e in /System/Applications/*.app /System/Applications/Utilities/*.app /System/Library/CoreServices/*.app; do [ -e "$e" ] && { e=${e##*/}; lc "${e%.app}"; echo; }; done
  for e in "$HOME/Library/Preferences"/com.apple.*; do [ -e "$e" ] && { e=$(lc "${e##*/com.apple.}"); echo "${e%%.*}"; }; done
  printf '%s\n' $LO_LIBRARY
}
by_name(){ # dir name → entries of dir whose name matches, ignoring case, unless an installed app keeps files there
  local e; for e in "$1"/*; do [ -e "$e" ] && [ ! -L "$e" ] && [ "$(lc "${e##*/}")" = "$2" ] && ! held "$e" && echo "$e"; done
}
held(){ # folder — true when a name inside it is an installed app's bundle id or app name
  local ids e
  ids=$(printf '%s\n' "$APPS" | cut -d'|' -f1 | sed '/^$/d')
  [ -n "$ids" ] || return 1
  find "$1" -maxdepth 3 2>/dev/null | sed 1d | while IFS= read -r e; do lc "${e##*/}"; echo; done | LO_IDS="$ids" LO_NM="$LO_NAMES" awk '
    BEGIN { n = split(ENVIRON["LO_IDS"], I, "\n"); m = split(ENVIRON["LO_NM"], A, "\n"); for (j = 1; j <= m; j++) if (A[j] != "") N[A[j]] = 1 }
    f { next }
    { if ($0 in N) { f = 1; next } for (j = 1; j <= n; j++) if (I[j] != "" && index($0, I[j])) { f = 1; next } }
    END { exit !f }'
}
data_paths(){ # vendor
  local v=$1 L="$HOME/Library" d e n id ids="" t i
  for d in Preferences Caches HTTPStorages "Saved Application State" WebKit Logs; do
    for e in "$L/$d"/*; do
      [ -e "$e" ] && [ ! -L "$e" ] || continue
      n=$(lc "${e##*/}"); case "$n" in "$v".*) echo "$e"; id=${n%.plist}; id=${id%.savedstate}; id=${id%.binarycookies}; ids="$ids$id"$'\n' ;; esac
    done
  done
  for id in $(printf '%s' "$ids" | sort -u); do
    [ "$(printf '%s' "$id" | awk -F. '{print NF}')" -ge 3 ] && name_ok "${id##*.}" && by_name "$L/Application Support" "${id##*.}"
  done
  n=${v#*.}
  if name_ok "$n"; then by_name "$L/Application Support" "$n"; by_name "$L" "$n"; fi
  if lo_interactive; then
    for e in "$L/Containers/$v".* "$L/Group Containers/group.$v".*; do [ -e "$e" ] && [ ! -L "$e" ] && echo "$e"; done
    for ((i = 0; i < O_N; i++)); do
      [ "${O_VENDOR[i]}" = "$v" ] && [ -e "${O_PROG[i]}" ] || continue
      t=$(team_of "${O_PROG[i]}"); [ -n "$t" ] || continue
      for e in "$L/Group Containers/$t".*; do [ -e "$e" ] && [ ! -L "$e" ] && echo "$e"; done
    done
  fi
}
data_cands(){
  local i v vs p s note n
  LO_NAMES=$(app_names | sed '/^$/d' | sort -u); LO_APPLE=$(apple_names | sed '/^$/d' | sort -u)
  vs=$(for ((i = 0; i < O_N; i++)); do [ "${O_REASON[i]}" != broken ] && [ -n "${O_VENDOR[i]}" ] && echo "${O_VENDOR[i]}|${O_NAME[i]}"; done | sort -u -t'|' -k1,1)
  while IFS='|' read -r v n; do
    [ -n "$v" ] || continue
    vendor_installed "$v" && continue
    p=$(data_paths "$v" | awk '!seen[$0]++'); [ -n "$p" ] || continue
    D_VENDOR[D_N]=$v; D_NAME[D_N]=$n; D_PATHS[D_N]=$p
    O_ALLOW="$O_ALLOW$p"$'\n'
    s=$(kbl "$(outer "$p")")
    note=$(_f 'What: settings, history, saved passwords and cookies of %s.' "$n"; echo
      _f 'Why: no app from %s is installed anymore.' "$n"; echo
      [ -n "$(printf '%s\n' "$p" | while IFS= read -r e; do find "$e" -maxdepth 4 \( -name 'Login Data' -o -name History -o -name Cookies \) 2>/dev/null; done | head -1)" ] \
        && { _ 'Note: move your passwords to another browser first if you need them.'; echo; }
      printf '%s\n' "$p" | grep '/Containers/\|/Group Containers/' >/dev/null && { _ 'Note: macOS may ask once for access.'; echo; }
      _ 'Safe: yes, it goes to the Trash.'; echo
      printf '%s\n' "$p" | while IFS= read -r e; do echo "@$(tildify "$e")"; done)
    CL_MANUAL=1 cand clean.orphan_data 3 "⚠ $n · $(_ 'data of a deleted app')" "$s" cmd "odata:$D_N" "" "" "" "$note"
    C_LOP[C_N - 1]=$p
    D_N=$((D_N + 1))
  done <<EOF2
$vs
EOF2
}
run_odata(){ # n
  local n=$1 s e
  apps_scan
  if vendor_installed "${D_VENDOR[n]}" || open_in "${D_PATHS[n]}"; then info '%s: still in use, skipped' "${D_NAME[n]} · $(_ 'data of a deleted app')"; return 2; fi
  s=$(kbl "${D_PATHS[n]}")
  while IFS= read -r e; do [ -n "$e" ] && { to_trash "$e" || return 1; }; done <<EOF2
${D_PATHS[n]}
EOF2
  KEY_FREED=$s
}

btm_stale(){ # names of this user's Background Task Management records whose app is gone; the format is undocumented, so no match means nothing
  lo_interactive && have sfltool || return 0   # it can wait on a system prompt: never in unattended runs
  btm_dump | awk -v u="$(id -u)" -v h="$HOME" '
    /Records for UID/ { on = ($4 == u); next }
    !on { next }
    /^ *Name: / { n = $0; sub(/^ *Name: /, "", n); next }
    /^ *URL: \// { p = $0; sub(/^ *URL: /, "", p); if (index(p, "/Users/" u "/") == 1) p = h substr(p, length("/Users/" u) + 1); print n "|" p }' |
  while IFS='|' read -r n p; do [ -e "$p" ] || echo "$n"; done | sort -u
}
btm_dump(){ # sfltool can hang without a word; ten seconds, then nothing
  local f p t=0
  f=$(mktemp "${TMPDIR:-/tmp}/macup-btm.XXXXXX") || return 0
  sfltool dumpbtm </dev/null >"$f" 2>/dev/null & p=$!
  while kill -0 "$p" 2>/dev/null && [ "$t" -lt 50 ]; do sleep 0.2; t=$((t + 1)); done
  kill "$p" 2>/dev/null; wait "$p" 2>/dev/null
  cat "$f"; rm -f "$f"
}

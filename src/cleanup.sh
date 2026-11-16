# ================================================================ CLEANUP
# Two phases. First every cleaner registers a candidate: what, how big, how risky.
# Then the chosen candidates run: `clean`/`all` take every enabled one up to --level,
# an interactive `check` lets you pick at the end. Levels:
#   1 safe        rebuilds itself, nothing to notice
#   2 standard    downloaded again on next use (time, traffic)
#   3 aggressive  apps get slower for a while or sign you out
C_N=0; COVERED=""; DID_CLEAN=0; POT_AUTO=0; POT_MORE=0
C_TASK=(); C_BUSY=(); C_LVL=(); C_AUTO=(); C_LBL=(); C_KB=(); C_KIND=(); C_PATHS=(); C_PROC=(); C_MDIR=(); C_OPEN=(); C_KEY=()
# Build folders macup may delete inside project_dirs, each only next to the file that makes it again.
ARTIFACT_NAMES='node_modules Pods .build .dart_tool .next target build'
artifact_ok(){ # path → true when it is a build folder with its build file next to it
  local d=${1%/*}
  case "${1##*/}" in
    node_modules) ;;
    Pods)       [ -e "$d/Podfile" ] ;;
    .build)     [ -e "$d/Package.swift" ] ;;
    .dart_tool) [ -e "$d/pubspec.yaml" ] ;;
    .next)      [ -e "$d/package.json" ] ;;
    target)     [ -e "$d/Cargo.toml" ] || [ -e "$d/pom.xml" ] ;;
    build)      [ -e "$d/build.gradle" ] || [ -e "$d/build.gradle.kts" ] ;;
    *) return 1 ;;
  esac
}
# Only these places, and never these names, whatever a cleaner asks for.
safe_path(){
  case "$1" in
    "$HOME"/Library/*|"$HOME"/.*) ;;
    *) in_projects "$1" && artifact_ok "$1" || return 1 ;;   # clean.stale_*: a build folder inside project_dirs, nothing else there
  esac
  case "$1" in */../*|*/..|*/.codex/sessions*|*/.codex/archived_sessions*|*/deno/location_data|*/deno/location_data/*|*.sqlite|*/User|*/User/*|*/Backups|*/Backups/*|\
    */gradle.properties|*/settings.xml|*/.android/avd*|*/.android/*key*|*/.ssh*|*/.gnupg*|*/Keychains*|*/.aws|*/.aws/*|*/.kube|*/.kube/*|*/.netrc|*/.config|*/.config/*|*/.claude|*/.claude/*|*/org.sparkle-project.Sparkle|*/org.sparkle-project.Sparkle/*|*.ShipIt|*.ShipIt/*) return 1 ;; esac   # updaters keep downloaded updates here until installed
  # in Application Support only what sits in a Chromium/Electron cache folder: never profiles or app data
  case "$1" in "$HOME/Library/Application Support/"*) in_cache_dir "${1#"$HOME/Library/Application Support"}" || return 1 ;; esac
  return 0
}
in_cache_dir(){ local n; while IFS= read -r n; do case "$1/" in *"/$n/"*) return 0 ;; esac; done <<EOF2
$(printf '%s\n' "$ELECTRON_CACHES" | tr '|' '\n')
EOF2
  return 1; }
project_roots(){ # the folders in project_dirs that exist; never the home folder itself or anything above it
  echo "$PROJECT_DIRS" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | while IFS= read -r d; do
    d=$(expand "$d"); d=${d%/}
    case "$d" in ""|"$HOME") continue ;; esac
    case "$HOME/" in "$d"/*) continue ;; esac
    [ -d "$d" ] && echo "$d"
  done
}
in_projects(){ local r; while IFS= read -r r; do [ -n "$r" ] && case "$1" in "$r"/*) return 0 ;; esac; done <<EOF2
$(project_roots)
EOF2
  return 1; }
kbl(){ local s=0 p; while IFS= read -r p; do [ -n "$p" ] && [ ! -L "$p" ] && s=$((s + $(kb "$p"))); done <<EOF2
$1
EOF2
  echo "$s"; }
# The big folders are measured together in the background while the rest is looked at; kb_get waits for the result.
# Only before anything is deleted: exec_cand forgets them, so sizes before and after a cleanup are measured anew.
KBP_N=0; KBP_PATH=(); KBP_PID=(); KBP_SUB=(); KB=0
kb_bg(){ # path [sub] — sub: also each folder inside it, in the same walk
  [ -n "$BODY" ] && [ -d "$1" ] && [ ! -L "$1" ] || return 0
  local i; for ((i = 0; i < KBP_N; i++)); do
    [ "${KBP_PATH[i]}" = "$1" ] && return 0
    [ -n "${KBP_SUB[i]}" ] && [ "${KBP_PATH[i]}" = "${1%/*}" ] && return 0
  done
  if [ -n "$2" ]; then du -k -d 1 "$1" >"$BODY.du.$KBP_N" 2>/dev/null &
  else du -sk "$1" >"$BODY.du.$KBP_N" 2>/dev/null &
  fi
  KBP_PID[KBP_N]=$!; KBP_PATH[KBP_N]=$1; KBP_SUB[KBP_N]=$2; KBP_N=$((KBP_N + 1))
}
kb_get(){ # path → KB; call it outside $( ): only this shell can wait for its background jobs
  local i v; KB=""
  for ((i = 0; i < KBP_N; i++)); do
    if [ "${KBP_PATH[i]}" = "$1" ]; then wait "${KBP_PID[i]}" 2>/dev/null; v=$(tail -1 "$BODY.du.$i" 2>/dev/null | awk '{print $1}')
    elif [ -n "${KBP_SUB[i]}" ] && [ "${KBP_PATH[i]}" = "${1%/*}" ]; then wait "${KBP_PID[i]}" 2>/dev/null; v=$(awk -F'\t' -v p="$1" '$2 == p {print $1; exit}' "$BODY.du.$i" 2>/dev/null)
    else continue; fi
    case "$v" in ''|*[!0-9]*) ;; *) KB=$v; return 0 ;; esac
  done
  KB=$(kb "$1")
}
kb_has(){ local i; for ((i = 0; i < KBP_N; i++)); do
  [ "${KBP_PATH[i]}" = "$1" ] || { [ -n "${KBP_SUB[i]}" ] && [ "${KBP_PATH[i]}" = "${1%/*}" ]; } && return 0; done; return 1; }
settle(){ # sizes the candidates registered with "?" (their du ran meanwhile) and drops folders under clean_dir's 5 MB
  local i j=0 a
  for ((i = 0; i < C_N; i++)); do
    if [ "${C_KB[i]}" = "?" ]; then
      if [ "${C_KIND[i]}" = cmd ]; then kb_get "${C_MDIR[i]}"; else kb_get "${C_PATHS[i]}"; fi
      C_KB[i]=$KB; [ "${C_KIND[i]}" = empty ] && [ "$KB" -lt 5120 ] && continue
    fi
    if [ "$j" != "$i" ]; then for a in C_TASK C_LVL C_AUTO C_LBL C_KB C_KIND C_PATHS C_PROC C_MDIR C_OPEN C_KEY; do eval "${a}[j]=\${${a}[i]}"; done; fi
    j=$((j + 1))
  done
  for ((i = j; i < C_N; i++)); do for a in C_TASK C_LVL C_AUTO C_LBL C_KB C_KIND C_PATHS C_PROC C_MDIR C_OPEN C_KEY; do unset "${a}[i]"; done; done
  C_N=$j
}
cover(){ COVERED="$COVERED$1"$'\n'; }
cand(){ # task level label kb kind paths [proc] [measure-dir] [open-dirs] — kind: empty (dirs) | rm (paths) | cmd (key)
  task_allowed "$1" || return 0
  C_TASK[C_N]=$1; C_LVL[C_N]=$2; C_LBL[C_N]=$3; C_KB[C_N]=$4; C_KIND[C_N]=$5; C_PATHS[C_N]=$6; C_PROC[C_N]=$7; C_MDIR[C_N]=$8; C_OPEN[C_N]=$9
  if task "$1" && [ -z "$CL_MANUAL" ]; then C_AUTO[C_N]=1; else C_AUTO[C_N]=0; fi
  # the same item gets the same key on the next run: CL_KEY names the ones whose paths change from day to day (old logs)
  C_KEY[C_N]="$1:$(printf '%s' "${CL_KEY:-$5|$6}" | cksum | cut -d' ' -f1)"
  [ "$5" = cmd ] || cover "$6"
  C_N=$((C_N + 1))
}
cand_more(){ # label level kb paths open-dirs — adds to the candidate with this label and level; false if there is none
  local i; for ((i = 0; i < C_N; i++)); do
    [ "${C_LBL[i]}" = "$1" ] && [ "${C_LVL[i]}" = "$2" ] && [ "${C_KIND[i]}" = empty ] && [ "${C_KB[i]}" != "?" ] || continue
    C_KB[i]=$((C_KB[i] + $3)); C_PATHS[i]="${C_PATHS[i]}"$'\n'"$4"; C_OPEN[i]="${C_OPEN[i]}${C_OPEN[i]:+$'\n'}$5"; cover "$4"; return 0
  done; return 1
}
# Xcode itself, or an xcodebuild started from a terminal or a CI agent: both write to DerivedData while they run
XCODE_BUSY='/Xcode.app/Contents/MacOS/Xcode|(^|/)xcodebuild( |$)'
busy_pat(){ # a name from the tables → the pgrep -f pattern of what uses that cache while it runs
  case "$1" in
    xcode)  echo "$XCODE_BUSY" ;;
    cargo)  echo '(^|/)(cargo|rustc)( |$)' ;;
    poetry) echo '(^|/)poetry( |$)' ;;
    maven)  echo 'plexus\.classworlds|(^|/)mvnd?( |$)' ;;
    deno)   echo '(^|/)deno( |$)' ;;
    npx)    echo '/\.npm/_npx/' ;;   # MCP servers and CLIs started with npx run from there
    *)      echo "$1" ;;
  esac
}
running(){ [ -n "$1" ] && pgrep -f "$1" >/dev/null 2>&1; }
# macOS's own watchers (UserEventAgent, Spotlight, fseventsd) keep folders open whether or not their app runs: not "in use"
lsof_snap(){ lsof -n -P -Fcn -u "$(id -u)" 2>/dev/null | awk '/^p/ { w = 0 } /^c/ { w = ($0 ~ /^c(UserEventAgent|mds|mds_stores|mdworker|mdworker_shared|fseventsd|revisiond|backupd|quicklookd)$/) } /^n/ && !w' >"$1"; }
open_in(){ # folders, one per line [a file with lsof's output, taken already]: true if a process has a file open in one of them, or if lsof cannot tell
  [ -n "$1" ] || return 1
  local f=${2:-$BODY.du.lsof} d
  [ -n "$2" ] || lsof_snap "$f"
  [ -s "$f" ] || return 0
  while IFS= read -r d; do [ -n "$d" ] && grep -qF "n$d/" "$f" && return 0; done <<EOF2
$1
EOF2
  return 1
}

# --- registering helpers (the old call sites stay as they were)
clean_dir(){ # id label path [proc] — empty a folder that rebuilds itself
  local p=$3 s proc; proc=$(busy_pat "$4")
  task_allowed "$1" || return 0
  [ -d "$p" ] && [ ! -L "$p" ] && safe_path "$p" || return 0
  if kb_has "$p"; then s="?"; else s=$(kb "$p"); [ "$s" -lt 5120 ] && return 0; fi   # ?: sized by settle, its du runs meanwhile
  cand "$1" "${CL_LVL:-1}" "$(_ "$2")" "$s" empty "$p" "$proc"
}
clean_old(){ # id label dir days [type] — entries older than N days
  local p=$3 days=$4 type=${5:-d} old s
  task_allowed "$1" || return 0
  [ -d "$p" ] && [ ! -L "$p" ] && safe_path "$p" || return 0
  old=$(find "$p" -mindepth 1 -maxdepth 1 -type "$type" -mtime +"$days" 2>/dev/null)
  [ -z "$old" ] && return 0
  s=$(kbl "$old"); [ "$s" -lt 1024 ] && return 0
  CL_KEY="old|$p" cand "$1" "${CL_LVL:-1}" "$(_f '%s (%s items, older than %s days)' "$(_ "$2")" "$(cnt "$old")" "$days")" "$s" rm "$old"
}
measure_cmd(){ # id label dir key — a tool's own clean command; the dir is measured before and after
  task_allowed "$1" && [ -e "$3" ] || return 0
  local s="?"; kb_has "$3" || s=$(kb "$3")
  cand "$1" "${CL_LVL:-1}" "$(_ "$2")" "$s" cmd "$4" "" "$3"
}

# --- running
KEY_FREED=""; REFUSED=0
run_key(){ local out r=0
  case "$1" in
    sim:*)     case "$1" in *default*) run xcrun simctl delete unavailable || r=1 ;; esac   # sim:[default] [tests]: the sets that have some
               case "$1" in *tests*) run xcrun simctl --set "$DEV/XCTestDevices" delete unavailable || r=1 ;; esac
               return $r ;;
    brew)      out=$(brew cleanup -s --prune=7 2>&1); echo "$out" >>"$RAW"
               KEY_FREED=$(tokb "$(echo "$out" | grep -o 'freed approximately [0-9.]*[KMGT]*B' | tail -1 | awk '{print $3}')") ;;
    npm)       run npm cache verify ;;
    pnpm)      run pnpm store prune ;;
    pip)       run pip3 cache purge ;;
    uv)        run uv cache prune ;;
    go)        run go clean -cache ;;
    gomod)     run go clean -modcache ;;
    brewauto)  run brew autoremove ;;
    dockerct)  out=$(docker container prune -f 2>&1) || r=1; echo "$out" >>"$RAW"
               KEY_FREED=$(tokb10 "$(echo "$out" | sed -n 's/^Total reclaimed space: *//p' | tail -1)"); return $r ;;
    dockerimg) out=$(docker image prune -a -f 2>&1) || r=1; echo "$out" >>"$RAW"
               KEY_FREED=$(tokb10 "$(echo "$out" | sed -n 's/^Total reclaimed space: *//p' | tail -1)"); return $r ;;
    quicklook) run qlmanage -r cache ;;
    simrt:*)    set -- ${1#simrt:}; sim_id "$1" && run xcrun simctl runtime delete "$1" && KEY_FREED=$2 ;;   # simrt:<id> <kb>
    simerase:*) for u in ${1#simerase:}; do sim_id "$u" && run xcrun simctl erase "$u" || return 1; done ;;
    simdel:*)   for u in ${1#simdel:}; do sim_id "$u" && run xcrun simctl delete "$u" || return 1; done ;;
    docker)    out=$({ docker builder prune -f || exit 1; docker image prune -f; } 2>&1) || r=1; echo "$out" >>"$RAW"
               KEY_FREED=$(echo "$out" | sed -n 's/^Total reclaimed space: *//p' | while read -r v; do tokb10 "$v"; echo; done | awk '{s+=$1} END{print s+0}'); return $r ;;
  esac
}
sim_id(){ case "$1" in ""|*[!0-9A-Fa-f-]*) echo "macup refused simulator id: $1" >>"$RAW"; return 1 ;; esac; }
del(){ # one path, re-checked right before deleting; symlinks are never followed or removed
  [ -L "$1" ] && return 0
  [ -e "$1" ] || return 0
  safe_path "$1" || { echo "macup refused to delete: $1" >>"$RAW"; REFUSED=$((REFUSED + 1)); return 0; }
  rm -rf "$1" 2>>"$RAW"
}
exec_cand(){ # index
  local i=$1 lbl=${C_LBL[$1]} b a d p
  KBP_N=0
  if running "${C_PROC[i]}" || open_in "${C_OPEN[i]}"; then
    info '%s: %s — skipped while the app is open' "$lbl" "$(hum "${C_KB[i]}")"
    SKIPPED+=("$lbl ($(hum "${C_KB[i]}"))"); return 0
  fi
  step '%s' "$lbl"
  case "${C_KIND[i]}" in
    empty) b=$(kbl "${C_PATHS[i]}")
           while IFS= read -r d; do
             [ -d "$d" ] && [ ! -L "$d" ] && safe_path "$d" || continue
             find "$d" -mindepth 1 -maxdepth 1 2>/dev/null | while IFS= read -r p; do del "$p"; done
           done <<EOF2
${C_PATHS[i]}
EOF2
           a=$(kbl "${C_PATHS[i]}") ;;
    rm)    b=$(kbl "${C_PATHS[i]}"); REFUSED=0
           while IFS= read -r p; do [ -n "$p" ] && del "$p"; done <<EOF2
${C_PATHS[i]}
EOF2
           a=$(kbl "${C_PATHS[i]}")
           # never "cleaned" for something macup would not touch
           if [ "$REFUSED" -gt 0 ] && [ "$a" -ge "$b" ]; then err '%s: nothing removed, the path is outside what macup may delete (see the report)' "$lbl"; return 0; fi ;;
    cmd)   KEY_FREED=""; b=0; a=0; [ -n "${C_MDIR[i]}" ] && b=$(kbl "${C_MDIR[i]}")
           if ! run_key "${C_PATHS[i]}"; then err '%s: failed (see the report)' "$lbl"; return 0; fi
           [ -n "${C_MDIR[i]}" ] && a=$(kbl "${C_MDIR[i]}")
           [ -n "$KEY_FREED" ] && { b=$KEY_FREED; a=0; } ;;
  esac
  d=$((b - a)); [ "$d" -lt 0 ] && d=0
  FREED=$((FREED + d)); DID_CLEAN=1
  if [ "$d" -ge 1024 ]; then ok '%s: freed %s' "$lbl" "$(hum "$d")"; else ok '%s: cleaned' "$lbl"; fi
}
lvl_word(){ case "$1" in 1) _ 'safe' ;; 2) _ 'standard' ;; *) _ 'aggressive' ;; esac; }
lvl_col(){ case "$1" in 1) printf '%s' "$G" ;; 2) printf '%s' "$Y" ;; *) printf '%s' "$R" ;; esac; }
mark_busy(){ # check: what is in use right now is said in the list and left out of the totals; exec_cand asks again before it cleans
  local i s="$BODY.du.busy"; : >"$s"
  for ((i = 0; i < C_N; i++)); do [ -n "${C_OPEN[i]}" ] && { lsof_snap "$s"; break; }; done
  for ((i = 0; i < C_N; i++)); do
    C_BUSY[i]=0
    # lsof that cannot tell makes the cleanup skip it, but the list does not call it in use
    if running "${C_PROC[i]}" || { [ -s "$s" ] && open_in "${C_OPEN[i]}" "$s"; }; then C_BUSY[i]=1; fi
  done
}
visible(){ [ "${C_KB[$1]}" -ge 1024 ] || { [ "${C_KIND[$1]}" = cmd ] && [ "${C_AUTO[$1]}" = 0 ]; } || [ "${C_TASK[$1]}" = clean.profiles ]; }   # small pick-only commands too; expired profiles are junk at any size
list_cands(){ # numbered list of what can be cleaned
  local i n=0 tag
  for ((i = 0; i < C_N; i++)); do
    visible "$i" || continue
    n=$((n + 1)); tag=""; [ "${C_AUTO[i]}" = 0 ] && tag=" $(_ '(only if you pick it)')"
    [ "${C_BUSY[i]:-0}" = 1 ] && tag="$tag $(_ '(in use now — skipped until it is closed)')"
    flush
    printf '%s  %3s  %s%s%s %9s  %s%s%s%s\n' "$CL" "$n" "$(lvl_col "${C_LVL[i]}")" "$(pad "$(lvl_word "${C_LVL[i]}")" 11)" "$N" "$(hum "${C_KB[i]}")" "${C_LBL[i]}" "$D" "$tag" "$N"
    md "- $n. [$(lvl_word "${C_LVL[i]}")] ${C_LBL[i]}: $(hum "${C_KB[i]}")$tag"
  done
}
vis_index(){ # visible number → index
  local i n=0; for ((i = 0; i < C_N; i++)); do visible "$i" || continue; n=$((n + 1)); [ "$n" = "$1" ] && { echo "$i"; return; }; done
}
pick(){ # reads a choice, prints the chosen indexes one per line
  local ans tok i a b lv
  ans=$(ask "$(_ 'Clean now? Numbers (1,3 or 2-5), a level (safe, standard, aggressive), or Enter to skip: ')")
  for tok in $(echo "$ans" | tr ',' ' '); do
    lv=""; case "$tok" in safe|"$(_ safe)") lv=1 ;; standard|"$(_ standard)") lv=2 ;; aggressive|"$(_ aggressive)") lv=3 ;; esac
    if [ -n "$lv" ]; then
      for ((i = 0; i < C_N; i++)); do [ "${C_AUTO[i]}" = 1 ] && [ "${C_LVL[i]}" -le "$lv" ] && echo "$i"; done
    elif echo "$tok" | grep -qE '^[0-9]{1,4}(-[0-9]{1,4})?$'; then
      a=$((10#${tok%-*})); b=$((10#${tok#*-})); [ "$b" -gt "$C_N" ] && b=$C_N   # 08 is not octal; 1-9999 does not loop for minutes
      while [ "$a" -le "$b" ]; do i=$(vis_index "$a"); [ -n "$i" ] && echo "$i"; a=$((a + 1)); done
    fi
  done | sort -un
}


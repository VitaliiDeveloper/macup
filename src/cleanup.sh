# ================================================================ CLEANUP
# Two phases. First every cleaner registers a candidate: what, how big, how risky.
# Then the chosen candidates run: `clean`/`all` take every enabled one up to --level,
# an interactive `check` lets you pick at the end. Levels:
#   1 safe        rebuilds itself, nothing to notice
#   2 standard    downloaded again on next use (time, traffic)
#   3 aggressive  apps get slower for a while or sign you out
C_N=0; COVERED=""; DID_CLEAN=0; POT_AUTO=0; POT_MORE=0
C_TASK=(); C_LVL=(); C_AUTO=(); C_LBL=(); C_KB=(); C_KIND=(); C_PATHS=(); C_PROC=(); C_MDIR=(); C_OPEN=()
# Only these places, and never these names, whatever a cleaner asks for.
safe_path(){
  case "$1" in "$HOME"/Library/*|"$HOME"/.*) ;; *) return 1 ;; esac
  case "$1" in */../*|*/..|*/.codex/sessions*|*/.codex/archived_sessions*|*.sqlite|*/User|*/User/*|*/Backups|*/Backups/*|\
    */gradle.properties|*/settings.xml|*/.android/avd*|*/.android/*key*|*/.ssh*|*/.gnupg*|*/Keychains*|*/org.sparkle-project.Sparkle|*/org.sparkle-project.Sparkle/*|*.ShipIt|*.ShipIt/*) return 1 ;; esac   # updaters keep downloaded updates here until installed
  # in Application Support only what sits in a Chromium/Electron cache folder: never profiles or app data
  case "$1" in "$HOME/Library/Application Support/"*) in_cache_dir "${1#"$HOME/Library/Application Support"}" || return 1 ;; esac
  return 0
}
in_cache_dir(){ local n; while IFS= read -r n; do case "$1/" in *"/$n/"*) return 0 ;; esac; done <<EOF2
$(printf '%s\n' "$ELECTRON_CACHES" | tr '|' '\n')
EOF2
  return 1; }
kbl(){ local s=0 p; while IFS= read -r p; do [ -n "$p" ] && [ ! -L "$p" ] && s=$((s + $(kb "$p"))); done <<EOF2
$1
EOF2
  echo "$s"; }
cover(){ COVERED="$COVERED$1"$'\n'; }
cand(){ # task level label kb kind paths [proc] [measure-dir] [open-dirs] — kind: empty (dirs) | rm (paths) | cmd (key)
  task_allowed "$1" || return 0
  C_TASK[C_N]=$1; C_LVL[C_N]=$2; C_LBL[C_N]=$3; C_KB[C_N]=$4; C_KIND[C_N]=$5; C_PATHS[C_N]=$6; C_PROC[C_N]=$7; C_MDIR[C_N]=$8; C_OPEN[C_N]=$9
  if task "$1" && [ -z "$CL_MANUAL" ]; then C_AUTO[C_N]=1; else C_AUTO[C_N]=0; fi
  [ "$5" = cmd ] || cover "$6"
  C_N=$((C_N + 1))
}
cand_more(){ # label level kb paths open-dirs — adds to the candidate with this label and level; false if there is none
  local i; for ((i = 0; i < C_N; i++)); do
    [ "${C_LBL[i]}" = "$1" ] && [ "${C_LVL[i]}" = "$2" ] && [ "${C_KIND[i]}" = empty ] || continue
    C_KB[i]=$((C_KB[i] + $3)); C_PATHS[i]="${C_PATHS[i]}"$'\n'"$4"; C_OPEN[i]="${C_OPEN[i]}${C_OPEN[i]:+$'\n'}$5"; cover "$4"; return 0
  done; return 1
}
running(){ [ -n "$1" ] && pgrep -f "$1" >/dev/null 2>&1; }
open_in(){ # folders, one per line: true if a process has a file open in one of them, or if lsof cannot tell
  [ -n "$1" ] || return 1
  local s d; s=$(lsof -n -P -Fn -u "$(id -u)" 2>/dev/null); [ -n "$s" ] || return 0
  while IFS= read -r d; do [ -n "$d" ] && printf '%s\n' "$s" | grep -qF "n$d/" && return 0; done <<EOF2
$1
EOF2
  return 1
}

# --- registering helpers (the old call sites stay as they were)
clean_dir(){ # id label path [proc] — empty a folder that rebuilds itself
  local p=$3 s proc=$4; [ "$proc" = xcode ] && proc='/Xcode.app/Contents/MacOS/Xcode'
  [ -d "$p" ] && [ ! -L "$p" ] && safe_path "$p" || return 0
  s=$(kb "$p"); [ "$s" -lt 5120 ] && return 0
  cand "$1" "${CL_LVL:-1}" "$(_ "$2")" "$s" empty "$p" "$proc"
}
clean_old(){ # id label dir days [type] — entries older than N days
  local p=$3 days=$4 type=${5:-d} old s
  [ -d "$p" ] && [ ! -L "$p" ] && safe_path "$p" || return 0
  old=$(find "$p" -mindepth 1 -maxdepth 1 -type "$type" -mtime +"$days" 2>/dev/null)
  [ -z "$old" ] && return 0
  s=$(kbl "$old"); [ "$s" -lt 1024 ] && return 0
  cand "$1" "${CL_LVL:-1}" "$(_f '%s (%s items, older than %s days)' "$(_ "$2")" "$(cnt "$old")" "$days")" "$s" rm "$old"
}
measure_cmd(){ # id label dir key — a tool's own clean command; the dir is measured before and after
  [ -e "$3" ] || return 0
  cand "$1" "${CL_LVL:-1}" "$(_ "$2")" "$(kb "$3")" cmd "$4" "" "$3"
}

# --- running
KEY_FREED=""
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
    quicklook) run qlmanage -r cache ;;
    simrt:*)    set -- ${1#simrt:}; sim_id "$1" && run xcrun simctl runtime delete "$1" && KEY_FREED=$2 ;;   # simrt:<id> <kb>
    simerase:*) for u in ${1#simerase:}; do sim_id "$u" && run xcrun simctl erase "$u" || return 1; done ;;
    simdel:*)   for u in ${1#simdel:}; do sim_id "$u" && run xcrun simctl delete "$u" || return 1; done ;;
    docker)    out=$({ docker builder prune -f; docker image prune -f; } 2>&1); echo "$out" >>"$RAW"
               KEY_FREED=$(echo "$out" | sed -n 's/^Total reclaimed space: *//p' | while read -r v; do tokb "$v"; echo; done | awk '{s+=$1} END{print s+0}') ;;
  esac
}
sim_id(){ case "$1" in ""|*[!0-9A-Fa-f-]*) echo "macup refused simulator id: $1" >>"$RAW"; return 1 ;; esac; }
del(){ # one path, re-checked right before deleting; symlinks are never followed or removed
  [ -L "$1" ] && return 0
  [ -e "$1" ] || return 0
  safe_path "$1" || { echo "macup refused to delete: $1" >>"$RAW"; return 0; }
  rm -rf "$1" 2>>"$RAW"
}
exec_cand(){ # index
  local i=$1 lbl=${C_LBL[$1]} b a d p
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
    rm)    b=$(kbl "${C_PATHS[i]}")
           while IFS= read -r p; do [ -n "$p" ] && del "$p"; done <<EOF2
${C_PATHS[i]}
EOF2
           a=$(kbl "${C_PATHS[i]}") ;;
    cmd)   KEY_FREED=""; b=0; a=0; [ -n "${C_MDIR[i]}" ] && b=$(kbl "${C_MDIR[i]}")
           if ! run_key "${C_PATHS[i]}"; then warn '%s: failed (see log)' "$lbl"; return 0; fi
           [ -n "${C_MDIR[i]}" ] && a=$(kbl "${C_MDIR[i]}")
           [ -n "$KEY_FREED" ] && { b=$KEY_FREED; a=0; } ;;
  esac
  d=$((b - a)); [ "$d" -lt 0 ] && d=0
  FREED=$((FREED + d)); DID_CLEAN=1
  if [ "$d" -ge 1024 ]; then ok '%s: freed %s' "$lbl" "$(hum "$d")"; else ok '%s: cleaned' "$lbl"; fi
}
lvl_word(){ case "$1" in 1) _ 'safe' ;; 2) _ 'standard' ;; *) _ 'aggressive' ;; esac; }
lvl_col(){ case "$1" in 1) printf '%s' "$G" ;; 2) printf '%s' "$Y" ;; *) printf '%s' "$R" ;; esac; }
visible(){ [ "${C_KB[$1]}" -ge 1024 ] || { [ "${C_KIND[$1]}" = cmd ] && [ "${C_AUTO[$1]}" = 0 ]; }; }   # small pick-only commands too
list_cands(){ # numbered list of what can be cleaned
  local i n=0 tag
  for ((i = 0; i < C_N; i++)); do
    visible "$i" || continue
    n=$((n + 1)); tag=""; [ "${C_AUTO[i]}" = 0 ] && tag=" $(_ '(only if you pick it)')"
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
    elif echo "$tok" | grep -qE '^[0-9]+(-[0-9]+)?$'; then
      a=${tok%-*}; b=${tok#*-}
      while [ "$a" -le "$b" ]; do i=$(vis_index "$a"); [ -n "$i" ] && echo "$i"; a=$((a + 1)); done
    fi
  done | sort -un
}


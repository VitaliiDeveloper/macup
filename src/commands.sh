# ---------------------------------------------------------------- small commands
list_tasks(){
  local id def desc st
  load_conf
  printf '%s%s %s %s%s\n' "$B" "$(pad "$(_ 'TASK')" 26)" "$(pad "$(_ 'STATE')" 6)" "$(_ 'WHAT IT DOES')" "$N"
  while IFS='|' read -r id def desc; do
    if task "$id"; then st="$G$(pad "$(_ 'on')" 6)$N"; else st="$D$(pad "$(_ 'off')" 6)$N"; fi
    printf '%s %s %s\n' "$(pad "$id" 26)" "$st" "$(_ "$desc")"
  done <<EOF
$TASKS
EOF
  printf '\n'; _f 'Turn tasks off or on in %s (skip = … / enable = …)' "$(tildify "$CONF")"; printf '\n'
}

write_default_conf(){
  mkdir -p "$CONF_DIR"
  cat >"$CONF" <<EOF
# macup config. Lines starting with # are comments.
# See every task id with:  macup tasks

# Interface language: en, uk, ru
language = $MSG_LANG

# Tasks to never run. Whole groups work too: update.*, clean.*, check.*
skip =

# Opt-in tasks to turn on, e.g.: clean.stale_node_modules, clean.trash
enable =

# What `macup clean` / `macup all` may remove: safe, standard, aggressive
#   safe        rebuilds itself (DerivedData, package caches, logs)
#   standard    downloaded again on next use (Gradle, Maven, old Node/Ruby/Python patches)
#   aggressive  browser caches; apps may be slower for a while or sign you out
clean_level = safe

# Delete DeviceSupport folders older than this many days
device_support_days = 90

# Offer to delete simulators nobody used for this many days
simulator_days = 30

# A project counts as stale when nothing in it changed for this many days
stale_project_days = 90

# Where your code lives (used by --deep and clean.stale_node_modules)
project_dirs = ~/Developer, ~/Projects, ~/Code, ~/dev, ~/src, ~/repos, ~/work

# Keep macup reports for this many days
keep_reports_days = 60
EOF
}

open_conf(){
  [ -f "$CONF" ] || { write_default_conf; _f 'Created %s' "$(tildify "$CONF")"; echo; }
  # shellcheck disable=SC2086 # $EDITOR may carry arguments, e.g. "code -w"
  if [ -t 0 ] && [ -t 1 ]; then ${VISUAL:-${EDITOR:-nano}} "$CONF"; else echo "$CONF"; fi
}

choose_lang(){ # [code]
  local c="$1"
  if [ -z "$c" ]; then
    { : </dev/tty; } 2>/dev/null || { echo "macup lang en|uk|ru"; return 2; }
    printf '\n  1  English\n  2  Українська\n  3  Русский\n\n'
    c=$(ask "Language / Мова / Язык [1-3]: ")
    case "$c" in 1|en) c=en ;; 2|uk|ua) c=uk ;; 3|ru) c=ru ;; *) echo "—"; return 1 ;; esac
  fi
  case "$c" in en|uk|ru) ;; ua) c=uk ;; *) echo "en | uk | ru"; return 1 ;; esac
  conf_set language "$c"; MSG_LANG=$c; load_lang
  _f 'Language: %s' "$(lang_name "$c")"; echo
}

show_last(){
  local f; f=$(ls -t "$LOGDIR"/macup_*.md 2>/dev/null | head -1)
  if [ -n "$f" ]; then cat "$f"; else _ 'No reports yet. Run: macup check'; echo; fi
}

show_history(){
  [ -s "$HISTORY" ] || { _ 'No history yet. Every run adds a line; run: macup check'; echo; return; }
  printf '%s%s%s  (%s)\n\n' "$B" "$(_ 'Last runs')" "$N" "$(tildify "$HISTORY")"
  printf '%s%s%s%s%s%s%s%s%s%s%s\n' "$B" "$(pad "$(_ 'DATE')" 18)" "$(pad "$(_ 'MODE')" 11)" "$(pad "$(_ 'FREE')" 11)" \
    "$(pad "$(_ 'CHANGE')" 11)" "$(pad "$(_ 'SWAP')" 10)" "$(pad "$(_ 'BATTERY')" 9)" "$(pad "$(_ 'UPDATED')" 9)" "$(pad "$(_ 'FREED')" 10)" "$(_ 'WARN')" "$N"
  tail -n 15 "$HISTORY" | awk -F, -v b="$B" -v n="$N" -v trend="$(_ 'Free space trend:')" '
    function h(k){ if(k<0) return "-" h(-k); b=k*1024; if(b>=1e9) return sprintf("%.1f GB",b/1e9); if(b>=1e6) return sprintf("%.0f MB",b/1e6); return sprintf("%d KB",b/1e3) }
    { chg = (NR>1) ? h($3-prev) : "";  prev=$3
      bat = ($8!="") ? $8 "%" : "-"
      printf "%-18s%-11s%-11s%-11s%-10s%-9s%-9s%-10s%s\n", $1,$2,h($3),chg,$6 " MB",bat,$9,h($10),$11
      v[NR]=$3 }
    END{ if(NR<2) exit; min=v[1]; max=v[1]; for(i=1;i<=NR;i++){ if(v[i]<min)min=v[i]; if(v[i]>max)max=v[i] }
      split("▁ ▂ ▃ ▄ ▅ ▆ ▇ █", c, " "); s=""
      for(i=1;i<=NR;i++){ k=(max==min)?4:int((v[i]-min)/(max-min)*7)+1; s=s c[k] }
      printf "\n%s%s%s %s  (%s … %s)\n", b, trend, n, s, h(min), h(max) }'
}

ver_gt(){ # true when version $1 is newer than $2
  [ -n "$1" ] && [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)" = "$1" ]
}
resolve_self(){ local p="$0"; case "$p" in */*) ;; *) p=$(command -v "$p") ;; esac; echo "$p"; }

self_update(){
  local tmp newv target
  case "$MACUP_REPO" in __*) _ 'This copy has no GitHub repo configured.'; echo; exit 1 ;; esac
  tmp=$(mktemp "${TMPDIR:-/tmp}/macup.XXXXXX")
  if ! curl -fsSL --max-time 30 "$MACUP_RAW/macup" -o "$tmp"; then _f 'Download failed: %s' "$MACUP_RAW/macup"; echo; rm -f "$tmp"; exit 1; fi
  newv=$(sed -n 's/^MACUP_VERSION="\(.*\)"/\1/p' "$tmp" | head -1)
  if [ -z "$newv" ] || ! bash -n "$tmp" 2>/dev/null; then _ 'The downloaded file looks broken; nothing changed.'; echo; rm -f "$tmp"; exit 1; fi
  if ! ver_gt "$newv" "$MACUP_VERSION"; then _f 'macup %s is already the latest.' "$MACUP_VERSION"; echo; rm -f "$tmp"; exit 0; fi
  target=$(resolve_self)
  if install -m 755 "$tmp" "$target" 2>/dev/null; then _f 'macup updated: %s → %s' "$MACUP_VERSION" "$newv"; else _f "Couldn't write %s" "$target"; fi
  echo; rm -f "$tmp"
}

uninstall(){
  local target ans; target=$(resolve_self)
  ans=$(ask "$(_f 'Remove %s? [y/N] ' "$(tildify "$target")")")
  case "$ans" in y|Y|т|Т|д|Д) rm -f "$target" && { _ 'Removed.'; echo; } ;; *) _ 'Nothing removed.'; echo; return ;; esac
  ans=$(ask "$(_ 'Also remove config, history and reports? [y/N] ')")
  case "$ans" in y|Y|т|Т|д|Д) rm -rf "$CONF_DIR" "$STATE_DIR" "$LOGDIR" && { _ 'Removed config, history and reports.'; echo; } ;; esac
}

mline(){ # key label hint
  printf '  %s%s%s  %s%s%s%s\n' "$B" "$1" "$N" "$(pad "$(_ "$2")" 24)" "$D" "$( [ -n "$3" ] && _ "$3")" "$N"
}
menu(){
  local c
  printf '\n%smacup%s — %s %s(v%s · %s)%s\n\n' "$B" "$N" "$(_ 'keep your Mac healthy')" "$D" "$MACUP_VERSION" "$(lang_name "$MSG_LANG")" "$N"
  mline 1 'Check'            'health, security, updates, then pick what to clean'
  mline 2 'Update & clean'   'everything + report'
  mline 3 'Update only'      ''
  mline 4 'Clean only'       ''
  mline 5 'Deep check'       'also largest folders, Downloads, project artifacts'
  mline 6 'History & trends' ''
  mline 7 'Latest report'    ''
  mline 8 'Tasks & settings' 'what runs, how to turn things off'
  mline 9 'Language'         'English · Українська · Русский'
  mline h 'Help'             ''
  mline q 'Quit'             ''
  echo
  c=$(ask "$(_ 'Choose [1]: ')")
  case "${c:-1}" in
    1) DRY=1 ;; 2) ;; 3) DO_CLEAN=0 ;; 4) DO_UPDATE=0 ;; 5) DRY=1; DEEP=1 ;;
    6) show_history; exit 0 ;; 7) show_last; exit 0 ;;
    8) list_tasks; c=$(ask "$(_ 'Open the config now? [y/N] ')"); case "$c" in y|Y|т|Т|д|Д) open_conf ;; esac; exit 0 ;;
    9) choose_lang; exit 0 ;;
    h|H) usage; exit 0 ;; *) exit 0 ;;
  esac
}


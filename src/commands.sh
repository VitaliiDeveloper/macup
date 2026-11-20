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

# --json: the same lists for a program (a GUI); see "For scripts and other programs" in the README
tasks_json(){
  local id def desc on first=1
  load_conf; printf '{"schema":1,"config":"%s","tasks":[' "$(jstr "$CONF")"
  while IFS='|' read -r id def desc; do
    if task "$id"; then on=true; else on=false; fi
    [ $first = 1 ] || printf ','; first=0
    printf '{"id":"%s","group":"%s","default":"%s","on":%s,"text":"%s"}' "$id" "${id%%.*}" "$def" "$on" "$(jstr "$(_ "$desc")")"
  done <<EOF
$TASKS
EOF
  printf ']}\n'
}
history_json(){
  [ -s "$HISTORY" ] || { echo '{"schema":1,"runs":[]}'; return; }
  awk -F, 'function n(v){ return v == "" ? "null" : v + 0 }
    BEGIN{ printf "{\"schema\":1,\"runs\":[" }
    { printf "%s{\"date\":\"%s\",\"mode\":\"%s\",\"free_kb\":%s,\"total_kb\":%s,\"memory_free_pct\":%s,\"swap_mb\":%s,\"battery_cycles\":%s,\"battery_max_pct\":%s,\"updated\":%s,\"freed_kb\":%s,\"warnings\":%s}", \
        (NR > 1 ? "," : ""), $1, $2, n($3), n($4), n($5), n($6), n($7), n($8), n($9), n($10), n($11) }
    END{ print "]}" }' "$HISTORY"
}

write_default_conf(){
  mkdir -p "$CONF_DIR"
  # the heredoc expands \$MSG_LANG, so a backtick in it must be escaped: unescaped, bash runs what is between them
  cat >"$CONF" <<EOF
# macup config. Lines starting with # are comments.
# See every task id with:  macup tasks

# Interface language: en, uk, ru
language = $MSG_LANG

# Tasks to never run. Whole groups work too: update.*, clean.*, check.*
skip =

# Opt-in tasks to turn on, e.g.: clean.stale_node_modules, clean.trash
enable =

# What \`macup clean\` / \`macup all\` may remove: safe, standard, aggressive
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

# Keep macup reports for this many days, and at most this many runs (one file per run; remove them all: macup reports clean)
keep_reports_days = 30
keep_reports = 20

# Stop an update or cleanup command that runs longer than this many minutes (App Store installs get four times as long)
step_timeout_minutes = 60
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
  [ -n "$f" ] || { _ 'No reports yet. Run: macup check'; echo; return; }
  # the command output can be thousands of lines of brew: it stays in the file
  awk -v more="$(_f 'The command output is at the end of %s' "$(tildify "$f")")" '{ a[NR] = $0 }
    END { n = NR; for (i = 1; i <= NR; i++) if (a[i] ~ /^## / && a[i+2] == "~~~~") { n = i - 1; cut = 1; break }
      for (i = 1; i <= n; i++) print a[i]; if (cut) printf "%s\n", more }' "$f"
}

# macup's reports: one file per run in $LOGDIR (macup_<date>.md; .log files are left by versions before 2.9.0)
report_mode(){ sed -n '3s/^[^:]*: \([a-z+]*\) · macup .*/\1/p' "$1" 2>/dev/null; }
report_date(){ local b=${1##*/macup_}; b=${b%.*}; printf '%s %s:%s' "${b%%_*}" "$(echo "${b#*_}" | cut -d- -f1)" "$(echo "${b#*_}" | cut -d- -f2)"; }
reports(){ # [clean|open]
  local mds n kb f m ans first=1
  mds=$(ls "$LOGDIR"/macup_*.md 2>/dev/null); n=$(cnt "$mds")
  kb=$(find "$LOGDIR" -maxdepth 1 -type f \( -name 'macup_*.md' -o -name 'macup_*.log' \) -exec du -k {} + 2>/dev/null | awk '{s+=$1} END{print s+0}')
  case "$1" in
    "") ;;
    open)  mkdir -p "$LOGDIR"; open "$LOGDIR"; return 0 ;;
    clean) [ "$kb" -gt 0 ] || { _ 'Nothing to remove.'; echo; return 0; }
           _f 'Reports to remove: %s (%s) in %s' "$n" "$(hum "$kb")" "$(tildify "$LOGDIR")"; echo
           if [ "$YES" != 1 ]; then
             ans=""; { : </dev/tty; } 2>/dev/null && ans=$(ask "$(_ 'Remove them? [y/N] ')")
             case "$ans" in y|Y|т|Т|д|Д) ;; *) _ 'Nothing removed.'; echo; return 0 ;; esac
           fi
           find "$LOGDIR" -maxdepth 1 -type f \( -name 'macup_*.md' -o -name 'macup_*.log' \) -delete 2>/dev/null
           _ 'Removed.'; echo; return 0 ;;
    *)     echo "macup reports [clean|open] [--yes] [--json]"; return 2 ;;
  esac
  if [ "$JSON" = 1 ]; then
    printf '{"schema":1,"folder":"%s","count":%s,"kb":%s,"reports":[' "$(jstr "$LOGDIR")" "$n" "$kb"
    [ -n "$mds" ] && while IFS= read -r f; do
      [ $first = 1 ] || printf ','; first=0
      m=$(report_mode "$f"); [ -n "$m" ] && m="\"$m\""
      printf '{"file":"%s","date":"%s","mode":%s,"kb":%s}' "$(jstr "$f")" "$(report_date "$f")" "${m:-null}" \
        "$(du -k "$f" "${f%.md}.log" 2>/dev/null | awk '{s+=$1} END{print s+0}')"
    done <<EOF
$mds
EOF
    printf ']}\n'; return 0
  fi
  [ "$n" -gt 0 ] || { _ 'No reports yet. Run: macup check'; echo; return 0; }
  _f 'Reports: %s · %s · %s' "$n" "$(hum "$kb")" "$(tildify "$LOGDIR")"; echo
  _f 'Oldest: %s · newest: %s' "$(report_date "$(echo "$mds" | head -1)")" "$(report_date "$(echo "$mds" | tail -1)")"; echo
  _f 'Kept: %s days, at most %s runs (keep_reports_days, keep_reports in %s)' "$(num "$(conf keep_reports_days 30)" 30)" "$(num "$(conf keep_reports 20)" 20)" "$(tildify "$CONF")"; echo
  _ 'Remove them all: macup reports clean · open the folder: macup reports open'; echo
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
brew_prefix(){ # a macup path → the Homebrew prefix that installed it; nothing for any other install
  case "$1" in
    */Cellar/macup/*)      echo "${1%%/Cellar/macup/*}"; return ;;
    */opt/macup/bin/macup) echo "${1%/opt/macup/bin/macup}"; return ;;
  esac
  case "$(readlink "$1" 2>/dev/null)" in */Cellar/macup/*) (cd "$(dirname "$1")/.." && pwd -P) ;; esac
}
update_cmd(){ if [ -n "$(brew_prefix "$(resolve_self)")" ]; then echo 'brew upgrade macup'; else echo 'macup self-update'; fi; }

sha256(){ if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1"; else sha256sum "$1"; fi 2>/dev/null | awk '{print $1}'; }
fetch_release(){ # file → the latest released macup, checked against its published SHA-256; prints its version
  # main names the latest version; the file itself comes from that version's tag, so work in progress on main is never installed.
  # Before a version is tagged (or for a fork without tags) main is used. 1: download failed, 2: not macup, 3: checksum differs.
  local out=$1 v ref want
  curl -fsSL --max-time 30 "$MACUP_RAW/main/macup" -o "$out" 2>/dev/null || return 1
  v=$(sed -n 's/^MACUP_VERSION="\(.*\)"/\1/p' "$out" | head -1); [ -n "$v" ] || return 2
  ref="v$v"; want=$(curl -fsSL --max-time 15 "$MACUP_RAW/$ref/macup.sha256" 2>/dev/null | awk '{print $1; exit}')
  if [ -n "$want" ] && curl -fsSL --max-time 30 "$MACUP_RAW/$ref/macup" -o "$out.tag" 2>/dev/null; then mv "$out.tag" "$out"
  else rm -f "$out.tag"; ref=main; want=$(curl -fsSL --max-time 15 "$MACUP_RAW/main/macup.sha256" 2>/dev/null | awk '{print $1; exit}'); fi
  [ -n "$want" ] && [ "$(sha256 "$out")" = "$want" ] || return 3
  bash -n "$out" 2>/dev/null || return 2
  echo "$v"
}

self_update(){
  local tmp newv target rc
  case "$MACUP_REPO" in __*) _ 'This copy has no GitHub repo configured.'; echo; exit 1 ;; esac
  # Homebrew owns that file, and the next brew upgrade would put its own version back
  if [ -n "$(brew_prefix "$(resolve_self)")" ]; then _ 'macup was installed with Homebrew. Update it with: brew upgrade macup'; echo; exit 0; fi
  tmp=$(mktemp "${TMPDIR:-/tmp}/macup.XXXXXX")
  newv=$(fetch_release "$tmp"); rc=$?
  case $rc in
    0) ;;
    1) _f 'Download failed: %s' "$MACUP_RAW/main/macup"; echo; rm -f "$tmp"; exit 1 ;;
    3) _ 'The downloaded file does not match its published checksum; nothing changed.'; echo; rm -f "$tmp"; exit 1 ;;
    *) _ 'The downloaded file looks broken; nothing changed.'; echo; rm -f "$tmp"; exit 1 ;;
  esac
  if ! ver_gt "$newv" "$MACUP_VERSION"; then _f 'macup %s is already the latest.' "$MACUP_VERSION"; echo; rm -f "$tmp"; exit 0; fi
  target=$(resolve_self)
  if install -m 755 "$tmp" "$target" 2>/dev/null; then _f 'macup updated: %s → %s' "$MACUP_VERSION" "$newv"; else _f "Couldn't write %s" "$target"; echo; rm -f "$tmp"; exit 1; fi
  echo; rm -f "$tmp"
}

# Optional: a LaunchAgent that runs `macup check` on its own and shows a notification. A check installs and deletes
# nothing, so the schedule never changes the Mac behind your back. Off unless you turn it on.
sched_off(){ launchctl bootout "gui/$(id -u)/$SCHED_LABEL" 2>/dev/null || launchctl unload "$SCHED_PLIST" 2>/dev/null; rm -f "$SCHED_PLIST"; }
schedule(){ # [daily | weekly | off]
  local self day=""
  case "$1" in
    "") if [ ! -f "$SCHED_PLIST" ]; then
          _ 'No schedule: macup runs only when you start it.'; echo
          _ 'Turn it on: macup schedule weekly (or daily). It runs macup check, which changes nothing, and shows a notification.'; echo
        else
          if grep -q '<key>Weekday</key>' "$SCHED_PLIST"; then _ 'Schedule: macup check every Monday at 10:00, with a notification.'
          else _ 'Schedule: macup check every day at 10:00, with a notification.'; fi; echo
          _ 'Turn it off: macup schedule off'; echo
        fi ;;
    off|remove|stop)
        if [ -f "$SCHED_PLIST" ]; then sched_off; _ 'Schedule removed.'; else _ 'No schedule: macup runs only when you start it.'; fi; echo ;;
    daily|weekly)
        self=$(resolve_self); case "$self" in /*) ;; *) self="$PWD/${self#./}" ;; esac
        [ -f "$self" ] || { _f "Couldn't write %s" "$(tildify "$SCHED_PLIST")"; echo; return 1; }
        [ "$1" = weekly ] && day='<key>Weekday</key><integer>1</integer>'
        # launchd starts programs with a bare PATH: the scheduled check gets today's, so it finds the same tools (nvm's node, ~/.cargo/bin)
        xesc(){ printf '%s' "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'; }
        mkdir -p "${SCHED_PLIST%/*}" "$LOGDIR"
        [ -f "$SCHED_PLIST" ] && sched_off
        cat >"$SCHED_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$SCHED_LABEL</string>
  <key>ProgramArguments</key>
  <array><string>/bin/bash</string><string>$(xesc "$self")</string><string>check</string><string>--quiet</string><string>--notify</string></array>
  <key>StartCalendarInterval</key>
  <dict>$day<key>Hour</key><integer>10</integer><key>Minute</key><integer>0</integer></dict>
  <key>EnvironmentVariables</key>
  <dict><key>PATH</key><string>$(xesc "$PATH")</string></dict>
  <key>StandardOutPath</key><string>$(xesc "$LOGDIR/schedule.log")</string>
  <key>StandardErrorPath</key><string>$(xesc "$LOGDIR/schedule.log")</string>
  <key>ProcessType</key><string>Background</string>
</dict>
</plist>
EOF
        if ! launchctl bootstrap "gui/$(id -u)" "$SCHED_PLIST" 2>/dev/null && ! launchctl load -w "$SCHED_PLIST" 2>/dev/null; then
          rm -f "$SCHED_PLIST"; _ "launchd did not accept the schedule; nothing changed."; echo; return 1
        fi
        if [ "$1" = weekly ]; then _ 'Schedule: macup check every Monday at 10:00, with a notification.'
        else _ 'Schedule: macup check every day at 10:00, with a notification.'; fi; echo
        _ 'Turn it off: macup schedule off'; echo ;;
    *) echo "macup schedule daily | weekly | off"; return 2 ;;
  esac
}

uninstall(){ # macup, older copies, settings, history, reports, the schedule, the installer's PATH line, leftover temp files
  local target bp f d rc l dir others tmps ans tap left="" n=0
  local -a progs=() dirs=() rcs=() lines=()
  target=$(resolve_self); bp=$(brew_prefix "$target")
  # ./macup in a source checkout is the build output, not an install
  [ -f "$(dirname "$target")/build.sh" ] && [ -d "$(dirname "$target")/src" ] && target=""
  for f in "$target" "$HOME/.local/bin/macup" "$HOME/.npm-global/bin/macup" /usr/local/bin/macup /opt/homebrew/bin/macup; do
    [ -n "$f" ] && [ -f "$f" ] && [ -z "$(brew_prefix "$f")" ] && grep -q '^MACUP_VERSION=' "$f" 2>/dev/null || continue
    case " ${progs[*]} " in *" $f "*) continue ;; esac
    progs+=("$f")
  done
  for d in "$CONF_DIR" "$STATE_DIR" "$CACHE_DIR" "$LOGDIR"; do [ -n "$HOME" ] && [ -d "$d" ] && dirs+=("$d"); done
  for rc in "$HOME/.zshrc" "$HOME/.bash_profile"; do
    l=$(awk 'p && /^export PATH="/ {print; exit} {p = ($0 == "# macup")}' "$rc" 2>/dev/null); [ -n "$l" ] || continue
    dir=$(printf '%s' "$l" | sed 's/^export PATH="//; s/:\$PATH"$//'); dir=${dir/\$HOME/$HOME}
    # the line also serves whatever else lives in that folder
    others=$(for f in "$dir"/* "$dir"/.[!.]*; do { [ -e "$f" ] || [ -L "$f" ]; } && [ "${f##*/}" != macup ] && printf '%s\n' "${f##*/}"; done | head -3 | paste -sd, - | sed 's/,/, /g')
    if [ -z "$others" ]; then rcs+=("$rc"); lines+=("$l")
    else left="$left$(_f 'Kept: the PATH line in %s, because %s also has %s' "$(tildify "$rc")" "$(tildify "$dir")" "$others")"$'\n'; fi
  done
  tmps=$(find "${TMPDIR:-/tmp}/" -maxdepth 1 -type f \( -name 'macup.[A-Za-z0-9][A-Za-z0-9][A-Za-z0-9][A-Za-z0-9][A-Za-z0-9][A-Za-z0-9]' -o -name 'macup.[A-Za-z0-9][A-Za-z0-9][A-Za-z0-9][A-Za-z0-9][A-Za-z0-9][A-Za-z0-9].*' -o -name 'macup-lang.??????' \) ! -name macup.sha256 \
    ! -name "$(basename "${LANGFILE:-none}")" 2>/dev/null)

  _ 'macup uninstall removes:'; echo
  [ -n "$bp" ] && printf '  · brew uninstall macup\n'
  for f in "${progs[@]}"; do printf '  · %s\n' "$(tildify "$f")"; done
  for d in "${dirs[@]}"; do printf '  · %s  %s\n' "$(tildify "$d")" "$(hum "$(kb "$d")")"; done
  for rc in "${rcs[@]}"; do printf '  · %s\n' "$(_f 'the PATH line in %s' "$(tildify "$rc")")"; done
  [ -n "$tmps" ] && printf '  · %s\n' "$(_f 'temporary files of interrupted runs: %s' "$(cnt "$tmps")")"
  [ -f "$SCHED_PLIST" ] && printf '  · %s\n' "$(_f 'the schedule (%s)' "$(tildify "$SCHED_PLIST")")"
  [ -n "$left" ] && printf '%s' "$left" | while IFS= read -r l; do printf '  %s\n' "$l"; done
  if [ -z "$bp" ] && [ ${#progs[@]} -eq 0 ] && [ ${#dirs[@]} -eq 0 ] && [ ${#rcs[@]} -eq 0 ] && [ -z "$tmps" ] && [ ! -f "$SCHED_PLIST" ]; then _ 'Nothing to remove.'; echo; return; fi
  if [ "$YES" != 1 ]; then
    ans=$(ask "$(_ 'Remove all of this? [y/N] ')")
    case "$ans" in y|Y|т|Т|д|Д) ;; *) _ 'Nothing removed.'; echo; return ;; esac
  fi

  [ -f "$SCHED_PLIST" ] && sched_off
  for d in "${dirs[@]}"; do rm -rf "$d"; done
  for rc in "${rcs[@]}"; do   # the installer wrote a blank line, "# macup" and the export line
    f=$(mktemp "${TMPDIR:-/tmp}/macup-rc.XXXXXX")
    awk -v l="${lines[n]}" '{ a[NR] = $0 } END { for (i = 1; i <= NR; i++) {
        if (a[i] == "# macup" && a[i+1] == l) { if (o > 0 && b[o] == "") o--; i++; continue }
        b[++o] = a[i] } for (i = 1; i <= o; i++) print b[i] }' "$rc" >"$f" && cat "$f" >"$rc"
    rm -f "$f"; n=$((n + 1))
  done
  [ -n "$tmps" ] && printf '%s\n' "$tmps" | while IFS= read -r f; do rm -f "$f"; done
  for f in "${progs[@]}"; do rm -f "$f" 2>/dev/null; [ -e "$f" ] && { _f "Couldn't remove %s, remove it yourself: sudo rm %s" "$(tildify "$f")" "$f"; echo; }; done
  if [ -n "$bp" ]; then
    "$bp/bin/brew" uninstall macup >/dev/null 2>&1 || { _ "brew uninstall macup failed; run it yourself."; echo; }
    tap="$(printf '%s' "${MACUP_REPO%%/*}" | tr '[:upper:]' '[:lower:]')/macup"
    "$bp/bin/brew" tap 2>/dev/null | grep -qx "$tap" && "$bp/bin/brew" untap "$tap" >/dev/null 2>&1
  fi
  _ 'Removed.'; echo
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


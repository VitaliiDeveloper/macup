# ================================================================ PICK (interactive check)
if [ "$DRY" = 1 ] && [ "${C_N:-0}" -gt 0 ] && [ -t 0 ] && [ -t 1 ] && [ $((POT_AUTO + POT_MORE)) -gt 0 ]; then
  echo
  CHOSEN=$(pick)
  if [ -n "$CHOSEN" ]; then
    RISKY=0; for i in $CHOSEN; do { [ "${C_LVL[i]}" = 3 ] || [ "${C_AUTO[i]}" = 0 ]; } && RISKY=1; done
    if [ "$RISKY" = 1 ]; then
      c=$(ask "$(_ 'This includes aggressive or opt-in items: apps may sign you out or rebuild caches slowly. Quit those apps first. Continue? [y/N] ')")
      case "$c" in y|Y|т|Т|д|Д) ;; *) CHOSEN="" ;; esac
    fi
    if [ -n "$CHOSEN" ]; then section "Cleanup"; for i in $CHOSEN; do exec_cand "$i"; done; fi
  fi
fi

# ================================================================ TRENDS + SUMMARY
FREE_AFTER=$(df -k /System/Volumes/Data 2>/dev/null | awk 'NR==2{print $4}'); FREE_AFTER=${FREE_AFTER:-0}
PCT2=$(( FREE_AFTER * 100 / D_TOTAL ))

if task check.trends && [ -n "$PREV" ]; then
  section "Since last run"
  IFS=, read -r P_TS P_MODE P_FREE P_TOT P_MEM P_SWAP P_CYC P_MAX P_UPD P_FREED P_WARN <<EOF
$PREV
EOF
  DFREE=$((FREE_AFTER - ${P_FREE:-$FREE_AFTER}))
  if [ "$DFREE" -lt -20971520 ]; then warn 'Free space: %s since %s — something is filling the disk (try: macup check --deep)' "$(hum "$DFREE")" "$P_TS"
  else info 'Free space: %s since %s' "$( [ "$DFREE" -ge 0 ] && printf '+')$(hum "$DFREE")" "$P_TS"; fi
  [ -n "$BMAX" ] && [ -n "$P_MAX" ] && [ "$P_MAX" != "$BMAX" ] && info 'Battery capacity: %s%% → %s%%' "$P_MAX" "$BMAX"
  [ -n "$BCYC" ] && [ -n "$P_CYC" ] && [ "$P_CYC" != "$BCYC" ] && info 'Battery cycles: +%s' "$((BCYC - P_CYC))"
  info 'Full history: macup history'
fi

NEWER=""
if task check.self_update; then
  case "$MACUP_REPO" in __*) ;; *)
    STAMPF="$STATE_DIR/last_version_check"
    if [ ! -f "$STAMPF" ] || [ -n "$(find "$STAMPF" -mtime +6 2>/dev/null)" ]; then
      RV=$(curl -fsS --max-time 4 "$MACUP_RAW/main/macup" 2>/dev/null | sed -n 's/^MACUP_VERSION="\(.*\)"/\1/p' | head -1)
      if [ -n "$RV" ]; then echo "$RV" >"$STAMPF"; else touch "$STAMPF"; fi
    fi
    RV=$(cat "$STAMPF" 2>/dev/null)
    ver_gt "$RV" "$MACUP_VERSION" && NEWER="$RV"
  ;; esac
fi

# a run that started no command leaves no empty log next to its report
[ -s "$RAW" ] || { rm -f "$RAW"; RAW=""; }
T=$SECONDS; TIME="$((T / 60))m $((T % 60))s"
echo "$(date '+%Y-%m-%d %H:%M'),$MODE,$FREE_AFTER,$D_TOTAL,${MEMFREE:-},${SWAP:-0},${BCYC:-},${BMAX:-},${#UPDATED[@]},$FREED,${#WARN[@]}" >>"$HISTORY"

SUM=$(mktemp "${TMPDIR:-/tmp}/macup.XXXXXX")
{
  echo "# $(_f 'macup report — %s' "$(date '+%Y-%m-%d %H:%M')")"
  echo
  _f 'Mode: %s · macup %s · took %s' "$MODE" "$MACUP_VERSION" "$TIME"; echo
  echo
  echo "## $(_ 'Summary')"
  echo
  if [ ${#UPDATED[@]} -gt 0 ]; then echo "- **$(_f 'Updated (%s):' "${#UPDATED[@]}")**"; for u in "${UPDATED[@]}"; do echo "    - $u"; done
  elif UPD; then echo "- $(_ 'Updates: everything was already up to date')"; fi
  if CLEAN || [ "$DID_CLEAN" = 1 ]; then echo "- **$(_f 'Freed: %s' "$(hum "$FREED")")**"
  elif WANT_CLN && [ "$POT_AUTO" -gt 0 ]; then echo "- $(_f 'Could free: ~%s' "$(hum "$POT_AUTO")")"; fi
  if [ ${#SKIPPED[@]} -gt 0 ]; then echo "- **$(_f 'Skipped because the app is open (%s), quit it and run again:' "${#SKIPPED[@]}")**"; for s in "${SKIPPED[@]}"; do echo "    - $s"; done; fi
  WANT_CLN && [ "$DID_CLEAN" = 0 ] && [ "$POT_MORE" -gt 0 ] && echo "- $(_f 'More with a higher level or by picking: ~%s' "$(hum "$POT_MORE")")"
  echo "- $(_f 'Free disk space: %s (%s%%), was %s' "$(hum "$FREE_AFTER")" "$PCT2" "$(hum "$FREE_BEFORE")")"
  if [ ${#WARN[@]} -gt 0 ]; then echo "- **$(_f 'Needs attention (%s):' "${#WARN[@]}")**"; for w in "${WARN[@]}"; do echo "    - $w"; done
  else echo "- $(_ 'Needs attention: nothing')"; fi
  [ -n "$NEWER" ] && echo "- $(_f 'macup %s is available: %s' "$NEWER" "$(update_cmd)")"
  [ -n "$RAW" ] && { echo; _f 'Command log: %s' "\`$(tildify "$RAW")\`"; echo; }
} >"$SUM"
cat "$SUM" "$BODY" >"$REPORT"; rm -f "$SUM"

[ "$QUIET" = 1 ] && exec >&3 3>&-
if [ "$JSON" = 1 ]; then
  # schema grows by adding fields; a change that breaks a reader raises the number
  json_items(){ local i; printf '['; for ((i = 0; i < IT_N; i++)); do [ $i = 0 ] || printf ','
    printf '{"section":"%s","kind":"%s","text":"%s","details":%s}' "$(jstr "${IT_SEC[i]}")" "${IT_KIND[i]}" "$(jstr "${IT_MSG[i]}")" "$(jlines "$(awk -F'\t' -v i="$i" '$1 == i { sub(/^[^\t]*\t/, ""); print }' "$BODY.det" 2>/dev/null)")"; done; printf ']'; }
  json_cands(){ local i first=1 lv inc opt hid busy; printf '['
    # every candidate, the small ones the terminal list hides too: a program can still --pick them
    [ "$DRY" = 1 ] && for ((i = 0; i < ${C_N:-0}; i++)); do
      [ $first = 1 ] || printf ','; first=0
      case "${C_LVL[i]}" in 1) lv=safe ;; 2) lv=standard ;; *) lv=aggressive ;; esac
      opt=true; inc=false; [ "${C_AUTO[i]}" = 1 ] && { opt=false; [ "${C_LVL[i]}" -le "$LEVEL" ] && inc=true; }
      hid=true; visible "$i" && hid=false
      busy=false; [ "${C_BUSY[i]:-0}" = 1 ] && busy=true
      printf '{"key":"%s","task":"%s","level":"%s","kb":%s,"opt_in":%s,"in_clean":%s,"hidden":%s,"busy":%s,"text":"%s"}' "${C_KEY[i]}" "${C_TASK[i]}" "$lv" "${C_KB[i]:-0}" "$opt" "$inc" "$hid" "$busy" "$(jstr "${C_LBL[i]}")"
    done; printf ']'; }
  printf '{"schema":1,"version":"%s","mode":"%s","date":"%s","seconds":%s,"free_kb":%s,"total_kb":%s,"freed_kb":%s,"could_free_kb":%s,"could_free_more_kb":%s,' \
    "$MACUP_VERSION" "$MODE" "$(date '+%Y-%m-%d %H:%M')" "$T" "$FREE_AFTER" "$D_TOTAL" "$FREED" "${POT_AUTO:-0}" "${POT_MORE:-0}"
  printf '"updated":%s,"skipped_open":%s,"needs_attention":%s,"failed_steps":%s,"newer_macup":"%s","report":"%s","log":"%s","items":%s,"cleanable":%s}\n' \
    "$(jarr "${UPDATED[@]}")" "$(jarr "${SKIPPED[@]}")" "$(jarr "${WARN[@]}")" "$ERRS" "$NEWER" "$(jstr "$REPORT")" "$(jstr "$RAW")" "$(json_items)" "$(json_cands)"
else
printf '%s\n%s━━━━━━━━━━━━━━━━ %s ━━━━━━━━━━━━━━━━%s\n' "$CL" "$B" "$(_ 'Summary')" "$N"
if [ ${#UPDATED[@]} -gt 0 ]; then
  printf '  %s%s%s\n' "$G" "$(_f 'Updated: %s' "${#UPDATED[@]}")" "$N"; for u in "${UPDATED[@]}"; do printf '    · %s\n' "$u"; done
elif UPD; then printf '  %s%s%s\n' "$G" "$(_ 'Updates: everything was already up to date')" "$N"; fi
if CLEAN || [ "$DID_CLEAN" = 1 ]; then printf '  %s%s%s\n' "$G" "$(_f 'Freed: %s' "$(hum "$FREED")")" "$N"
elif WANT_CLN && [ "$POT_AUTO" -gt 0 ]; then printf '  %s\n' "$(_f 'Could free: ~%s  (to free it: macup all)' "$(hum "$POT_AUTO")")"; fi
if [ ${#SKIPPED[@]} -gt 0 ]; then
  printf '  %s%s%s\n' "$Y" "$(_f 'Skipped because the app is open (%s), quit it and run again:' "${#SKIPPED[@]}")" "$N"; for s in "${SKIPPED[@]}"; do printf '    · %s\n' "$s"; done
fi
WANT_CLN && [ "$DID_CLEAN" = 0 ] && [ "$POT_MORE" -gt 0 ] && printf '  %s\n' "$(_f 'More with a higher level or by picking: ~%s' "$(hum "$POT_MORE")")"
printf '  %s\n' "$(_f 'Free disk space: %s (%s%%)' "$(hum "$FREE_AFTER")" "$PCT2")"
if [ ${#WARN[@]} -gt 0 ]; then
  printf '  %s%s%s\n' "$Y" "$(_f 'Needs attention: %s' "${#WARN[@]}")" "$N"; for w in "${WARN[@]}"; do printf '    %s!%s %s\n' "$Y" "$N" "$w"; done
else printf '  %s%s%s\n' "$G" "$(_ 'Needs attention: nothing')" "$N"; fi
[ -n "$NEWER" ] && printf '  %s%s%s\n' "$C" "$(_f 'macup %s is available: %s' "$NEWER" "$(update_cmd)")" "$N"
printf '  %s%s%s\n' "$D" "$(_f 'Report: %s · %s' "$(tildify "$REPORT")" "$TIME")" "$N"
printf '  %s%s%s\n' "$D" "$(_ 'Menu: macup · trends: macup history · help: macup help')" "$N"
fi

# --notify (the schedule uses it): one notification when something needs a look
# nothing to say, no notification: a weekly "all good" teaches people to ignore it
if [ "$NOTIFY" = 1 ] && command -v osascript >/dev/null 2>&1 && { [ ${#WARN[@]} -gt 0 ] || [ "${POT_AUTO:-0}" -ge 1048576 ]; }; then
  if [ ${#WARN[@]} -gt 0 ]; then NT=$(_f 'Needs attention: %s' "${#WARN[@]}"); else NT=$(_ 'Needs attention: nothing'); fi
  [ "${POT_AUTO:-0}" -ge 1048576 ] && NT="$NT · $(_f 'Could free: ~%s' "$(hum "$POT_AUTO")")"
  osascript -e "display notification \"$(jstr "$NT. $(_ 'Details: macup last')")\" with title \"macup\"" >/dev/null 2>&1
fi
# 3: an update or cleanup step failed. Warnings from the health checks are not failures of the run.
[ "$ERRS" -gt 0 ] && exit 3
exit 0

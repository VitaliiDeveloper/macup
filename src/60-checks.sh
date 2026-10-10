# ================================================================ SYSTEM
section "System"
OSV=$(sw_vers -productVersion 2>/dev/null)
if task check.system; then
  UPTXT=$(uptime | sed -E 's/.* up ([^,]+(, *[0-9]+:[0-9]+)?),.*/\1/')
  BOOT=$(sysctl -n kern.boottime 2>/dev/null | awk -F'sec = ' '{print $2+0}')
  UPDAYS=$(( ( $(date +%s) - ${BOOT:-$(date +%s)} ) / 86400 ))
  BUILD=$(sw_vers -buildVersion 2>/dev/null); MODEL=$(sysctl -n hw.model 2>/dev/null)
  if [ "$UPDAYS" -ge 14 ]; then warn 'macOS %s (%s) · %s · up %s — restart recommended (%s days without restart)' "$OSV" "$BUILD" "$MODEL" "$UPTXT" "$UPDAYS"
  else ok 'macOS %s (%s) · %s · up %s' "$OSV" "$BUILD" "$MODEL" "$UPTXT"; fi
fi

D_TOTAL=$(df -k /System/Volumes/Data 2>/dev/null | awk 'NR==2{print $2}'); D_TOTAL=${D_TOTAL:-1}
FREE_BEFORE=$(df -k /System/Volumes/Data 2>/dev/null | awk 'NR==2{print $4}'); FREE_BEFORE=${FREE_BEFORE:-0}
if task check.disk; then
  PCT=$(( FREE_BEFORE * 100 / D_TOTAL )); F1=$(hum "$FREE_BEFORE"); F2=$(hum "$D_TOTAL")
  if   [ "$PCT" -lt 10 ]; then fail 'Disk: %s free of %s (%s%%) — critically low' "$F1" "$F2" "$PCT"
  elif [ "$PCT" -lt 20 ]; then warn 'Disk: %s free of %s (%s%%) — getting low' "$F1" "$F2" "$PCT"
  else ok 'Disk: %s free of %s (%s%%)' "$F1" "$F2" "$PCT"; fi
  SWAPDISK=$(df -k /System/Volumes/VM 2>/dev/null | awk 'NR==2{print $3}')
  [ "${SWAPDISK:-0}" -ge 1048576 ] && info 'Swap files: %s of the used space (macOS removes them on restart)' "$(hum "$SWAPDISK")"
  SMART=$(diskutil info disk0 2>/dev/null | awk -F': *' '/SMART Status/{print $2}')
  if [ -n "$SMART" ]; then
    case "$SMART" in Verified|"Not Supported") ok 'Disk health (SMART): %s' "$SMART" ;; *) fail 'Disk health (SMART): %s — back up now' "$SMART" ;; esac
  fi
  SNAPS=$(tmutil listlocalsnapshots / 2>/dev/null | grep -c 'com.apple')
  [ "${SNAPS:-0}" -gt 0 ] && info 'Local Time Machine snapshots: %s (macOS frees them automatically when space runs low)' "$SNAPS"
fi

MEMFREE=""; SWAP=0
if task check.memory; then
  RAM=$(( $(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1073741824 ))
  MEMFREE=$(memory_pressure 2>/dev/null | awk -F': ' '/free percentage/{gsub(/%/,"",$2); print $2+0}')
  SWAP=$(sysctl -n vm.swapusage 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="used"){v=$(i+2); m=1; if(v~/G/)m=1024; gsub(/[MG]/,"",v); printf "%d", v*m; exit}}')
  SWAP=${SWAP:-0}
  if [ "${MEMFREE:-100}" -lt 15 ] || [ "$SWAP" -gt 6144 ]; then warn 'Memory: %s GB, %s%% free, swap %s — memory is tight; quit heavy apps or restart' "$RAM" "${MEMFREE:-?}" "$(hum $((SWAP * 1024)))"
  else ok 'Memory: %s GB, %s%% free, swap %s' "$RAM" "${MEMFREE:-?}" "$(hum $((SWAP * 1024)))"; fi
fi

if task check.cpu; then
  CORES=$(sysctl -n hw.ncpu 2>/dev/null || echo 1)
  LOAD=$(sysctl -n vm.loadavg 2>/dev/null | awk '{print $2}')
  HIGH=$(awk -v l="${LOAD:-0}" -v c="$CORES" 'BEGIN{print (l > c*1.5) ? 1 : 0}')
  if [ "$HIGH" = 1 ]; then warn 'CPU: load %s on %s cores — something is busy' "$LOAD" "$CORES"; else ok 'CPU: load %s on %s cores' "${LOAD:-?}" "$CORES"; fi
  TOPCPU=$(ps -Aceo pcpu=,comm= -r 2>/dev/null | head -3 | awk '{p=$1; $1=""; sub(/^ /,""); printf "%s%% %s\n", p, $0}' | paste -sd ',' - | sed 's/,/, /g')
  TOPMEM=$(ps -Aceo rss=,comm= -m 2>/dev/null | head -3 | awk '{r=$1; $1=""; sub(/^ /,""); printf "%.1f GB %s\n", r/1048576, $0}' | paste -sd ',' - | sed 's/,/, /g')
  [ -n "$TOPCPU" ] && info 'Top CPU:    %s' "$TOPCPU"
  [ -n "$TOPMEM" ] && info 'Top memory: %s' "$TOPMEM"
  if pmset -g therm 2>/dev/null | grep -qiE 'thermal warning level set|Speed_Limit[^0-9]*[0-9]{1,2}$'; then
    warn 'Thermal: the Mac is throttling right now'
  fi
fi

BCYC=""; BMAX=""
if task check.battery && pmset -g batt 2>/dev/null | grep -q InternalBattery; then
  BPCT=$(pmset -g batt | grep -o '[0-9]*%' | head -1)
  BP=$(system_profiler SPPowerDataType 2>/dev/null)
  BCYC=$(echo "$BP" | awk -F': ' '/Cycle Count/{print $2; exit}')
  BCOND=$(echo "$BP" | awk -F': ' '/Condition/{print $2; exit}')
  BMAX=$(echo "$BP" | awk -F': ' '/Maximum Capacity/{gsub(/%/,"",$2); print $2; exit}')
  if [ -n "$BCOND" ] && [ "$BCOND" != "Normal" ]; then warn 'Battery: %s charged, %s cycles, %s%% capacity, %s' "$BPCT" "${BCYC:-?}" "${BMAX:-?}" "$BCOND"
  elif [ -n "$BMAX" ] && [ "$BMAX" -lt 80 ]; then warn 'Battery: %s charged, %s cycles, %s%% capacity, %s — capacity under 80%%' "$BPCT" "${BCYC:-?}" "$BMAX" "${BCOND:-?}"
  else ok 'Battery: %s charged, %s cycles, %s%% capacity, %s' "$BPCT" "${BCYC:-?}" "${BMAX:-?}" "${BCOND:-?}"; fi
fi

# ================================================================ SECURITY
if task check.security; then
  section "Security"
  FV=$(fdesetup status 2>/dev/null)
  case "$FV" in *"is On"*) ok 'FileVault: on' ;; "") ;; *) warn 'FileVault: off — your disk is not encrypted (System Settings → Privacy & Security)' ;; esac
  FW=$(/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null)
  case "$FW" in *enabled*) ok 'Firewall: on' ;; "") ;; *) warn 'Firewall: off (System Settings → Network → Firewall)' ;; esac
  SIP=$(csrutil status 2>/dev/null)
  case "$SIP" in *"status: enabled"*) ok 'System Integrity Protection: on' ;; "") ;; *) warn 'System Integrity Protection: off' ;; esac
  GK=$(spctl --status 2>/dev/null)
  case "$GK" in *enabled*) ok 'Gatekeeper: on' ;; "") ;; *) warn 'Gatekeeper: off — apps from anywhere can run' ;; esac
  AU=$(defaults read /Library/Preferences/com.apple.SoftwareUpdate AutomaticCheckEnabled 2>/dev/null)
  CR=$(defaults read /Library/Preferences/com.apple.SoftwareUpdate CriticalUpdateInstall 2>/dev/null)
  if [ "$AU" = 0 ]; then warn 'Automatic update checks: off'; elif [ "$CR" = 0 ]; then warn 'Security responses & system files: not installed automatically'; else ok 'Automatic security updates: on'; fi
  TMD=$(tmutil destinationinfo 2>/dev/null)
  if echo "$TMD" | grep -q 'Name'; then
    LB=$(tmutil latestbackup 2>/dev/null | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | tail -1)
    if [ -n "$LB" ]; then
      AGE=$(( ( $(date +%s) - $(date -j -f %Y-%m-%d "$LB" +%s 2>/dev/null || date +%s) ) / 86400 ))
      if [ "$AGE" -gt 7 ]; then warn 'Time Machine: last backup %s (%s days ago)' "$LB" "$AGE"; else ok 'Time Machine: last backup %s' "$LB"; fi
    else info 'Time Machine: configured (last backup date needs Full Disk Access for Terminal)'; fi
  else
    warn 'Time Machine: no backup destination configured'
  fi
fi


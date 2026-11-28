# ================================================================ PROCESSES left running
# A program whose parent quits is adopted by launchd (parent pid 1). Apps, their helpers and launchd's own jobs live
# like that on purpose; a script, a test run or a dev server whose terminal or tool went away does too, and then
# nothing ever stops it. A check lists those; one is stopped, with everything it started, only when picked by number.
STRAY_SECS=$(num "${MACUP_STRAY_SECS:-}" 3600)   # younger ones may still be starting up; seconds, for the tests
# programs people leave running on purpose, and dev tools' own servers that detach from what starts them (lowercase;
# screen's server calls itself SCREEN, an ssh master "ssh: <socket> [mux]")
STRAY_KEEP=' ssh-agent gpg-agent ssh autossh mosh-server tmux screen emacs caffeinate ollama syncthing limactl colima adb sccache watchman postgres mysqld mariadbd redis-server mongod '
STRAY_KEEP_CMD='GradleDaemon|KotlinCompileDaemon|fsmonitor--daemon|A-server[.]jar|--daemon( |$)'
PS_T=""
ps_load(){ # the process table, once per question: pid ppid uid rss time etime tty start(lstart, _ for spaces) command
  PS_T=$(LC_ALL=C ps -Ao pid=,ppid=,uid=,rss=,time=,etime=,tty=,lstart=,command= 2>/dev/null |
    awk '{ s = $8 "_" $9 "_" $10 "_" $11 "_" $12; c = $0; sub(/^ *([^ ]+ +){12}/, "", c); print $1, $2, $3, $4, $5, $6, $7, s, c }')
}
ps_trees(){ # mode → for each root: pid ⇥ start ⇥ seconds ⇥ KB of its tree ⇥ processes in it ⇥ macup in it (0/1) ⇥ command
  # mode stray: left running, as above; mode claude: Claude Code sessions of the Claude app, open for a day or more
  local anc lj=""
  anc=$(printf '%s\n' "$PS_T" | awk -v p=$$ '{ par[$1] = $2 } END { while (p > 1 && !(p in seen)) { seen[p] = 1; print p; p = par[p] } }')
  [ "$1" = stray ] && lj=$(launchctl list 2>/dev/null | awk 'NR > 1 && $1 ~ /^[0-9]+$/ { print $1 }')
  printf '%s\n' "$PS_T" | ANC="$anc" LJ="$lj" KEEP="$STRAY_KEEP" KEEPC="$STRAY_KEEP_CMD" awk -v mode="$1" -v me="$(id -u)" -v min="$STRAY_SECS" '
    function secs(e,  d, n, a, s, i) { d = 0; if (i = index(e, "-")) { d = substr(e, 1, i - 1); e = substr(e, i + 1) }
      n = split(e, a, ":"); s = 0; for (i = 1; i <= n; i++) s = s * 60 + a[i]; return d * 86400 + s }
    BEGIN { n = split(ENVIRON["ANC"], v, "\n"); for (i = 1; i <= n; i++) A[v[i]] = 1
            n = split(ENVIRON["LJ"], v, "\n"); for (i = 1; i <= n; i++) L[v[i]] = 1 }
    NF >= 9 { p = $1; P[p] = $2; U[p] = $3; R[p] = $4; E[p] = secs($6); Y[p] = $7; S[p] = $8
              c = $0; sub(/^ *([^ ]+ +){8}/, "", c); C[p] = c; o[++N] = p }
    END {
      for (i = 1; i <= N; i++) { p = o[i]; c = C[p]
        if (U[p] != me) continue
        if (mode == "claude") {
          if (c ~ /\/Claude\/claude-code\/.*\/MacOS\/claude .*--output-format stream-json/ && c !~ /\/Helpers\/disclaimer / && E[p] >= 86400) K[p] = 1
          continue }
        if (P[p] != 1 || (p in L) || (p in A) || E[p] < min) continue
        if (c ~ /\.(app|appex|xpc)\/Contents\// || c ~ /^\/(System|usr\/libexec|usr\/sbin|sbin|Library\/Apple|Library\/Developer|Library\/PrivilegedHelperTools)\//) continue
        w = c; sub(/ .*/, "", w); sub(/.*\//, "", w); sub(/:$/, "", w)
        if (index(ENVIRON["KEEP"], " " tolower(w) " ") || c ~ ENVIRON["KEEPC"]) continue
        K[p] = 1 }
      for (i = 1; i <= N; i++) { q = o[i]; x = q; g = 0
        while ((x in P) && !(x in K) && x > 1 && g++ < 1000) x = P[x]
        if (!(x in K)) continue
        T[q] = x; cnt[x]++; kb[x] += R[q]; if (q in A) self[x] = 1 }
      for (i = 1; i <= N; i++) { r = o[i]; if (!(r in K)) continue
        if (mode == "stray") {   # one with macup inside is out already: its root is an ancestor of macup
          if (Y[r] != "??") { busy = 0; for (j = 1; j <= N; j++) { q = o[j]; if (Y[q] == Y[r] && T[q] != r) busy = 1 }
            if (busy) continue }    # its terminal is still open: put in the background there on purpose
        }
        printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n", r, S[r], E[r], kb[r], cnt[r], (r in self) ? 1 : 0, C[r] } }'
}
ps_tree_pids(){ # pid → it and every process under it, from a fresh look
  LC_ALL=C ps -Ao pid=,ppid= 2>/dev/null | awk -v r="$1" '{ par[$1] = $2 } END { for (c in par) { x = c; g = 0; while ((x in par) && x != r && x > 1 && g++ < 1000) x = par[x]; if (x == r) print c } }'
}
age(){ # seconds → 3 d, 5 h, 40 min
  if [ "$1" -ge 86400 ]; then _f '%s d' $(($1 / 86400)); elif [ "$1" -ge 3600 ]; then _f '%s h' $(($1 / 3600)); else _f '%s min' $(($1 / 60)); fi
}
prog_name(){ # command → what to call it: the script an interpreter runs, else the program
  printf '%s\n' "$1" | awk '{ w = $1; sub(/.*\//, "", w)
    if (w ~ /^(bash|sh|zsh|dash|fish|python[0-9.]*|node|ruby|perl[0-9.]*|deno|bun)$/) for (i = 2; i <= NF; i++) if ($i !~ /^-/) { w = $i; sub(/.*\//, "", w); break }
    print w }'
}
cwd_of(){ lsof -a -p "$1" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -1; }

claude_sessions(){ # check.memory: every session open in the Claude app keeps a Claude Code process with its memory
  local l n=0 kb=0 pid st s k c self d
  ps_load; l=$(ps_trees claude); [ -n "$l" ] || return 0
  while IFS=$'\t' read -r pid st s k c self d; do n=$((n + 1)); kb=$((kb + k)); done <<EOF2
$l
EOF2
  info 'Claude Code sessions open in the Claude app for a day or more: %s, %s of memory' "$n" "$(hum "$kb")"
  while IFS=$'\t' read -r pid st s k c self d; do
    d=$(cwd_of "$pid"); [ -n "$d" ] || d='?'
    if [ "$self" = 1 ]; then sub "$(tildify "$d") · $(age "$s") · $(hum "$k") · $(_ 'this session')"; else sub "$(tildify "$d") · $(age "$s") · $(hum "$k")"; fi
  done <<EOF2
$l
EOF2
}

STRAY_N=0
stray_cands(){
  task_allowed clean.stray_processes || return 0
  local l pid st s k c self cmd d info
  ps_load; l=$(ps_trees stray); [ -n "$l" ] || return 0
  while IFS=$'\t' read -r pid st s k c self cmd; do
    [ -n "$pid" ] || continue
    d=$(cwd_of "$pid")
    info=$(_f 'What: %s' "${cmd:0:120}"; echo
      _f 'Started %s ago in %s.' "$(age "$s")" "$(tildify "${d:-?}")"; echo
      _ 'Why: what started it has quit, and neither macOS nor an app looks after it.'; echo
      [ "$c" -gt 1 ] && { _f 'It started %s more processes; they stop with it.' "$((c - 1))"; echo; }
      _ 'Stopping: it is asked to quit, and stopped after 5 seconds if it does not; what it has not saved is lost.'; echo)
    CL_MANUAL=1 cand clean.stray_processes 3 "$(_f '%s · left running for %s (%s of memory)' "$(prog_name "$cmd")" "$(age "$s")" "$(hum "$k")")" 0 cmd "proc:$pid:$st" "" "" "" "$info"
    STRAY_N=$((STRAY_N + 1))
  done <<EOF2
$l
EOF2
}
run_stray(){ # pid start — asked again right before: the same process (pid and start), still left running
  local pid=$1 st=$2 all i
  case "$pid" in ""|*[!0-9]*) echo "macup refused pid: $pid" >>"$RAW"; return 1 ;; esac
  ps_load
  ps_trees stray | awk -F'\t' -v p="$pid" -v s="$st" '$1 == p && $2 == s { f = 1 } END { exit !f }' || {
    info '%s: no longer running or no longer left over, skipped' "${lbl:-$pid}"; return 2; }   # lbl: exec_cand's
  all=$(ps_tree_pids "$pid"); [ -n "$all" ] || return 0
  echo "macup stops $pid and what it started: $(echo $all)" >>"$RAW"
  kill -TERM $all 2>>"$RAW"
  for i in 1 2 3 4 5 6 7 8 9 10; do
    kill -0 $all 2>/dev/null || return 0   # true while any one of them is left
    sleep 0.5
  done
  kill -KILL $all 2>/dev/null; sleep 0.5
  ! kill -0 "$pid" 2>/dev/null
}

# ================================================================ TOOLS & SERVICES
section "Tools & services"
if task check.mcp && have claude; then
  step 'Checking MCP servers'
  # from $HOME: the list depends on the current folder (local-scope servers)
  MCP=$(cd "$HOME" && tl 120 claude mcp list 2>/dev/null </dev/null | nocolor); MCPRC=$?
  MT=$(printf '%s\n' "$MCP" | grep -cE '✓|✔|✗|✘|⚠|Connected|Failed|[Aa]uth')
  BAD=$(printf '%s\n' "$MCP" | grep -E '✗|✘|⚠|Failed|[Nn]eeds auth')
  if [ "$MCPRC" = 124 ]; then warn '%s: no answer in %s seconds, skipped' 'claude mcp list' 120
  elif [ "$MT" -eq 0 ]; then info 'Claude Code MCP servers: none configured'
  elif [ -z "$BAD" ]; then ok 'Claude Code MCP servers: all %s connected' "$MT"
  else warn 'Claude Code MCP servers: %s of %s not working' "$(cnt "$BAD")" "$MT"; lines "$BAD"; fi
fi
if task check.brew_doctor && have brew; then
  step 'brew doctor'
  DOC=$(tl 240 brew doctor 2>&1); DOCRC=$?; echo "$DOC" >>"$RAW"
  ND=$(printf '%s\n' "$DOC" | grep -c '^Warning:')
  if [ "$DOCRC" = 124 ]; then warn '%s: no answer in %s seconds, skipped' 'brew doctor' 240
  elif [ "$ND" -gt 0 ]; then warn 'brew doctor: %s warnings (details in the report)' "$ND"; else ok 'brew doctor: all good'; fi
fi
if task check.xcode; then
  if XP=$(xcode-select -p 2>/dev/null) && [ -d "$XP" ]; then
    XV=$(xcodebuild -version 2>/dev/null | head -1)
    ok 'Developer tools: %s (%s)' "${XV:-$(_ 'Command Line Tools only')}" "$(tildify "$XP")"
  else warn 'Developer tools: not installed or broken — run: xcode-select --install'; fi
  if have xcrun && have python3; then
    RT=$(xcrun simctl runtime list -j 2>/dev/null | python3 -c "$MACUP_PY" sim-runtimes 2>/dev/null)
    if [ -n "$RT" ]; then
      read -r RN RK <<EOF
$(printf '%s\n' "$RT" | head -1)
EOF
      if [ "${RN:-0}" -gt 0 ]; then
        info 'Simulator runtimes: %s, %s — remove old ones in Xcode → Settings → Components' "$RN" "$(hum "$RK")"
        printf '%s\n' "$RT" | tail -n +2 | while IFS= read -r l; do mdonly "$l"; done
      fi
    fi
  fi
fi
if task check.devtools; then
  tool(){ [ -n "$2" ] && TOOLS="$TOOLS${TOOLS:+ · }$1 $2"; }
  TOOLS=""
  have swift   && tool Swift     "$(swift --version 2>&1 | grep -o 'Swift version [0-9.]*' | head -1 | sed 's/Swift version //')"
  have pod     && tool CocoaPods "$(pod --version 2>/dev/null)"
  have flutter && tool Flutter   "$(flutter --version 2>/dev/null | head -1 | sed 's/^Flutter //; s/ •.*//')"
  have node    && tool Node      "$(node --version 2>/dev/null | sed 's/^v//')"
  have ruby    && tool Ruby      "$(ruby -e 'print RUBY_VERSION' 2>/dev/null)"
  have python3 && tool Python    "$(python3 -c "$MACUP_PY" python-version 2>/dev/null)"
  have codex   && tool Codex     "$(codex --version 2>/dev/null | head -1 | awk '{print $NF}')"
  [ -n "$TOOLS" ] && info '%s' "$TOOLS"
  [ -d /Applications/Claude.app ] && info 'Claude Desktop %s (updates itself)' "$(defaults read /Applications/Claude.app/Contents/Info.plist CFBundleShortVersionString 2>/dev/null)"
fi
if task check.commands && have python3; then
  step 'Checking commands'
  # a script whose interpreter is gone stays on PATH and only fails when run ("env: node: No such file or directory"):
  # an unlinked keg-only node@24, a pipx venv whose Python was removed by brew, a link to a deleted file
  CMDS=$(python3 -c "$MACUP_PY" commands "$HOME/.local/bin" "$HOME/.npm-global/bin" /opt/homebrew/bin /usr/local/bin </dev/null 2>/dev/null)
  if [ -z "$CMDS" ]; then :   # the scan itself failed: no false "all can start"
  elif [ -z "$(printf '%s\n' "$CMDS" | tail -n +2)" ]; then ok 'Commands: all %s scripts in your bin folders can start' "$(printf '%s\n' "$CMDS" | head -1)"
  else
    while IFS=$'\t' read -r name hint names from; do
      if [ "$name" = - ]; then
        fix="find $(tildify "$hint") -maxdepth 1 -type l ! -exec test -e {} \\; -print -delete"; [ -w "$hint" ] || fix="sudo $fix"
        warn 'Dead links in %s, leftovers of removed %s: %s — safe to remove, run in Terminal: %s' "$(tildify "$hint")" "$from" "$names" "$fix"
        continue
      fi
      [ "$hint" = - ] && hint=$(link_fix "$name")
      if [ -z "$hint" ]; then warn 'Commands that cannot start, %s is missing: %s' "$name" "$names"
      else warn 'Commands that cannot start, %s is missing: %s — run: %s' "$name" "$names" "$hint"; fi
    done <<EOF
$(printf '%s\n' "$CMDS" | tail -n +2)
EOF
  fi
  # (no `case` inside $( ): bash 3.2 takes its ")" for the end of the substitution)
  # folders of yours in PATH that do not exist: a line in ~/.zshrc for a tool that was removed (macOS itself lists system folders that may not exist)
  GONEP=$(printf '%s' "$USER_PATH" | tr ':' '\n' | awk 'NF && !seen[$0]++' | while IFS= read -r d; do [[ "$d" == "$HOME"/* ]] && [ ! -d "$d" ] && tildify "$d"; done | paste -sd, - | sed 's/,/, /g')
  [ -n "$GONEP" ] && info 'PATH names folders that do not exist: %s — the lines that add them (~/.zshrc, ~/.zprofile) can go' "$GONEP"
fi
if task check.docker && have docker && tl 20 docker info >/dev/null 2>&1; then
  # the Reclaimable column has a space inside ("1.2GB (50%)"), so the columns are asked for by name
  DDF=$(tl 30 docker system df --format '{{.Type}} {{.Size}}, {{.Reclaimable}} reclaimable' 2>/dev/null | paste -sd';' - | sed 's/;/; /g')
  [ -n "$DDF" ] && info 'Docker: %s' "$DDF"
  DV=$(tl 30 docker volume ls -qf dangling=true 2>/dev/null | grep -c .)
  [ "${DV:-0}" -gt 0 ] && info 'Docker volumes no container uses: %s — macup never deletes volumes; look: docker volume ls -f dangling=true' "$DV"
fi
# a token GitHub no longer accepts fails later, in the middle of a push or a release
if task check.gh && have gh && [ -s "${GH_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/gh}/hosts.yml" ]; then
  GHS=$(tl 20 gh auth status 2>&1 </dev/null)
  printf '%s\n' "$GHS" | grep -qiE 'token .* is (invalid|no longer valid)|authentication failed' && warn 'GitHub CLI: the saved login no longer works — run: gh auth login'
fi
# signing certificates: Xcode says nothing until the build fails on the day one expires
if task check.certs && have security && have openssl && have python3; then
  CE=$(security find-identity -v -p codesigning 2>/dev/null | python3 -c "$MACUP_PY" certs-expiring 2>/dev/null)
  [ -n "$CE" ] && { warn 'Signing certificates that expire within 30 days: %s — renew them in Xcode → Settings → Accounts' "$(cnt "$CE")"; lines "$CE"; }
fi
# an app that keeps crashing: the reports are in ~/Library/Logs/DiagnosticReports, and in Retired/ once macOS has sent them
if task check.crashes && have python3 && [ -d "$HOME/Library/Logs/DiagnosticReports" ]; then
  CR=$(python3 -c "$MACUP_PY" crashes 2>/dev/null)
  CRA=$(printf '%s\n' "$CR" | awk '$1 == "A" {n=$2; $1=$2=""; sub(/^ +/,""); printf "%s ×%d\n", $0, n}' | head -5 | paste -sd, - | sed 's/,/, /g')
  CRS=$(printf '%s\n' "$CR" | awk '$1 == "S" {print $2}')
  [ -n "$CRA" ] && info 'Crashed 3 or more times in the last 7 days: %s' "$CRA"
  [ "${CRS:-0}" -ge 3 ] && info 'macOS system processes crashed %s times this week (not yours to fix; Apple gets the reports)' "$CRS"
fi


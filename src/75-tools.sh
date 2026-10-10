# ================================================================ TOOLS & SERVICES
section "Tools & services"
if task check.mcp && have claude; then
  step 'Checking MCP servers'
  # from $HOME: the list depends on the current folder (local-scope servers)
  MCP=$(cd "$HOME" && claude mcp list 2>/dev/null </dev/null | nocolor)
  MT=$(printf '%s\n' "$MCP" | grep -cE '✓|✔|✗|✘|⚠|Connected|Failed|[Aa]uth')
  BAD=$(printf '%s\n' "$MCP" | grep -E '✗|✘|⚠|Failed|[Nn]eeds auth')
  if [ "$MT" -eq 0 ]; then info 'Claude Code MCP servers: none configured'
  elif [ -z "$BAD" ]; then ok 'Claude Code MCP servers: all %s connected' "$MT"
  else warn 'Claude Code MCP servers: %s of %s not working' "$(cnt "$BAD")" "$MT"; lines "$BAD"; fi
fi
if task check.brew_doctor && have brew; then
  step 'brew doctor'
  DOC=$(brew doctor 2>&1); echo "$DOC" >>"$RAW"
  ND=$(printf '%s\n' "$DOC" | grep -c '^Warning:')
  if [ "$ND" -gt 0 ]; then warn 'brew doctor: %s warnings (details in the log)' "$ND"; else ok 'brew doctor: all good'; fi
fi
if task check.xcode; then
  if XP=$(xcode-select -p 2>/dev/null) && [ -d "$XP" ]; then
    XV=$(xcodebuild -version 2>/dev/null | head -1)
    ok 'Developer tools: %s (%s)' "${XV:-$(_ 'Command Line Tools only')}" "$(tildify "$XP")"
  else warn 'Developer tools: not installed or broken — run: xcode-select --install'; fi
  if have xcrun && have python3; then
    RT=$(xcrun simctl runtime list -j 2>/dev/null | python3 -c '
import json, sys
try: d = json.load(sys.stdin)
except Exception: sys.exit()
rs = sorted(d.values(), key=lambda r: (r.get("platformIdentifier",""), r.get("version","")))
print(len(rs), sum(r.get("sizeBytes", 0) for r in rs) // 1024)
for r in rs: print("%s %s · %.1f GB" % (r.get("platformIdentifier","").split(".")[-1].replace("platform",""), r.get("version","?"), r.get("sizeBytes",0)/1e9))' 2>/dev/null)
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
  have python3 && tool Python    "$(python3 -c 'import platform; print(platform.python_version())' 2>/dev/null)"
  have codex   && tool Codex     "$(codex --version 2>/dev/null | head -1 | awk '{print $NF}')"
  [ -n "$TOOLS" ] && info '%s' "$TOOLS"
  [ -d /Applications/Claude.app ] && info 'Claude Desktop %s (updates itself)' "$(defaults read /Applications/Claude.app/Contents/Info.plist CFBundleShortVersionString 2>/dev/null)"
fi
if task check.docker && have docker && docker info >/dev/null 2>&1; then
  DDF=$(docker system df 2>/dev/null | awk 'NR>1{printf "%s %s (%s); ", $1, $4, $5}')
  info 'Docker: %s' "${DDF%; }"
fi


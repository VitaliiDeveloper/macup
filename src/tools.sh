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
if task check.commands && have python3; then
  step 'Checking commands'
  # a script whose interpreter is gone stays on PATH and only fails when run ("env: node: No such file or directory"):
  # an unlinked keg-only node@24, a pipx venv whose Python was removed by brew, a link to a deleted file
  CMDS=$(python3 - "$HOME/.local/bin" "$HOME/.npm-global/bin" /opt/homebrew/bin /usr/local/bin <<'PY' 2>/dev/null
import glob, os, re, shutil, sys
n, groups = 0, {}
dirs = {}
for x in sys.argv[1:]:
    if os.path.isdir(x): dirs.setdefault(os.path.realpath(x), x)
for d in dirs.values():
    try: entries = list(os.scandir(d))
    except OSError: continue
    for e in entries:
        p = e.path
        # files Homebrew installed are brew doctor's job (libevent ships an `env python` script nobody runs)
        if "/Cellar/" in os.path.realpath(p): continue
        if not os.path.exists(p):
            if os.path.islink(p): groups.setdefault(("-", d), set()).add(e.name)
            continue
        if not os.path.isfile(p) or not os.access(p, os.X_OK): continue
        try:
            with open(p, "rb") as f: head = f.readline(256)
        except OSError: continue
        if not head.startswith(b"#!"): continue
        n += 1
        args = head[2:].decode("utf-8", "replace").split()
        if not args: continue
        if os.path.basename(args[0]) == "env":
            rest = [a for a in args[1:] if not a.startswith("-") and "=" not in a]
            if not rest or shutil.which(rest[0]): continue
            name = rest[0]
        elif os.access(args[0], os.X_OK): continue
        else: name = os.path.basename(args[0])
        if "/pipx/venvs/" in os.path.realpath(p): hint = "pipx reinstall-all"
        else:
            kegs = [k for pre in ("/opt/homebrew", "/usr/local") for k in glob.glob(f"{pre}/opt/{name}@*/bin/{name}")]
            # --overwrite too: a leftover npm in the prefix blocks the link, and brew's own advice for that omits --force
            hint = "brew link --force --overwrite " + max(kegs, key=lambda k: [int(x) for x in re.findall(r"\d+", k)]).split("/")[-3] if kegs else "-"
        groups.setdefault((name, hint), set()).add(e.name)
print(n)
for (name, hint), names in sorted(groups.items()):
    names = sorted(names)
    print(name, hint, ", ".join(names[:10]) + (f" +{len(names) - 10}" if len(names) > 10 else ""), sep="\t")
PY
)
  if [ -z "$CMDS" ]; then :   # the scan itself failed: no false "all can start"
  elif [ -z "$(printf '%s\n' "$CMDS" | tail -n +2)" ]; then ok 'Commands: all %s scripts in your bin folders can start' "$(printf '%s\n' "$CMDS" | head -1)"
  else
    while IFS=$'\t' read -r name hint names; do
      if [ "$name" = - ]; then warn 'Commands that cannot start, the file they link to is gone (%s): %s' "$(tildify "$hint")" "$names"
      elif [ "$hint" = - ]; then warn 'Commands that cannot start, %s is missing: %s' "$name" "$names"
      else warn 'Commands that cannot start, %s is missing: %s — run: %s' "$name" "$names" "$hint"; fi
    done <<EOF
$(printf '%s\n' "$CMDS" | tail -n +2)
EOF
  fi
fi
if task check.docker && have docker && docker info >/dev/null 2>&1; then
  DDF=$(docker system df 2>/dev/null | awk 'NR>1{printf "%s %s (%s); ", $1, $4, $5}')
  info 'Docker: %s' "${DDF%; }"
fi


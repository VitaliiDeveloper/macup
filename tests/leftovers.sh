#!/bin/bash
# Leftovers of deleted apps: launch agents, their folders, app data, system services, BTM records.
# Runs against fake homes, a fake /Applications (MACUP_APPS) and a fake /Library (MACUP_SYSLIB). tests/run.sh calls it.
cd "$(dirname "$0")/.." || exit 1
W=$(mktemp -d "${TMPDIR:-/tmp}/macup-leftovers.XXXXXX"); trap 'chflags -R nouchg "$W" 2>/dev/null; rm -rf "$W"' EXIT
F=0; pass(){ echo "PASS $*"; }; fail(){ echo "FAIL $*"; F=1; }
M="$PWD/macup"

mkdir -p "$W/bin"
cat >"$W/bin/pgrep" <<'FAKE'
#!/bin/bash
[ "$1" = "-f" ] && [ -n "$2" ] && printf '%s\n' "${FAKE_RUNNING:-}" | grep -qE -- "$2"
FAKE
cat >"$W/bin/lsof" <<'FAKE'
#!/bin/bash
printf 'p1\nn/\n'
FAKE
# codesign answers from FAKE_SIGN lines "path-prefix|TEAM|Name"; anything else is unsigned
cat >"$W/bin/codesign" <<'FAKE'
#!/bin/bash
p="${!#}"
while IFS='|' read -r pre team name; do
  [ -n "$pre" ] || continue
  case "$p" in "$pre"*) echo "Authority=Developer ID Application: $name ($team)" >&2; echo "TeamIdentifier=$team" >&2; exit 0 ;; esac
done <<EOF
${FAKE_SIGN:-}
EOF
echo "$p: code object is not signed at all" >&2; exit 1
FAKE
# launchctl records what macup asked; `print` finds only the labels in FAKE_LOADED
cat >"$W/bin/launchctl" <<'FAKE'
#!/bin/bash
echo "$*" >>"$HOME/launchctl.log"
if [ "$1" = print ]; then for l in ${FAKE_LOADED:-}; do case "$2" in */"$l") exit 0 ;; esac; done; exit 113; fi
exit 0
FAKE
cat >"$W/bin/osascript" <<'FAKE'
#!/bin/bash
exit 0
FAKE
chmod +x "$W/bin/"*; export PATH="$W/bin:$PATH"

app(){ # dir bundle-id
  mkdir -p "$1/Contents/MacOS"
  printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>%s</string></dict></plist>\n' "$2" >"$1/Contents/Info.plist"
}
agent(){ # file label program [assoc-id]
  local a=""; [ -n "$4" ] && a="<key>AssociatedBundleIdentifiers</key><array><string>$4</string></array>"
  mkdir -p "$(dirname "$1")"
  printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict><key>Label</key><string>%s</string><key>ProgramArguments</key><array><string>%s</string></array><key>StartInterval</key><integer>3600</integer>%s</dict></plist>\n' "$2" "$3" "$a" >"$1"
}
empty_plist(){ mkdir -p "$(dirname "$1")"; printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0">\n<dict/>\n</plist>\n' >"$1"; }
prog(){ mkdir -p "$(dirname "$1")"; dd if=/dev/zero of="$1" bs=1024 count="${2:-2048}" 2>/dev/null; chmod +x "$1"; }

leftovers_home(){ # dir
  local H=$1; chflags -R nouchg "$H" 2>/dev/null; rm -rf "$H"; mkdir -p "$H/.config/macup" "$H/.Trash"
  printf 'language = en\n' >"$H/.config/macup/config"
  local LA="$H/Library/LaunchAgents" AS="$H/Library/Application Support"
  app "$H/Apps/Steam.app" com.valvesoftware.steam
  app "$H/Apps/iStat.app" imagetasks.iStatistica
  app "$H/Apps/Vendor Folder/Tool.app" com.tool.app
  CU="$AS/Perplexity/CometUpdater/Current/CometUpdater.app/Contents/MacOS/CometUpdater"; prog "$CU"
  agent "$LA/ai.perplexity.CometUpdater.wake.plist" ai.perplexity.CometUpdater.wake "$CU" ai.perplexity.CometUpdater
  empty_plist "$LA/ai.perplexity.keystone.agent.plist"
  empty_plist "$LA/com.locked.empty.plist"; chflags uchg "$LA/com.locked.empty.plist"
  prog "$AS/Steam/SteamApps/steamclean"; agent "$LA/com.valvesoftware.steamclean.plist" com.valvesoftware.steamclean "$AS/Steam/SteamApps/steamclean"
  prog "$AS/iStat Helper/helper"; agent "$LA/com.imagetasks.helper.plist" com.imagetasks.helper "$AS/iStat Helper/helper"
  prog "$AS/Tool/bin/tool"; agent "$LA/com.tool.agent.plist" com.tool.agent "$AS/Tool/bin/tool"
  prog "$H/opt/homebrew/opt/redis/bin/redis-server" 1; agent "$LA/homebrew.mxcl.redis.plist" homebrew.mxcl.redis "$H/opt/homebrew/opt/redis/bin/redis-server"
  prog "$H/Library/pnpm/run.sh" 1; agent "$LA/com.me.script.plist" com.me.script "$H/Library/pnpm/run.sh"
  agent "$LA/com.gone.thing.plist" com.gone.thing /Applications/Gone.app/Contents/MacOS/Gone
  echo 'not a plist' >"$LA/broken.plist"
}
lo(){ # dir macup-args… — runs macup on that fake home and Mac
  local H=$1; shift
  env HOME="$H" MACUP_APPS="$H/Apps" MACUP_SYSLIB="$H/SysLib" FAKE_SIGN="$(printf '%s\n' \
    "$H/Library/Application Support/Perplexity|7S8W4W365S|Perplexity AI Inc." \
    "$H/Library/Application Support/iStat Helper|NF7JU763MN|ImageTasks Inc" \
    "$H/Apps/iStat.app|NF7JU763MN|ImageTasks Inc")" /bin/bash "$M" "$@"
}

# --- check.startup reports exactly the leftovers
H="$W/lo"; leftovers_home "$H"; lo "$H" check --only check.startup --no-color </dev/null >"$W/lo.out" 2>&1
o=$(tr -d '\r' <"$W/lo.out"); sec=$(printf '%s\n' "$o" | sed -n '/Leftovers of deleted apps/,$p'); bad=0
for l in ai.perplexity.CometUpdater.wake ai.perplexity.keystone.agent com.gone.thing; do
  printf '%s\n' "$sec" | grep -q "$l" || { fail "leftovers: $l not reported"; bad=1; }; done
for l in steamclean com.imagetasks.helper com.tool.agent homebrew.mxcl.redis com.me.script com.locked.empty; do
  printf '%s\n' "$sec" | grep -q "$l" && { fail "leftovers: live $l reported"; bad=1; }; done
printf '%s\n' "$o" | grep -q 'broken.plist.*cannot be read' || { fail "leftovers: broken plist not reported"; bad=1; }
printf '%s\n' "$o" | grep -qE 'line [0-9]+:|command not found|unbound' && { fail "leftovers: errors in output"; bad=1; }
[ $bad = 0 ] && pass "leftovers: report flags exactly the orphans" || printf '%s\n' "$o" | tail -25

[ $F = 0 ] || exit 1

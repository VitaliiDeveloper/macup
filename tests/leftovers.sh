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
printf 'p1\nn/\n'; printf '%s\n' "${FAKE_OPEN:-}" | sed '/^$/d; s/^/n/'
[ -n "$FAKE_LSOF_PAD" ] && jot -w 'n/private/var/folders/xx/pad%d' "$FAKE_LSOF_PAD"
exit 0
FAKE
# codesign answers from FAKE_SIGN lines "path-prefix|TEAM|Name"; anything else is unsigned
cat >"$W/bin/codesign" <<'FAKE'
#!/bin/bash
p="${!#}"; echo "$p" >>"$HOME/codesign.log"
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
cat >"$W/bin/sfltool" <<'FAKE'
#!/bin/bash
[ -n "$FAKE_BTM_HANG" ] && sleep 60
[ "$1" = dumpbtm ] && [ -f "${FAKE_BTM:-/nonexistent}" ] && cat "$FAKE_BTM"
exit 0
FAKE
# sudo records what it was asked and runs the rest as this user; FAKE_SUDO_FAIL=1 is a wrong password
cat >"$W/bin/sudo" <<'FAKE'
#!/bin/bash
echo "$*" >>"$HOME/sudo.log"
while [ $# -gt 0 ]; do
  case "$1" in
    -v) [ -n "$FAKE_SUDO_FAIL" ] && exit 1; shift ;;
    -k|-n) shift ;;
    -p) shift 2 ;;
    *) break ;;
  esac
done
[ $# -gt 0 ] && { [ "$1" = true ] && exit 0; exec "$@"; }
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

# --- clean.orphan_agents: picked leftovers go to the Trash, with their own folder
until_done(){ local i=0; while [ $i -lt 240 ]; do grep -q 'Report: ' "$1" 2>/dev/null && return; sleep 0.5; i=$((i + 1)); done; }
pk(){ # dir answer confirm [command run before answering] — interactive check of clean.orphan_agents
  local H=$1 out="$1.out"
  (sleep 2; [ -n "$4" ] && eval "$4"; printf '%s\n' "$2"; sleep 1; printf '%s\n' "$3"; until_done "$out") \
    | script -q /dev/null env FAKE_OPEN="${FAKE_OPEN:-}" FAKE_LSOF_PAD="${FAKE_LSOF_PAD:-}" FAKE_LOADED="${FAKE_LOADED:-}" FAKE_SUDO_FAIL="${FAKE_SUDO_FAIL:-}" HOME="$H" MACUP_APPS="$H/Apps" MACUP_SYSLIB="$H/SysLib" FAKE_SIGN="$(printf '%s\n' \
      "$H/Library/Application Support/Perplexity|7S8W4W365S|Perplexity AI Inc." \
      "$H/Library/Application Support/iStat Helper|NF7JU763MN|ImageTasks Inc" \
      "$H/Apps/iStat.app|NF7JU763MN|ImageTasks Inc")" /bin/bash "$M" check --only "${PK_ONLY:-clean.orphan_agents}" --no-color >"$out" 2>&1
}
nm(){ tr -d '\r' <"$1" | grep -E "^ +[0-9]+ .*$2" | head -1 | awk '{print $1}'; }
AS="Library/Application Support"
H="$W/pa"; leftovers_home "$H"; pk "$H" '' ''
o=$(tr -d '\r' <"$H.out")
printf '%s\n' "$o" | grep -q 'Leftovers of deleted apps — found' && printf '%s\n' "$o" | grep -q 'What:' && printf '%s\n' "$o" | grep -q 'Why:' \
  && ! printf '%s\n' "$o" | grep -q 'Application Support' && pass "orphan_agents: entries explain what and why, without paths" || { fail "orphan_agents: list"; printf '%s\n' "$o" | sed -n '/What can be cleaned/,$p' | head -30; }
nu=$(nm "$H.out" 'Perplexity AI · update program'); ne=$(nm "$H.out" 'Perplexity AI · empty startup file')

leftovers_home "$H"; FAKE_LOADED=ai.perplexity.CometUpdater.wake pk "$H" "$nu" y
[ -f "$H/.Trash/ai.perplexity.CometUpdater.wake.plist" ] && [ -d "$H/.Trash/CometUpdater" ] && [ ! -e "$H/$AS/Perplexity" ] && [ ! -e "$H/Library/LaunchAgents/ai.perplexity.CometUpdater.wake.plist" ] \
  && pass "orphan_agents: plist and updater folder in the Trash, emptied vendor folder too" || { fail "orphan_agents: move"; ls -R "$H/.Trash" | head; tr -d '\r' <"$H.out" | sed -n '/Cleanup/,$p' | head; }
grep -q "bootout gui/$(id -u)/ai.perplexity.CometUpdater.wake" "$H/launchctl.log" 2>/dev/null && pass "orphan_agents: a loaded agent is booted out" || fail "orphan_agents: no bootout"

leftovers_home "$H"; mkdir -p "$H/$AS/Perplexity/Other Product"; echo keep >"$H/$AS/Perplexity/Other Product/data"
pk "$H" "$nu" y
[ -d "$H/.Trash/CometUpdater" ] && [ -f "$H/$AS/Perplexity/Other Product/data" ] && ! grep -q bootout "$H/launchctl.log" 2>/dev/null \
  && pass "orphan_agents: a vendor folder with another product stays; nothing booted out when not loaded" || fail "orphan_agents: shared vendor folder"

leftovers_home "$H"; pk "$H" "$ne" y
[ -f "$H/.Trash/ai.perplexity.keystone.agent.plist" ] && ! grep -q 'bootout' "$H/launchctl.log" 2>/dev/null && pass "orphan_agents: an empty plist goes to the Trash" || fail "orphan_agents: empty plist"

leftovers_home "$H"; mkdir -p "$H/.Trash/CometUpdater"; echo old >"$H/.Trash/CometUpdater/old"
pk "$H" "$nu" y
[ -f "$H/.Trash/CometUpdater/old" ] && [ -d "$H/.Trash/CometUpdater 2/Current" ] && pass "orphan_agents: a name taken in the Trash is never overwritten" || { fail "orphan_agents: Trash collision"; ls "$H/.Trash"; }

leftovers_home "$H"; pk "$H" "$nu" y "app '$H/Apps/Comet.app' ai.perplexity.comet"
[ -f "$H/Library/LaunchAgents/ai.perplexity.CometUpdater.wake.plist" ] && [ -d "$H/$AS/Perplexity/CometUpdater" ] && tr -d '\r' <"$H.out" | grep -q 'still in use, skipped' \
  && pass "orphan_agents: an app installed again before the pick keeps its agent" || { fail "orphan_agents: re-check"; tr -d '\r' <"$H.out" | sed -n '/Cleanup/,$p' | head; }

leftovers_home "$H"; lo "$H" clean --level aggressive --only clean.orphan_agents --no-color </dev/null >/dev/null 2>&1
[ -f "$H/Library/LaunchAgents/ai.perplexity.CometUpdater.wake.plist" ] && [ -z "$(ls -A "$H/.Trash")" ] && pass "orphan_agents: nothing without a pick" || fail "orphan_agents: moved without a pick"

# --- clean.orphan_data: data of a vendor whose agent was orphaned
data_home(){ # dir
  local H=$1 L="$1/Library"; leftovers_home "$H"
  mkdir -p "$L/Preferences" "$L/HTTPStorages/ai.perplexity.CometUpdater" "$L/Application Support/Comet/Default" "$L/Perplexity" \
    "$L/Containers/ai.perplexity.mac.Notif" "$L/Group Containers/group.ai.perplexity.app" "$L/Application Support/Downloader"
  for f in ai.perplexity.comet ai.perplexity.downloader com.segment.analytics com.other.app; do empty_plist "$L/Preferences/$f.plist"; done
  echo h >"$L/Application Support/Comet/Default/History"; prog "$L/Application Support/Comet/Default/Cache" 4096
  echo x >"$L/Perplexity/x"; echo x >"$L/Containers/ai.perplexity.mac.Notif/x"; echo x >"$L/Group Containers/group.ai.perplexity.app/x"
  echo mine >"$L/Application Support/Downloader/x"; app "$H/Apps/Downloader.app" local.vitalii.downloader
}
H="$W/da"; data_home "$H"; PK_ONLY=clean.orphan_data pk "$H" '' ''
nd=$(nm "$H.out" 'Perplexity AI · data of a deleted app')
o=$(tr -d '\r' <"$H.out")
printf '%s\n' "$o" | grep -q '⚠ Perplexity AI · data of a deleted app' && printf '%s\n' "$o" | grep -q 'saved passwords' && printf '%s\n' "$o" | grep -q 'macOS may ask once' \
  && ! printf '%s\n' "$o" | grep -q 'Other ·' && pass "orphan_data: one warned entry per orphaned vendor, none for others" || { fail "orphan_data: list"; printf '%s\n' "$o" | sed -n '/What can be cleaned/,$p' | head -20; }
data_home "$H"; PK_ONLY=clean.orphan_data pk "$H" "$nd" y; T="$H/.Trash"
[ -f "$T/ai.perplexity.comet.plist" ] && [ -f "$T/ai.perplexity.downloader.plist" ] && [ -d "$T/ai.perplexity.CometUpdater" ] && [ -d "$T/Comet" ] && [ -d "$T/Perplexity" ] \
  && [ -d "$T/ai.perplexity.mac.Notif" ] && [ -d "$T/group.ai.perplexity.app" ] \
  && pass "orphan_data: prefs, profile, vendor folders and containers in the Trash" || { fail "orphan_data: move"; ls "$T"; }
[ -f "$H/Library/Application Support/Downloader/x" ] && [ -f "$H/Library/Preferences/com.segment.analytics.plist" ] && [ -f "$H/Library/Preferences/com.other.app.plist" ] \
  && pass "orphan_data: another app's folder of the same name and other vendors stay" || fail "orphan_data: took too much"
data_home "$H"; lo "$H" check --only clean.orphan_data --no-color </dev/null >/dev/null 2>&1; r=$(ls "$H"/Library/Logs/macup/*.md | tail -1)
grep -q 'Application Support/Comet' "$r" && ! grep -q 'Containers' "$r" && pass "orphan_data: unattended runs list paths in the report, never containers" || { fail "orphan_data: unattended"; grep -n 'Comet\|Containers' "$r" | head; }

# --- system leftovers: one password for all picked ones; a vendor prefix alone never qualifies
sys_home(){ # dir
  local H=$1; leftovers_home "$H"; rm -f "$H/Library/LaunchAgents/com.gone.thing.plist"
  agent "$H/SysLib/LaunchDaemons/com.gone.daemon.plist" com.gone.daemon "$H/SysLib/Gone/missing"
  mkdir -p "$H/SysLib/PrivilegedHelperTools"; echo bin >"$H/SysLib/PrivilegedHelperTools/com.gone.daemon"
  prog "$H/SysLib/Application Support/Prefix/bin/p" 1; agent "$H/SysLib/LaunchDaemons/com.prefix.only.plist" com.prefix.only "$H/SysLib/Application Support/Prefix/bin/p"
}
H="$W/sy"; sys_home "$H"; pk "$H" '' ''
nsd=$(nm "$H.out" 'Gone · system service'); npo=$(nm "$H.out" 'Prefix'); nu=$(nm "$H.out" 'Perplexity AI · update program')
[ -n "$nsd" ] && [ -z "$npo" ] && tr -d '\r' <"$H.out" | grep -q 'Needs your Mac password' && pass "system leftovers: offered only on strong evidence, marked as needing a password" || { fail "system leftovers: list"; tr -d '\r' <"$H.out" | sed -n '/What can be cleaned/,$p' | head -24; }
sys_home "$H"; pk "$H" "$nsd" y
[ "$(grep -c -- '^-v' "$H/sudo.log" 2>/dev/null)" = 1 ] && grep -q '^-k' "$H/sudo.log" && [ "$(tail -1 "$H/sudo.log")" = "-k" ] \
  && [ -f "$H/.Trash/com.gone.daemon.plist" ] && [ -f "$H/.Trash/com.gone.daemon" ] && pass "system leftovers: one password, plist and helper in the Trash, sudo forgotten after" || { fail "system leftovers: move"; cat "$H/sudo.log"; ls "$H/.Trash"; }
sys_home "$H"; FAKE_SUDO_FAIL=1 pk "$H" "$nsd,$nu" y
[ -f "$H/SysLib/LaunchDaemons/com.gone.daemon.plist" ] && [ -f "$H/.Trash/ai.perplexity.CometUpdater.wake.plist" ] && tr -d '\r' <"$H.out" | grep -q 'Password not accepted, system items skipped' \
  && pass "system leftovers: a wrong password skips only system items" || { fail "system leftovers: wrong password"; tr -d '\r' <"$H.out" | sed -n '/Clean now/,$p' | head; }
sys_home "$H"; lo "$H" check --only check.startup,clean.orphan_agents --no-color </dev/null >"$H.out" 2>&1
[ ! -e "$H/sudo.log" ] && grep -q 'sudo launchctl bootout system/com.gone.daemon' "$H.out" && grep -q 'sudo mv .*com.gone.daemon.plist' "$H.out" && grep -q 'com.prefix.only' "$H.out" \
  && pass "system leftovers: unattended runs only print the commands" || { fail "system leftovers: unattended"; sed -n '/Startup/,/Login items/p' "$H.out"; }

# --- Background Task Management: login items whose app is gone (read only)
H="$W/bt"; leftovers_home "$H"; U=$(id -u)
cat >"$H.btm" <<EOF
========================
 Records for UID -2 : FFFFEEEE-DDDD-CCCC-BBBB-AAAAFFFFFFFE
========================
 #1:
                 Name: Nobody
                  URL: /Users/-2/Applications/Nobody.app
========================
 Records for UID $U : 0BF99691-0E1F-433D-8FF0-0C94BE67D58A
========================
 #1:
                 Name: Ghost
                 Type: app (0x2)
                  URL: /Users/$U/Applications/Ghost.app
 #2:
                 Name: Steam
                  URL: /Users/$U/Apps/Steam.app
 #3:
                 Name: Xnull
                  URL: (null)
 #4:
                 Name: Yrel
                  URL: Contents/Library/LoginItems/Y.app
EOF
cp "$H.btm" "$H.full"
bt(){ (sleep 1; until_done "$H.out") | script -q /dev/null env FAKE_BTM="$H.btm" FAKE_BTM_HANG="${FAKE_BTM_HANG:-}" HOME="$H" MACUP_APPS="$H/Apps" MACUP_SYSLIB="$H/SysLib" /bin/bash "$M" check --only check.startup --no-color >"$H.out" 2>&1; tr -d '\r' <"$H.out" >"$H.o2"; mv "$H.o2" "$H.out"; }
bt
sec=$(sed -n '/Login items that point to deleted apps/,/Login items:/p' "$H.out")
printf '%s\n' "$sec" | grep -q 'Ghost' && ! printf '%s\n' "$sec" | grep -qE 'Steam|Xnull|Yrel|Nobody' && grep -q 'Login Items' "$H.out" \
  && pass "btm: only this user's records that point to a missing app" || { fail "btm"; sed -n '/Startup/,/Summary/p' "$H.out"; }
: >"$H.btm"; bt; cp "$H.full" "$H.btm"
! grep -q 'point to deleted apps' "$H.out" && ! grep -qE 'line [0-9]+:|command not found' "$H.out" && pass "btm: nothing to parse, nothing said" || fail "btm: empty output"

FAKE_BTM="$H.btm" lo "$H" check --only check.startup --no-color </dev/null >"$H.out" 2>&1
! grep -q 'Ghost' "$H.out" && pass "btm: unattended runs never ask sfltool" || fail "btm: unattended run read BTM"
t0=$SECONDS; FAKE_BTM_HANG=1 bt
[ $((SECONDS - t0)) -lt 40 ] && ! grep -q 'point to deleted apps' "$H.out" && pass "btm: a hanging sfltool is given up on" || fail "btm: hang ($((SECONDS - t0))s)"

# --- review findings: a folder is never taken by mistake
rv_home(){ # dir
  local H=$1 AS="$1/Library/Application Support" LA="$1/Library/LaunchAgents"; data_home "$H"
  prog "$AS/Flat/updater" 1; mkdir -p "$AS/Flat/Profile"; echo mine >"$AS/Flat/Profile/data"; agent "$LA/com.flat.updater.plist" com.flat.updater "$AS/Flat/updater"
  agent "$LA/com.valvesoftware.steamold.plist" com.valvesoftware.steamold "$AS/Steam/SteamApps/gone-binary"
  prog "$AS/MailRu/upd/u" 1; agent "$LA/ru.mail.updater.plist" ru.mail.updater "$AS/MailRu/upd/u"
  mkdir -p "$H/Library/Mail"; echo mail >"$H/Library/Mail/x"; empty_plist "$H/Library/Preferences/com.apple.mail.plist"
  prog "$AS/Zedco/a/b" 1; agent "$LA/com.zedco.agent.plist" com.zedco.agent "$AS/Zedco/a/b"; empty_plist "$H/Library/Preferences/com.zedco.AddressBook.plist"
  mkdir -p "$AS/AddressBook"; echo card >"$AS/AddressBook/x"; empty_plist "$H/Library/Preferences/com.apple.AddressBook.plist"
  prog "$AS/MyScripts/bin/run" 1; agent "$LA/mybackup.plist" mybackup "$AS/MyScripts/bin/run"
}
H="$W/rv"; rv_home "$H"; PK_ONLY=clean.orphan_agents,clean.orphan_data,check.startup pk "$H" '' ''
nf=$(nm "$H.out" 'Flat · update program'); ns=$(nm "$H.out" 'Valvesoftware ·'); r=$(ls "$H"/Library/Logs/macup/*.md | tail -1)
! grep -q 'mybackup —' "$r" && pass "review: a label without a vendor is never an orphan" || fail "review: mybackup flagged"
! grep -q '~/Library/Mail`' "$r" && ! grep -q 'Application Support/AddressBook' "$r" && pass "review: data never takes folders of Apple's apps" || { fail "review: Apple folder offered"; grep -n 'Mail\\|AddressBook' "$r"; }
rv_home "$H"; PK_ONLY=clean.orphan_agents,clean.orphan_data,check.startup pk "$H" "$nf,$ns" y
[ -f "$H/.Trash/com.flat.updater.plist" ] && [ -f "$H/Library/Application Support/Flat/Profile/data" ] && pass "review: a program right in the vendor folder takes only its plist" || { fail "review: vendor folder taken"; ls "$H/.Trash"; }
[ -f "$H/.Trash/com.valvesoftware.steamold.plist" ] && [ -f "$H/Library/Application Support/Steam/SteamApps/steamclean" ] && pass "review: a missing program takes only its plist" || { fail "review: missing took a folder"; ls "$H/.Trash"; }
H="$W/cs"; leftovers_home "$H"; for f in "$H"/Library/LaunchAgents/*; do case "$f" in *steamclean*) ;; *) chflags nouchg "$f"; rm -f "$f" ;; esac; done
env HOME="$H" MACUP_APPS="$H/Apps" MACUP_SYSLIB="$H/SysLib" FAKE_SIGN="$H/Library/Application Support/Steam|MXGJJ98X76|Valve Corporation" /bin/bash "$M" check --only check.startup --no-color </dev/null >/dev/null 2>&1
! grep -q "$H/Apps" "$H/codesign.log" 2>/dev/null && pass "review: no codesign of every app when the vendor alone settles it" || fail "review: codesign ran on apps"
H="$W/op"; data_home "$H"; PK_ONLY=clean.orphan_data pk "$H" '' ''; nd=$(nm "$H.out" 'data of a deleted app')
data_home "$H"; FAKE_OPEN="$H/Library/Application Support/Comet/Default/History" PK_ONLY=clean.orphan_data pk "$H" "$nd" y
[ -d "$H/Library/Application Support/Comet" ] && tr -d '\r' <"$H.out" | grep -qE 'skipped while the app is open|still in use' && pass "review: data in use is skipped" || { fail "review: data in use moved"; tr -d '\r' <"$H.out" | sed -n '/Cleanup/,$p' | head -5; }

# --- totals count a folder once, even when two entries contain it
H="$W/tt"; data_home "$H"; PK_ONLY=clean.orphan_agents,clean.orphan_data pk "$H" '' ''
o=$(tr -d '\r' <"$H.out")
ht=$(printf '%s\n' "$o" | sed -n 's/.*Leftovers of deleted apps — found [0-9]*, total \(.*\)$/\1/p')
dz=$(printf '%s\n' "$o" | grep 'data of a deleted app' | awk '{print $3, $4}')
pm=$(printf '%s\n' "$o" | sed -n 's/.*More with a higher level or by picking: ~\(.*\)$/\1/p')
[ -n "$dz" ] && [ "$ht" = "$dz" ] && [ "$pm" = "$dz" ] && pass "totals: a folder inside two entries is counted once" || fail "totals: heading '$ht', more '$pm', data entry '$dz'"

# --- a folder named like the deleted app but holding an installed app's files stays
H="$W/hd"; data_home "$H"; app "$H/Apps/Writer.app" com.example.writer
echo s >"$H/Library/Application Support/Comet/Default/com.example.writer.state"
mkdir -p "$H/Library/Perplexity/Writer"
lo "$H" check --only clean.orphan_data --no-color </dev/null >/dev/null 2>&1; r=$(ls "$H"/Library/Logs/macup/*.md | tail -1)
! grep -q 'Application Support/Comet`' "$r" && ! grep -q '~/Library/Perplexity`' "$r" && grep -q 'Preferences/ai.perplexity.comet.plist' "$r" \
  && pass "data: a folder that holds an installed app's files stays" || { fail "data: shared folder offered"; sed -n '/What can be cleaned/,$p' "$r" | head -20; }

# --- deferred minors
H="$W/mh"; leftovers_home "$H"; mkdir -p "$H/SysLib/PrivilegedHelperTools"; echo bin >"$H/SysLib/PrivilegedHelperTools/com.gone.thing"
pk "$H" '' ''; ng=$(nm "$H.out" 'Gone ·'); leftovers_home "$H"; mkdir -p "$H/SysLib/PrivilegedHelperTools"; echo bin >"$H/SysLib/PrivilegedHelperTools/com.gone.thing"
pk "$H" "$ng" y
[ -f "$H/.Trash/com.gone.thing.plist" ] && [ -f "$H/SysLib/PrivilegedHelperTools/com.gone.thing" ] && [ ! -e "$H/sudo.log" ] && pass "minor: a user agent never takes a system helper" || { fail "minor: user agent took a helper"; ls "$H/.Trash"; }
H="$W/mr"; leftovers_home "$H"; chmod 000 "$H/Library/LaunchAgents/com.me.script.plist"
lo "$H" check --only check.startup --no-color </dev/null >"$H.out" 2>&1; chmod 644 "$H/Library/LaunchAgents/com.me.script.plist"
! grep -q 'com.me.script.plist cannot be read (not a valid plist)' "$H.out" && grep -q 'broken.plist cannot be read' "$H.out" && pass "minor: a plist we may not read is not called invalid" || fail "minor: unreadable plist called invalid"
H="$W/mp"; leftovers_home "$H"; prog "$H/Library/Application Support/FooTool/x/y" 1; agent "$H/Library/LaunchAgents/io.github.foo.agent.plist" io.github.foo.agent "$H/Library/Application Support/FooTool/x/y"
empty_plist "$H/Library/Preferences/io.github.foo.plist"; empty_plist "$H/Library/Preferences/io.github.bar.plist"
lo "$H" check --only clean.orphan_data --no-color </dev/null >/dev/null 2>&1; r=$(ls "$H"/Library/Logs/macup/*.md | tail -1)
grep -q 'io.github.foo.plist' "$r" && ! grep -q 'io.github.bar.plist' "$r" && pass "minor: a shared hosting prefix (io.github) is not one vendor" || { fail "minor: io.github swept"; grep -n 'io.github' "$r"; }

# --- second review
H="$W/ob"; data_home "$H"; PK_ONLY=clean.orphan_data pk "$H" '' ''; nd=$(nm "$H.out" 'data of a deleted app')
data_home "$H"; FAKE_LSOF_PAD=40000 FAKE_OPEN="$H/Library/Application Support/Comet/Default/History" PK_ONLY=clean.orphan_data pk "$H" "$nd" y
[ -d "$H/Library/Application Support/Comet" ] && pass "review2: an open file is seen in a real-sized lsof listing" || fail "review2: open file missed in a big lsof listing"
H="$W/hu"; data_home "$H"; app "$H/Apps/Writer.app" com.example.writer; echo s >"$H/Library/Application Support/Comet/com.example.writer.state"
mkdir -p "$H/Library/Application Support/Comet/Locked"; chmod 000 "$H/Library/Application Support/Comet/Locked"
lo "$H" check --only clean.orphan_data --no-color </dev/null >/dev/null 2>&1; chmod 755 "$H/Library/Application Support/Comet/Locked"; r=$(ls "$H"/Library/Logs/macup/*.md | tail -1)
! grep -q 'Application Support/Comet`' "$r" && pass "review2: an unreadable subfolder does not hide an installed app's files" || fail "review2: held failed open on an unreadable subfolder"
H="$W/ws"; data_home "$H"; empty_plist "$H/Library/Preferences/ai.perplexity.my app.plist"; mkdir -p "$H/Library/Application Support/My"; echo x >"$H/Library/Application Support/My/x"
lo "$H" check --only clean.orphan_data --no-color </dev/null >/dev/null 2>&1; r=$(ls "$H"/Library/Logs/macup/*.md | tail -1)
! grep -q 'Application Support/My`' "$r" && grep -q 'ai.perplexity.my app.plist' "$r" && pass "review2: an id with a space is one id" || fail "review2: id split on a space"
H="$W/gn"; leftovers_home "$H"; prog "$H/Library/Application Support/FooTool/x/y" 1; agent "$H/Library/LaunchAgents/io.github.foo.agent.plist" io.github.foo.agent "$H/Library/Application Support/FooTool/x/y"
lo "$H" check --only check.startup --no-color </dev/null >"$H.out" 2>&1
grep -q 'Foo · io.github.foo.agent' "$H.out" && pass "review2: a three-part vendor is named by its owner" || { fail "review2: vendor name"; grep 'io.github' "$H.out"; }

[ $F = 0 ] || exit 1

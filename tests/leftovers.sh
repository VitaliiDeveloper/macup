#!/bin/bash
# shellcheck disable=SC2088  # the report prints paths with a literal ~
# Leftovers of deleted apps: launch agents, their folders, app data, system services.
# Runs against fake homes, a fake /Applications (MACUP_APPS) and a fake /Library (MACUP_SYSLIB). tests/run.sh calls it.
cd "$(dirname "$0")/.." || exit 1
work=$(mktemp -d "${TMPDIR:-/tmp}/macup-leftovers.XXXXXX"); trap 'chflags -R nouchg "$work" 2>/dev/null; rm -rf "$work"' EXIT
F=0; pass(){ echo "PASS $*"; }; fail(){ echo "FAIL $*"; F=1; }

mkdir -p "$work/bin"
cat >"$work/bin/pgrep" <<'FAKE'
#!/bin/bash
[ "$1" = "-f" ] && [ -n "$2" ] && printf '%s\n' "${FAKE_RUNNING:-}" | grep -qE -- "$2"
FAKE
cat >"$work/bin/lsof" <<'FAKE'
#!/bin/bash
printf 'p1\nn/\n'; printf '%s\n' "${FAKE_OPEN:-}" | sed '/^$/d; s/^/n/'
[ -n "$FAKE_LSOF_PAD" ] && jot -w 'n/private/var/folders/xx/pad%d' "$FAKE_LSOF_PAD"
exit 0
FAKE
# codesign answers from FAKE_SIGN lines "path-prefix|TEAM|Name"; anything else is unsigned
cat >"$work/bin/codesign" <<'FAKE'
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
cat >"$work/bin/launchctl" <<'FAKE'
#!/bin/bash
echo "$*" >>"$HOME/launchctl.log"
if [ "$1" = print ]; then for l in ${FAKE_LOADED:-}; do case "$2" in */"$l") exit 0 ;; esac; done; exit 113; fi
exit 0
FAKE
cat >"$work/bin/sfltool" <<'FAKE'
#!/bin/bash
echo "$*" >>"$HOME/sfltool.log"
FAKE
# sudo records what it was asked and runs the rest as this user; FAKE_SUDO_FAIL=1 is a wrong password
cat >"$work/bin/sudo" <<'FAKE'
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
cat >"$work/bin/osascript" <<'FAKE' 
#!/bin/bash
exit 0
FAKE
chmod +x "$work/bin/"*; export PATH="$work/bin:$PATH" MACUP_PATH=keep   # the fakes above win over Homebrew's tools
ln -s "$PWD/tests/macup_run" "$work/bin/macup_run"   # the build under test (MACUP_BUILD, MACUP_BIN from tests/run.sh)

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
  local home=$1; chflags -R nouchg "$home" 2>/dev/null; rm -rf "$home"; mkdir -p "$home/.config/macup" "$home/.Trash"
  printf 'language = en\n' >"$home/.config/macup/config"
  local LA="$home/Library/LaunchAgents" AS="$home/Library/Application Support"
  app "$home/Apps/Steam.app" com.valvesoftware.steam
  app "$home/Apps/iStat.app" imagetasks.iStatistica
  app "$home/Apps/Vendor Folder/Tool.app" com.tool.app
  CU="$AS/Perplexity/CometUpdater/Current/CometUpdater.app/Contents/MacOS/CometUpdater"; prog "$CU"
  agent "$LA/ai.perplexity.CometUpdater.wake.plist" ai.perplexity.CometUpdater.wake "$CU" ai.perplexity.CometUpdater
  empty_plist "$LA/ai.perplexity.keystone.agent.plist"
  empty_plist "$LA/com.locked.empty.plist"; chflags uchg "$LA/com.locked.empty.plist"
  prog "$AS/Steam/SteamApps/steamclean"; agent "$LA/com.valvesoftware.steamclean.plist" com.valvesoftware.steamclean "$AS/Steam/SteamApps/steamclean"
  prog "$AS/iStat Helper/helper"; agent "$LA/com.imagetasks.helper.plist" com.imagetasks.helper "$AS/iStat Helper/helper"
  prog "$AS/Tool/bin/tool"; agent "$LA/com.tool.agent.plist" com.tool.agent "$AS/Tool/bin/tool"
  prog "$home/opt/homebrew/opt/redis/bin/redis-server" 1; agent "$LA/homebrew.mxcl.redis.plist" homebrew.mxcl.redis "$home/opt/homebrew/opt/redis/bin/redis-server"
  prog "$home/Library/pnpm/run.sh" 1; agent "$LA/com.me.script.plist" com.me.script "$home/Library/pnpm/run.sh"
  agent "$LA/com.gone.thing.plist" com.gone.thing /Applications/Gone.app/Contents/MacOS/Gone
  echo 'not a plist' >"$LA/broken.plist"
}
lo(){ # dir macup-args… — runs macup on that fake home and Mac
  local home=$1; shift
  env HOME="$home" MACUP_APPS="$home/Apps" MACUP_SYSLIB="$home/SysLib" FAKE_SIGN="$(printf '%s\n' \
    "$home/Library/Application Support/Perplexity|7S8W4W365S|Perplexity AI Inc." \
    "$home/Library/Application Support/iStat Helper|NF7JU763MN|ImageTasks Inc" \
    "$home/Apps/iStat.app|NF7JU763MN|ImageTasks Inc")" macup_run "$@"
}

# --- check.startup reports exactly the leftovers
home="$work/lo"; leftovers_home "$home"; lo "$home" check --only check.startup --no-color </dev/null >"$work/lo.out" 2>&1
o=$(tr -d '\r' <"$work/lo.out"); sec=$(printf '%s\n' "$o" | sed -n '/Leftovers of deleted apps/,$p'); bad=0
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
  local home=$1 out="$1.out"
  (sleep 2; [ -n "$4" ] && eval "$4"; printf '%s\n' "$2"; sleep 1; printf '%s\n' "$3"; until_done "$out") 2>/dev/null \
    | script -q /dev/null env FAKE_OPEN="${FAKE_OPEN:-}" FAKE_LSOF_PAD="${FAKE_LSOF_PAD:-}" FAKE_LOADED="${FAKE_LOADED:-}" FAKE_SUDO_FAIL="${FAKE_SUDO_FAIL:-}" HOME="$home" MACUP_APPS="$home/Apps" MACUP_SYSLIB="$home/SysLib" FAKE_SIGN="$(printf '%s\n' \
      "$home/Library/Application Support/Perplexity|7S8W4W365S|Perplexity AI Inc." \
      "$home/Library/Application Support/iStat Helper|NF7JU763MN|ImageTasks Inc" \
      "$home/Apps/iStat.app|NF7JU763MN|ImageTasks Inc")" macup_run check --only "${PK_ONLY:-clean.orphan_agents}" --no-color >"$out" 2>&1
}
nm(){ tr -d '\r' <"$1" | grep -E "^ +[0-9]+ .*$2" | head -1 | awk '{print $1}'; }
AS="Library/Application Support"
home="$work/pa"; leftovers_home "$home"; pk "$home" '' ''
o=$(tr -d '\r' <"$home.out")
printf '%s\n' "$o" | grep -q 'Leftovers of deleted apps — found' && printf '%s\n' "$o" | grep -q 'What:' && printf '%s\n' "$o" | grep -q 'Why:' \
  && ! printf '%s\n' "$o" | grep -q 'Application Support' && pass "orphan_agents: entries explain what and why, without paths" || { fail "orphan_agents: list"; printf '%s\n' "$o" | sed -n '/What can be cleaned/,$p' | head -30; }
nu=$(nm "$home.out" 'Perplexity AI · update program'); ne=$(nm "$home.out" 'Perplexity AI · empty startup file')

leftovers_home "$home"; FAKE_LOADED=ai.perplexity.CometUpdater.wake pk "$home" "$nu" y
[ -f "$home/.Trash/ai.perplexity.CometUpdater.wake.plist" ] && [ -d "$home/.Trash/CometUpdater" ] && [ ! -e "$home/$AS/Perplexity" ] && [ ! -e "$home/Library/LaunchAgents/ai.perplexity.CometUpdater.wake.plist" ] \
  && pass "orphan_agents: plist and updater folder in the Trash, emptied vendor folder too" || { fail "orphan_agents: move"; ls -R "$home/.Trash" | head; tr -d '\r' <"$home.out" | sed -n '/Cleanup/,$p' | head; }
grep -q "bootout gui/$(id -u)/ai.perplexity.CometUpdater.wake" "$home/launchctl.log" 2>/dev/null && pass "orphan_agents: a loaded agent is booted out" || fail "orphan_agents: no bootout"

leftovers_home "$home"; mkdir -p "$home/$AS/Perplexity/Other Product"; echo keep >"$home/$AS/Perplexity/Other Product/data"
pk "$home" "$nu" y
[ -d "$home/.Trash/CometUpdater" ] && [ -f "$home/$AS/Perplexity/Other Product/data" ] && ! grep -q bootout "$home/launchctl.log" 2>/dev/null \
  && pass "orphan_agents: a vendor folder with another product stays; nothing booted out when not loaded" || fail "orphan_agents: shared vendor folder"

leftovers_home "$home"; pk "$home" "$ne" y
[ -f "$home/.Trash/ai.perplexity.keystone.agent.plist" ] && ! grep -q 'bootout' "$home/launchctl.log" 2>/dev/null && pass "orphan_agents: an empty plist goes to the Trash" || fail "orphan_agents: empty plist"

leftovers_home "$home"; mkdir -p "$home/.Trash/CometUpdater"; echo old >"$home/.Trash/CometUpdater/old"
pk "$home" "$nu" y
[ -f "$home/.Trash/CometUpdater/old" ] && [ -d "$home/.Trash/CometUpdater 2/Current" ] && pass "orphan_agents: a name taken in the Trash is never overwritten" || { fail "orphan_agents: Trash collision"; ls "$home/.Trash"; }

leftovers_home "$home"; pk "$home" "$nu" y "app '$home/Apps/Comet.app' ai.perplexity.comet"
[ -f "$home/Library/LaunchAgents/ai.perplexity.CometUpdater.wake.plist" ] && [ -d "$home/$AS/Perplexity/CometUpdater" ] && tr -d '\r' <"$home.out" | grep -q 'still in use, skipped' \
  && pass "orphan_agents: an app installed again before the pick keeps its agent" || { fail "orphan_agents: re-check"; tr -d '\r' <"$home.out" | sed -n '/Cleanup/,$p' | head; }

leftovers_home "$home"; lo "$home" clean --level aggressive --only clean.orphan_agents --no-color </dev/null >/dev/null 2>&1
[ -f "$home/Library/LaunchAgents/ai.perplexity.CometUpdater.wake.plist" ] && [ -z "$(ls -A "$home/.Trash")" ] && pass "orphan_agents: nothing without a pick" || fail "orphan_agents: moved without a pick"

# --- clean.orphan_data: data of a vendor whose agent was orphaned
data_home(){ # dir
  local home=$1 L="$1/Library"; leftovers_home "$home"
  mkdir -p "$L/Preferences" "$L/HTTPStorages/ai.perplexity.CometUpdater" "$L/Application Support/Comet/Default" "$L/Perplexity" \
    "$L/Containers/ai.perplexity.mac.Notif" "$L/Group Containers/group.ai.perplexity.app" "$L/Application Support/Downloader"
  for f in ai.perplexity.comet ai.perplexity.downloader com.segment.analytics com.other.app; do empty_plist "$L/Preferences/$f.plist"; done
  echo h >"$L/Application Support/Comet/Default/History"; prog "$L/Application Support/Comet/Default/Cache" 4096
  echo x >"$L/Perplexity/x"; echo x >"$L/Containers/ai.perplexity.mac.Notif/x"; echo x >"$L/Group Containers/group.ai.perplexity.app/x"
  echo mine >"$L/Application Support/Downloader/x"; app "$home/Apps/Downloader.app" local.vitalii.downloader
}
home="$work/da"; data_home "$home"; PK_ONLY=clean.orphan_data pk "$home" '' ''
nd=$(nm "$home.out" 'Perplexity AI · data of a deleted app')
o=$(tr -d '\r' <"$home.out")
printf '%s\n' "$o" | grep -q '⚠ Perplexity AI · data of a deleted app' && printf '%s\n' "$o" | grep -q 'saved passwords' && printf '%s\n' "$o" | grep -q 'macOS may ask once' \
  && ! printf '%s\n' "$o" | grep -q 'Other ·' && pass "orphan_data: one warned entry per orphaned vendor, none for others" || { fail "orphan_data: list"; printf '%s\n' "$o" | sed -n '/What can be cleaned/,$p' | head -20; }
data_home "$home"; PK_ONLY=clean.orphan_data pk "$home" "$nd" y; T="$home/.Trash"
[ -f "$T/ai.perplexity.comet.plist" ] && [ -f "$T/ai.perplexity.downloader.plist" ] && [ -d "$T/ai.perplexity.CometUpdater" ] && [ -d "$T/Comet" ] && [ -d "$T/Perplexity" ] \
  && [ -d "$T/ai.perplexity.mac.Notif" ] && [ -d "$T/group.ai.perplexity.app" ] \
  && pass "orphan_data: prefs, profile, vendor folders and containers in the Trash" || { fail "orphan_data: move"; ls "$T"; }
[ -f "$home/Library/Application Support/Downloader/x" ] && [ -f "$home/Library/Preferences/com.segment.analytics.plist" ] && [ -f "$home/Library/Preferences/com.other.app.plist" ] \
  && pass "orphan_data: another app's folder of the same name and other vendors stay" || fail "orphan_data: took too much"
data_home "$home"; lo "$home" check --only clean.orphan_data --no-color </dev/null >/dev/null 2>&1; r=$(ls "$home"/Library/Logs/macup/*.md | tail -1)
grep -q 'Application Support/Comet' "$r" && ! grep -q 'Containers' "$r" && pass "orphan_data: unattended runs list paths in the report, never containers" || { fail "orphan_data: unattended"; grep -n 'Comet\|Containers' "$r" | head; }

# --- system leftovers: one password for all picked ones; a vendor prefix alone never qualifies
sys_home(){ # dir
  local home=$1; leftovers_home "$home"; rm -f "$home/Library/LaunchAgents/com.gone.thing.plist"
  agent "$home/SysLib/LaunchDaemons/com.gone.daemon.plist" com.gone.daemon "$home/SysLib/Gone/missing"
  mkdir -p "$home/SysLib/PrivilegedHelperTools"; echo bin >"$home/SysLib/PrivilegedHelperTools/com.gone.daemon"
  prog "$home/SysLib/Application Support/Prefix/bin/p" 1; agent "$home/SysLib/LaunchDaemons/com.prefix.only.plist" com.prefix.only "$home/SysLib/Application Support/Prefix/bin/p"
}
home="$work/sy"; sys_home "$home"; pk "$home" '' ''
nsd=$(nm "$home.out" 'Gone · system service'); npo=$(nm "$home.out" 'Prefix'); nu=$(nm "$home.out" 'Perplexity AI · update program')
[ -n "$nsd" ] && [ -z "$npo" ] && tr -d '\r' <"$home.out" | grep -q 'Needs your Mac password' && pass "system leftovers: offered only on strong evidence, marked as needing a password" || { fail "system leftovers: list"; tr -d '\r' <"$home.out" | sed -n '/What can be cleaned/,$p' | head -24; }
sys_home "$home"; pk "$home" "$nsd" y
[ "$(grep -c -- '^-v' "$home/sudo.log" 2>/dev/null)" = 1 ] && grep -q '^-k' "$home/sudo.log" && [ "$(tail -1 "$home/sudo.log")" = "-k" ] \
  && [ -f "$home/.Trash/com.gone.daemon.plist" ] && [ -f "$home/.Trash/com.gone.daemon" ] && pass "system leftovers: one password, plist and helper in the Trash, sudo forgotten after" || { fail "system leftovers: move"; cat "$home/sudo.log"; ls "$home/.Trash"; }
sys_home "$home"; FAKE_SUDO_FAIL=1 pk "$home" "$nsd,$nu" y
[ -f "$home/SysLib/LaunchDaemons/com.gone.daemon.plist" ] && [ -f "$home/.Trash/ai.perplexity.CometUpdater.wake.plist" ] && tr -d '\r' <"$home.out" | grep -q 'Password not accepted, system items skipped' \
  && pass "system leftovers: a wrong password skips only system items" || { fail "system leftovers: wrong password"; tr -d '\r' <"$home.out" | sed -n '/Clean now/,$p' | head; }
sys_home "$home"; lo "$home" check --only check.startup,clean.orphan_agents --no-color </dev/null >"$home.out" 2>&1
[ ! -e "$home/sudo.log" ] && grep -q 'sudo launchctl bootout system/com.gone.daemon' "$home.out" && grep -q 'sudo mv .*com.gone.daemon.plist' "$home.out" && grep -q 'com.prefix.only' "$home.out" \
  && pass "system leftovers: unattended runs only print the commands" || { fail "system leftovers: unattended"; sed -n '/Startup/,/Login items/p' "$home.out"; }

# --- Background Task Management is never read: sfltool dumpbtm asks for an administrator password (SecurityAgent)
home="$work/bt"; leftovers_home "$home"
(sleep 1; until_done "$home.out") | script -q /dev/null env HOME="$home" MACUP_APPS="$home/Apps" MACUP_SYSLIB="$home/SysLib" macup_run check --only check.startup --no-color >"$home.out" 2>&1
[ ! -e "$home/sfltool.log" ] && pass "btm: sfltool is never run, so no password dialog" || fail "btm: sfltool was run"

# --- review findings: a folder is never taken by mistake
rv_home(){ # dir
  local home=$1 AS="$1/Library/Application Support" LA="$1/Library/LaunchAgents"; data_home "$home"
  prog "$AS/Flat/updater" 1; mkdir -p "$AS/Flat/Profile"; echo mine >"$AS/Flat/Profile/data"; agent "$LA/com.flat.updater.plist" com.flat.updater "$AS/Flat/updater"
  agent "$LA/com.valvesoftware.steamold.plist" com.valvesoftware.steamold "$AS/Steam/SteamApps/gone-binary"
  prog "$AS/MailRu/upd/u" 1; agent "$LA/ru.mail.updater.plist" ru.mail.updater "$AS/MailRu/upd/u"
  mkdir -p "$home/Library/Mail"; echo mail >"$home/Library/Mail/x"; empty_plist "$home/Library/Preferences/com.apple.mail.plist"
  prog "$AS/Zedco/a/b" 1; agent "$LA/com.zedco.agent.plist" com.zedco.agent "$AS/Zedco/a/b"; empty_plist "$home/Library/Preferences/com.zedco.AddressBook.plist"
  mkdir -p "$AS/AddressBook"; echo card >"$AS/AddressBook/x"; empty_plist "$home/Library/Preferences/com.apple.AddressBook.plist"
  prog "$AS/MyScripts/bin/run" 1; agent "$LA/mybackup.plist" mybackup "$AS/MyScripts/bin/run"
}
home="$work/rv"; rv_home "$home"; PK_ONLY=clean.orphan_agents,clean.orphan_data,check.startup pk "$home" '' ''
nf=$(nm "$home.out" 'Flat · update program'); ns=$(nm "$home.out" 'Valvesoftware ·'); r=$(ls "$home"/Library/Logs/macup/*.md | tail -1)
! grep -q 'mybackup —' "$r" && pass "review: a label without a vendor is never an orphan" || fail "review: mybackup flagged"
! grep -q '~/Library/Mail`' "$r" && ! grep -q 'Application Support/AddressBook' "$r" && pass "review: data never takes folders of Apple's apps" || { fail "review: Apple folder offered"; grep -n 'Mail\\|AddressBook' "$r"; }
rv_home "$home"; PK_ONLY=clean.orphan_agents,clean.orphan_data,check.startup pk "$home" "$nf,$ns" y
[ -f "$home/.Trash/com.flat.updater.plist" ] && [ -f "$home/Library/Application Support/Flat/Profile/data" ] && pass "review: a program right in the vendor folder takes only its plist" || { fail "review: vendor folder taken"; ls "$home/.Trash"; }
[ -f "$home/.Trash/com.valvesoftware.steamold.plist" ] && [ -f "$home/Library/Application Support/Steam/SteamApps/steamclean" ] && pass "review: a missing program takes only its plist" || { fail "review: missing took a folder"; ls "$home/.Trash"; }
home="$work/cs"; leftovers_home "$home"; for f in "$home"/Library/LaunchAgents/*; do case "$f" in *steamclean*) ;; *) chflags nouchg "$f"; rm -f "$f" ;; esac; done
env HOME="$home" MACUP_APPS="$home/Apps" MACUP_SYSLIB="$home/SysLib" FAKE_SIGN="$home/Library/Application Support/Steam|MXGJJ98X76|Valve Corporation" macup_run check --only check.startup --no-color </dev/null >/dev/null 2>&1
! grep -q "$home/Apps" "$home/codesign.log" 2>/dev/null && pass "review: no codesign of every app when the vendor alone settles it" || fail "review: codesign ran on apps"
home="$work/op"; data_home "$home"; PK_ONLY=clean.orphan_data pk "$home" '' ''; nd=$(nm "$home.out" 'data of a deleted app')
data_home "$home"; FAKE_OPEN="$home/Library/Application Support/Comet/Default/History" PK_ONLY=clean.orphan_data pk "$home" "$nd" y
[ -d "$home/Library/Application Support/Comet" ] && tr -d '\r' <"$home.out" | grep -qE 'skipped while the app is open|still in use' && pass "review: data in use is skipped" || { fail "review: data in use moved"; tr -d '\r' <"$home.out" | sed -n '/Cleanup/,$p' | head -5; }

# --- totals count a folder once, even when two entries contain it
home="$work/tt"; data_home "$home"; PK_ONLY=clean.orphan_agents,clean.orphan_data pk "$home" '' ''
o=$(tr -d '\r' <"$home.out")
ht=$(printf '%s\n' "$o" | sed -n 's/.*Leftovers of deleted apps — found [0-9]*, total \(.*\)$/\1/p')
dz=$(printf '%s\n' "$o" | grep 'data of a deleted app' | awk '{print $3, $4}')
pm=$(printf '%s\n' "$o" | sed -n 's/.*More with a higher level or by picking: ~\(.*\)$/\1/p')
[ -n "$dz" ] && [ "$ht" = "$dz" ] && [ "$pm" = "$dz" ] && pass "totals: a folder inside two entries is counted once" || fail "totals: heading '$ht', more '$pm', data entry '$dz'"

# --- a folder named like the deleted app but holding an installed app's files stays
home="$work/hd"; data_home "$home"; app "$home/Apps/Writer.app" com.example.writer
echo s >"$home/Library/Application Support/Comet/Default/com.example.writer.state"
mkdir -p "$home/Library/Perplexity/Writer"
lo "$home" check --only clean.orphan_data --no-color </dev/null >/dev/null 2>&1; r=$(ls "$home"/Library/Logs/macup/*.md | tail -1)
! grep -q 'Application Support/Comet`' "$r" && ! grep -q '~/Library/Perplexity`' "$r" && grep -q 'Preferences/ai.perplexity.comet.plist' "$r" \
  && pass "data: a folder that holds an installed app's files stays" || { fail "data: shared folder offered"; sed -n '/What can be cleaned/,$p' "$r" | head -20; }

# --- deferred minors
home="$work/mh"; leftovers_home "$home"; mkdir -p "$home/SysLib/PrivilegedHelperTools"; echo bin >"$home/SysLib/PrivilegedHelperTools/com.gone.thing"
pk "$home" '' ''; ng=$(nm "$home.out" 'Gone ·'); leftovers_home "$home"; mkdir -p "$home/SysLib/PrivilegedHelperTools"; echo bin >"$home/SysLib/PrivilegedHelperTools/com.gone.thing"
pk "$home" "$ng" y
[ -f "$home/.Trash/com.gone.thing.plist" ] && [ -f "$home/SysLib/PrivilegedHelperTools/com.gone.thing" ] && [ ! -e "$home/sudo.log" ] && pass "minor: a user agent never takes a system helper" || { fail "minor: user agent took a helper"; ls "$home/.Trash"; }
home="$work/mr"; leftovers_home "$home"; chmod 000 "$home/Library/LaunchAgents/com.me.script.plist"
lo "$home" check --only check.startup --no-color </dev/null >"$home.out" 2>&1; chmod 644 "$home/Library/LaunchAgents/com.me.script.plist"
! grep -q 'com.me.script.plist cannot be read (not a valid plist)' "$home.out" && grep -q 'broken.plist cannot be read' "$home.out" && pass "minor: a plist we may not read is not called invalid" || fail "minor: unreadable plist called invalid"
home="$work/mp"; leftovers_home "$home"; prog "$home/Library/Application Support/FooTool/x/y" 1; agent "$home/Library/LaunchAgents/io.github.foo.agent.plist" io.github.foo.agent "$home/Library/Application Support/FooTool/x/y"
empty_plist "$home/Library/Preferences/io.github.foo.plist"; empty_plist "$home/Library/Preferences/io.github.bar.plist"
lo "$home" check --only clean.orphan_data --no-color </dev/null >/dev/null 2>&1; r=$(ls "$home"/Library/Logs/macup/*.md | tail -1)
grep -q 'io.github.foo.plist' "$r" && ! grep -q 'io.github.bar.plist' "$r" && pass "minor: a shared hosting prefix (io.github) is not one vendor" || { fail "minor: io.github swept"; grep -n 'io.github' "$r"; }

# --- second review
home="$work/ob"; data_home "$home"; PK_ONLY=clean.orphan_data pk "$home" '' ''; nd=$(nm "$home.out" 'data of a deleted app')
data_home "$home"; FAKE_LSOF_PAD=40000 FAKE_OPEN="$home/Library/Application Support/Comet/Default/History" PK_ONLY=clean.orphan_data pk "$home" "$nd" y
[ -d "$home/Library/Application Support/Comet" ] && pass "review2: an open file is seen in a real-sized lsof listing" || fail "review2: open file missed in a big lsof listing"
home="$work/hu"; data_home "$home"; app "$home/Apps/Writer.app" com.example.writer; echo s >"$home/Library/Application Support/Comet/com.example.writer.state"
mkdir -p "$home/Library/Application Support/Comet/Locked"; chmod 000 "$home/Library/Application Support/Comet/Locked"
lo "$home" check --only clean.orphan_data --no-color </dev/null >/dev/null 2>&1; chmod 755 "$home/Library/Application Support/Comet/Locked"; r=$(ls "$home"/Library/Logs/macup/*.md | tail -1)
! grep -q 'Application Support/Comet`' "$r" && pass "review2: an unreadable subfolder does not hide an installed app's files" || fail "review2: held failed open on an unreadable subfolder"
home="$work/ws"; data_home "$home"; empty_plist "$home/Library/Preferences/ai.perplexity.my app.plist"; mkdir -p "$home/Library/Application Support/My"; echo x >"$home/Library/Application Support/My/x"
lo "$home" check --only clean.orphan_data --no-color </dev/null >/dev/null 2>&1; r=$(ls "$home"/Library/Logs/macup/*.md | tail -1)
! grep -q 'Application Support/My`' "$r" && grep -q 'ai.perplexity.my app.plist' "$r" && pass "review2: an id with a space is one id" || fail "review2: id split on a space"
home="$work/gn"; leftovers_home "$home"; prog "$home/Library/Application Support/FooTool/x/y" 1; agent "$home/Library/LaunchAgents/io.github.foo.agent.plist" io.github.foo.agent "$home/Library/Application Support/FooTool/x/y"
lo "$home" check --only check.startup --no-color </dev/null >"$home.out" 2>&1
grep -q 'Foo · io.github.foo.agent' "$home.out" && pass "review2: a three-part vendor is named by its owner" || { fail "review2: vendor name"; grep 'io.github' "$home.out"; }

# --- macOS keeps a container folder itself: its contents go, the rest of the pick too
home="$work/cn"; data_home "$home"; PK_ONLY=clean.orphan_data pk "$home" '' ''; nd=$(nm "$home.out" 'data of a deleted app')
data_home "$home"; chmod 555 "$home/Library/Containers"
PK_ONLY=clean.orphan_data pk "$home" "$nd" y; chmod 755 "$home/Library/Containers"
[ -f "$home/.Trash/ai.perplexity.mac.Notif/x" ] && [ -d "$home/Library/Containers/ai.perplexity.mac.Notif" ] && [ -d "$home/.Trash/Comet" ] && [ -d "$home/.Trash/group.ai.perplexity.app" ] \
  && pass "containers: a folder macOS keeps is emptied into the Trash, the rest still moves" || { fail "containers: refused folder"; ls "$home/.Trash"; tr -d '\r' <"$home.out" | sed -n '/Cleanup/,$p' | head -5; }

# --- a dev build's container belongs to clean.dev_containers, never offered twice
home="$work/dv"; data_home "$home"; printf 'language = en\ndev_container_prefixes = ai.perplexity.mac\n' >"$home/.config/macup/config"
PK_ONLY=clean.orphan_data pk "$home" '' ''; r=$(ls "$home"/Library/Logs/macup/*.md | tail -1)
grep -q 'Group Containers/group.ai.perplexity.app' "$r" && ! grep -q 'Containers/ai.perplexity.mac.Notif' "$r" && pass "dev containers: a dev build's container is not also app data" || { fail "dev containers: offered twice"; grep -n Containers "$r"; }

# --- plutil on macOS 15 prints "Could not extract value" to stdout for a missing key: never read as a value
mkdir -p "$work/bin15"; cat >"$work/bin15/plutil" <<'FAKE'
#!/bin/bash
if [ "$1" = -extract ]; then
  out=$(/usr/bin/plutil "$@" 2>&1) && { printf '%s' "$out"; exit 0; }
  echo "${!#}: Could not extract value, error: No value at that key path or invalid key path: $2"; exit 1
fi
exec /usr/bin/plutil "$@"
FAKE
chmod +x "$work/bin15/plutil"
home="$work/p15"; leftovers_home "$home"; PATH="$work/bin15:$PATH" lo "$home" check --only check.startup --no-color </dev/null >"$home.out" 2>&1
sec=$(sed -n '/Leftovers of deleted apps/,$p' "$home.out")
printf '%s\n' "$sec" | grep -q 'ai.perplexity.CometUpdater.wake — app is not installed' && ! printf '%s\n' "$sec" | grep -qE 'Could not extract|steamclean|homebrew.mxcl.redis|com.me.script' \
  && pass "macOS 15 plutil: a missing key is not a value" || { fail "macOS 15 plutil"; printf '%s\n' "$sec" | head -12; }

# --- a range (1-30) never takes leftovers: data and agents go only by their own number
home="$work/rg"; data_home "$home"; PK_ONLY=clean.orphan_agents,clean.orphan_data pk "$home" '1-30' y
[ -f "$home/Library/LaunchAgents/ai.perplexity.CometUpdater.wake.plist" ] && [ -d "$home/Library/Application Support/Comet" ] && pass "range: leftovers are never picked by a range" || { fail "range: leftovers taken by 1-30"; ls "$home/.Trash"; }

[ $F = 0 ] || exit 1

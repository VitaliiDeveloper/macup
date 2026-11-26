# shellcheck shell=bash
# tests/diff.sh, leftovers unit: a fake codesign and the fake homes, apps (MACUP_APPS) and /Library (MACUP_SYSLIB).
#   leftovers_fakes DIR   writes the fake codesign into DIR: it answers from $HOME/.fake/sign, lines "path-prefix|TEAM|Name",
#                         anything else is unsigned; every path it is asked about goes into $HOME/codesign.log
leftovers_fakes(){
  mkdir -p "$1"; cat >"$1/codesign" <<'FAKE'
#!/bin/bash
path="${!#}"; echo "$path" >>"$HOME/codesign.log"
while IFS='|' read -r prefix team name; do
  [ -n "$prefix" ] || continue
  case "$path" in "$prefix"*) echo "Authority=Developer ID Application: $name ($team)" >&2; echo "TeamIdentifier=$team" >&2; exit 0 ;; esac
done <"$HOME/.fake/sign"
echo "$path: code object is not signed at all" >&2; exit 1
FAKE
  chmod +x "$1/codesign"
}

lo_app(){ # app bundle-id
  mkdir -p "$1/Contents/MacOS"
  printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>%s</string></dict></plist>\n' "$2" >"$1/Contents/Info.plist"
}
lo_agent(){ # plist label program [associated id] [seconds]
  local assoc=""; [ -n "$4" ] && assoc="<key>AssociatedBundleIdentifiers</key><array><string>$4</string></array>"
  mkdir -p "$(dirname "$1")"
  printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict><key>Label</key><string>%s</string><key>ProgramArguments</key><array><string>%s</string></array><key>StartInterval</key><integer>%s</integer>%s</dict></plist>\n' "$2" "$3" "${5:-3600}" "$assoc" >"$1"
}
lo_empty(){ mkdir -p "$(dirname "$1")"; printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0">\n<dict/>\n</plist>\n' >"$1"; }
lo_prog(){ mkdir -p "$(dirname "$1")"; dd if=/dev/zero of="$1" bs=1024 count="${2:-2048}" 2>/dev/null; chmod +x "$1"; }

# Apps in ~/Apps and ~/Applications; an updater of an app that is gone (with its own folder), an empty startup file, a program
# that was deleted, a broken plist, agents whose app is there (by vendor, by team), Homebrew's and a script's agents (never
# judged), a system daemon whose program is gone (with a helper), one whose vendor alone owns nothing, and the data they left
fix_lo(){ local home=$1 library="$1/Library" support="$1/Library/Application Support" agents="$1/Library/LaunchAgents" sys="$1/SysLib"
  mkdir -p "$home/.fake" "$home/.Trash"
  printf '%s\n' "$support/Perplexity|7S8W4W365S|Perplexity AI Inc." "$support/iStat Helper|NF7JU763MN|ImageTasks Inc" \
    "$home/Applications/iStat.app|NF7JU763MN|ImageTasks Inc" "$sys/Application Support/Teamed|TEAMED1234|Teamed, LLC" >"$home/.fake/sign"
  lo_app "$home/Apps/Steam.app" com.valvesoftware.steam; lo_app "$home/Applications/iStat.app" imagetasks.iStatistica
  lo_app "$home/Apps/Vendor Folder/Tool.app" com.tool.app
  lo_prog "$support/Perplexity/CometUpdater/Current/CometUpdater.app/Contents/MacOS/CometUpdater"
  lo_agent "$agents/ai.perplexity.CometUpdater.wake.plist" ai.perplexity.CometUpdater.wake "$support/Perplexity/CometUpdater/Current/CometUpdater.app/Contents/MacOS/CometUpdater" ai.perplexity.CometUpdater
  lo_empty "$agents/ai.perplexity.keystone.agent.plist"
  lo_prog "$support/Steam/SteamApps/steamclean"; lo_agent "$agents/com.valvesoftware.steamclean.plist" com.valvesoftware.steamclean "$support/Steam/SteamApps/steamclean"
  lo_prog "$support/iStat Helper/helper"; lo_agent "$agents/com.imagetasks.helper.plist" com.imagetasks.helper "$support/iStat Helper/helper"
  lo_prog "$support/Tool/bin/tool"; lo_agent "$agents/com.tool.agent.plist" com.tool.agent "$support/Tool/bin/tool"
  lo_prog "$home/opt/redis-server" 1; lo_agent "$agents/homebrew.mxcl.redis.plist" homebrew.mxcl.redis "$home/opt/redis-server"
  lo_prog "$library/pnpm/run.sh" 1; lo_agent "$agents/com.me.script.plist" com.me.script "$library/pnpm/run.sh"
  lo_agent "$agents/com.gone.thing.plist" com.gone.thing /Applications/Gone.app/Contents/MacOS/Gone 86400
  lo_prog "$support/FooTool/x/y" 1; lo_agent "$agents/io.github.foo.agent.plist" io.github.foo.agent "$support/FooTool/x/y" "" 60
  lo_prog "$support/MyScripts/bin/run" 1; lo_agent "$agents/mybackup.plist" mybackup "$support/MyScripts/bin/run"
  echo 'not a plist' >"$agents/broken.plist"; lo_empty "$agents/com.apple.ignored.plist"; ln -s "$agents/com.tool.agent.plist" "$agents/com.linked.plist"
  lo_agent "$sys/LaunchDaemons/com.gone.daemon.plist" com.gone.daemon "$sys/Gone/missing"
  mkdir -p "$sys/PrivilegedHelperTools"; echo bin >"$sys/PrivilegedHelperTools/com.gone.daemon"
  lo_prog "$sys/Application Support/Prefix/bin/p" 1; lo_agent "$sys/LaunchDaemons/com.prefix.only.plist" com.prefix.only "$sys/Application Support/Prefix/bin/p"
  lo_prog "$sys/Application Support/Teamed/svc/bin/s" 1; lo_agent "$sys/LaunchAgents/com.teamed.svc.plist" com.teamed.svc "$sys/Application Support/Teamed/svc/bin/s"
  mkdir -p "$library/HTTPStorages/ai.perplexity.CometUpdater" "$support/Comet/Default" "$library/Perplexity" "$library/Containers/ai.perplexity.mac.Notif" \
    "$library/Group Containers/group.ai.perplexity.app" "$library/Group Containers/7S8W4W365S.shared" "$library/Saved Application State/ai.perplexity.comet.savedstate" \
    "$support/Downloader" "$support/Teamed" "$library/Containers/com.teamed.dev.App"
  for file in ai.perplexity.comet ai.perplexity.downloader com.segment.analytics io.github.foo io.github.bar com.teamed.svc; do lo_empty "$library/Preferences/$file.plist"; done
  echo h >"$support/Comet/Default/History"; lo_prog "$support/Comet/Default/Cache" 4096; echo x >"$library/Perplexity/x"
  echo x >"$library/Containers/ai.perplexity.mac.Notif/x"; echo x >"$library/Group Containers/group.ai.perplexity.app/x"; echo x >"$library/Group Containers/7S8W4W365S.shared/x"
  echo mine >"$support/Downloader/x"; lo_app "$home/Apps/Downloader.app" local.vitalii.downloader; lo_prog "$support/Teamed/data" 64
  echo x >"$library/Containers/com.teamed.dev.App/x"; mkdir -p "$home/.config/macup"; printf 'dev_container_prefixes = com.teamed.dev\n' >"$home/.config/macup/config"
}
# the same Mac after Comet was installed again: its updater, its data and its folders are the app's again
fix_loapp(){ fix_lo "$1"; lo_app "$1/Applications/Comet.app" ai.perplexity.comet; }
# a folder named like the deleted app that holds an installed app's files stays
fix_loheld(){ fix_lo "$1"; lo_app "$1/Apps/Writer.app" com.example.writer; echo s >"$1/Library/Application Support/Comet/com.example.writer.state"; }

#!/bin/bash
# Makes the README screenshots (docs/images/*.svg) from the real macup in this checkout, run against a made-up Mac:
# a fake home with caches and an app's leftovers, fake sizes and free space, no running apps. Nothing of this Mac
# shows up, and nothing outside a temp folder is touched: MACUP_PATH=keep keeps the real Homebrew off PATH, and only
# cleaners that work on files alone are run (no brew, npm, pip, docker, xcrun), each named below.
#   tools/screenshots.sh            rebuild the binary, then write docs/images/check.svg, summary.svg, menu.svg
set -eo pipefail
cd "$(dirname "$0")/.."
./build.sh >/dev/null
MACUP="$(swift build --show-bin-path)/macup"
OUT=docs/images; mkdir -p "$OUT"
W=$(mktemp -d "${TMPDIR:-/tmp}/macup-shots.XXXXXX"); trap 'chflags -R nouchg "$W" 2>/dev/null; rm -rf "$W"' EXIT
H="$W/home"; L="$H/Library"; AS="$L/Application Support"; B="$W/bin"; mkdir -p "$B"

# --- the made-up Mac
blob(){ mkdir -p "$1"; echo x >"$1/blob"; }
app(){ mkdir -p "$1/Contents"; printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>%s</string></dict></plist>\n' "$2" >"$1/Contents/Info.plist"; }
agent(){ mkdir -p "$(dirname "$1")"; printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict><key>Label</key><string>%s</string><key>ProgramArguments</key><array><string>%s</string></array><key>StartInterval</key><integer>3600</integer></dict></plist>\n' "$2" "$3" >"$1"; }
mkdir -p "$H/.config/macup" "$H/.Trash"; printf 'language = en\n' >"$H/.config/macup/config"
blob "$L/Developer/Xcode/DerivedData/Shop-abc"; blob "$L/Developer/Xcode/UserData/Previews/x"
blob "$L/Developer/CoreSimulator/Caches/dyld"; blob "$L/Caches/org.swift.swiftpm/repos"; blob "$L/Caches/CocoaPods/Pods"
for a in Code Slack Claude; do blob "$AS/$a/Cache/Cache_Data"; blob "$AS/$a/Code Cache/js"; blob "$AS/$a/GPUCache"; mkdir -p "$AS/$a/User"; done
blob "$L/Caches/Google/Chrome/Default/Cache"
blob "$H/.gradle/caches/modules-2"; blob "$H/.m2/repository/org"
blob "$H/.Trash/old-project"
app "$H/Apps/Slack.app" com.tinyspeck.slackmacgap
mkdir -p "$L/LaunchAgents"
P="$AS/Perplexity/CometUpdater/Current/CometUpdater.app/Contents/MacOS/CometUpdater"; mkdir -p "$(dirname "$P")"; echo x >"$P"; chmod +x "$P"
agent "$L/LaunchAgents/ai.perplexity.CometUpdater.wake.plist" ai.perplexity.CometUpdater.wake "$P"
printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0">\n<dict/>\n</plist>\n' >"$L/LaunchAgents/ai.perplexity.keystone.agent.plist"
mkdir -p "$L/Preferences" "$AS/Comet/Default"; echo h >"$AS/Comet/Default/History"
printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0">\n<dict/>\n</plist>\n' >"$L/Preferences/ai.perplexity.comet.plist"

# --- sizes as on a Mac in use (KB); du answers from this table, anything else is measured
cat >"$W/sizes" <<EOF
$L/Developer/Xcode/DerivedData	14852000
$L/Developer/Xcode/UserData/Previews	1210000
$L/Developer/CoreSimulator/Caches	2304000
$L/Caches/org.swift.swiftpm	1870000
$L/Caches/CocoaPods	846000
$AS/Code/Cache	402000
$AS/Code/Code Cache	131000
$AS/Code/GPUCache	22000
$AS/Slack/Cache	1120000
$AS/Slack/Code Cache	214000
$AS/Slack/GPUCache	18000
$AS/Claude/Cache	356000
$AS/Claude/Code Cache	96000
$AS/Claude/GPUCache	12000
$L/Caches/Google/Chrome/Default/Cache	1630000
$H/.gradle/caches	3410000
$H/.m2/repository	1240000
$H/.Trash	2210000
$AS/Perplexity/CometUpdater	340000
$AS/Perplexity	340000
$AS/Comet	403000
EOF
cat >"$B/du" <<EOF
#!/bin/bash
# a listed folder has its listed size until it is emptied; -d 1 lists each child the same way
last=\${!#}; last=\${last%/}
size(){ local s; [ -d "\$1" ] && [ -z "\$(ls -A "\$1" 2>/dev/null)" ] && { echo 0; return; }
  s=\$(awk -F'\t' -v p="\$1" '\$1 == p {print \$2; exit}' "$W/sizes"); [ -n "\$s" ] && echo "\$s" || /usr/bin/du -sk "\$1" 2>/dev/null | awk '{print \$1}'; }
case " \$* " in
  *" -d 1 "*) for c in "\$last"/* "\$last"/.[!.]*; do [ -e "\$c" ] && printf '%s\t%s\n' "\$(size "\$c")" "\$c"; done; printf '%s\t%s\n' "\$(size "\$last")" "\$last" ;;
  *) printf '%s\t%s\n' "\$(size "\$last")" "\$last" ;;
esac
EOF
cat >"$B/df" <<'EOF'
#!/bin/bash
printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\n/dev/disk3s5 482797652 300297652 182500000 63%% /System/Volumes/Data\n'
EOF
# no app is running, nothing is open, nothing is loaded; the updater is signed by a team no installed app has
printf '#!/bin/bash\nexit 1\n' >"$B/pgrep"
printf '#!/bin/bash\nprintf "p1\\ncsh\\nn/\\n"\n' >"$B/lsof"
printf '#!/bin/bash\nexit 0\n' >"$B/sfltool"; printf '#!/bin/bash\nexit 0\n' >"$B/osascript"
# system tools that would read this Mac (simulators, Spotlight, pip's own cache) answer nothing
for t in xcrun pip3 mdfind qlmanage tmutil; do printf '#!/bin/bash\nexit 1\n' >"$B/$t"; done
printf '#!/bin/bash\n[ "$1" = print ] && exit 113\nexit 0\n' >"$B/launchctl"
cat >"$B/codesign" <<EOF
#!/bin/bash
case "\${!#}" in "$AS/Perplexity/"*) echo "Authority=Developer ID Application: Perplexity AI Inc. (7S8W4W365S)" >&2; echo "TeamIdentifier=7S8W4W365S" >&2; exit 0 ;; esac
exit 1
EOF
chmod +x "$B"/*

waitfor(){ local i=0; while [ $i -lt 240 ]; do grep -qF "$2" "$1" 2>/dev/null && return; sleep 0.5; i=$((i + 1)); done; }
run(){ # file prompt input macup-args… — macup in a terminal; the input is typed once the prompt shows (no prompt: none)
  local f=$1 pr=$2 in=$3; shift 3; : >"$f"
  ( [ -n "$pr" ] && { waitfor "$f" "$pr"; printf '%s' "$in"; }; waitfor "$f" "${DONE:-Report: }"; sleep 1 ) | script -q /dev/null env -i MACUP_PATH=keep HOME="$H" PATH="$B:/usr/bin:/bin:/usr/sbin:/sbin" TERM=xterm-256color LANG=en_US.UTF-8 \
    MACUP_APPS="$H/Apps" MACUP_SYSLIB="$W/SysLib" "$MACUP" "$@" >"$f" 2>&1 || true
  # the clock: a fixed report name and run time
  sed -i '' -E 's/macup_[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9-]{8}/macup_2026-11-21_09-41-07/g; s/· [0-9]+m [0-9]+s/· 0m 38s/g' "$f"
}
[ -n "$SHOTS_RAW" ] && trap 'cp "$W"/*.txt "$SHOTS_RAW"/ 2>/dev/null; chflags -R nouchg "$W" 2>/dev/null; rm -rf "$W"' EXIT
FILES='clean.derived_data,clean.xcode_previews,clean.sim_caches,clean.spm,clean.cocoapods,clean.gradle,clean.maven,clean.editors,clean.browsers'
run "$W/check.txt" 'Clean now?' $'\n' check --only "check.startup,$FILES,clean.trash,clean.orphan_agents,clean.orphan_data"
python3 tools/screenshots/ansi2svg.py "macup check" "macup check" "$W/check.txt" "$OUT/check.svg" --until 'Clean now?' --cursor
run "$W/clean.txt" '' '' clean --level standard --only "$FILES"
python3 tools/screenshots/ansi2svg.py "macup clean" "macup clean --level standard" "$W/clean.txt" "$OUT/summary.svg"
DONE='Choose [1]' run "$W/menu.txt" 'Choose [1]' $'q\n'
sed -i '' -E 's/(Choose \[1\]: )q/\1/' "$W/menu.txt"   # the answer typed to close it
python3 tools/screenshots/ansi2svg.py "macup" "macup" "$W/menu.txt" "$OUT/menu.svg" --until 'Choose [1]' --cursor
ls -l "$OUT"/*.svg

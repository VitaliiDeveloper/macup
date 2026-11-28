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
WORK=$(mktemp -d "${TMPDIR:-/tmp}/macup-shots.XXXXXX"); trap 'chflags -R nouchg "$WORK" 2>/dev/null; rm -rf "$WORK"' EXIT
FAKE_HOME="$WORK/home"; LIBRARY="$FAKE_HOME/Library"; AS="$LIBRARY/Application Support"; FAKE_BIN="$WORK/bin"; mkdir -p "$FAKE_BIN"

# --- the made-up Mac
blob(){ mkdir -p "$1"; echo x >"$1/blob"; }
app(){ mkdir -p "$1/Contents"; printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>%s</string></dict></plist>\n' "$2" >"$1/Contents/Info.plist"; }
agent(){ mkdir -p "$(dirname "$1")"; printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict><key>Label</key><string>%s</string><key>ProgramArguments</key><array><string>%s</string></array><key>StartInterval</key><integer>3600</integer></dict></plist>\n' "$2" "$3" >"$1"; }
mkdir -p "$FAKE_HOME/.config/macup" "$FAKE_HOME/.Trash"; printf 'language = en\n' >"$FAKE_HOME/.config/macup/config"
blob "$LIBRARY/Developer/Xcode/DerivedData/Shop-abc"; blob "$LIBRARY/Developer/Xcode/UserData/Previews/x"
blob "$LIBRARY/Developer/CoreSimulator/Caches/dyld"; blob "$LIBRARY/Caches/org.swift.swiftpm/repos"; blob "$LIBRARY/Caches/CocoaPods/Pods"
for editor in Code Slack Claude; do blob "$AS/$editor/Cache/Cache_Data"; blob "$AS/$editor/Code Cache/js"; blob "$AS/$editor/GPUCache"; mkdir -p "$AS/$editor/User"; done
blob "$LIBRARY/Caches/Google/Chrome/Default/Cache"
blob "$FAKE_HOME/.gradle/caches/modules-2"; blob "$FAKE_HOME/.m2/repository/org"
blob "$FAKE_HOME/.Trash/old-project"
app "$FAKE_HOME/Apps/Slack.app" com.tinyspeck.slackmacgap
mkdir -p "$LIBRARY/LaunchAgents"
P="$AS/Perplexity/CometUpdater/Current/CometUpdater.app/Contents/MacOS/CometUpdater"; mkdir -p "$(dirname "$P")"; echo x >"$P"; chmod +x "$P"
agent "$LIBRARY/LaunchAgents/ai.perplexity.CometUpdater.wake.plist" ai.perplexity.CometUpdater.wake "$P"
printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0">\n<dict/>\n</plist>\n' >"$LIBRARY/LaunchAgents/ai.perplexity.keystone.agent.plist"
mkdir -p "$LIBRARY/Preferences" "$AS/Comet/Default"; echo h >"$AS/Comet/Default/History"
printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0">\n<dict/>\n</plist>\n' >"$LIBRARY/Preferences/ai.perplexity.comet.plist"

# --- sizes as on a Mac in use (KB); du answers from this table, anything else is measured
cat >"$WORK/sizes" <<EOF
$LIBRARY/Developer/Xcode/DerivedData	14852000
$LIBRARY/Developer/Xcode/UserData/Previews	1210000
$LIBRARY/Developer/CoreSimulator/Caches	2304000
$LIBRARY/Caches/org.swift.swiftpm	1870000
$LIBRARY/Caches/CocoaPods	846000
$AS/Code/Cache	402000
$AS/Code/Code Cache	131000
$AS/Code/GPUCache	22000
$AS/Slack/Cache	1120000
$AS/Slack/Code Cache	214000
$AS/Slack/GPUCache	18000
$AS/Claude/Cache	356000
$AS/Claude/Code Cache	96000
$AS/Claude/GPUCache	12000
$LIBRARY/Caches/Google/Chrome/Default/Cache	1630000
$FAKE_HOME/.gradle/caches	3410000
$FAKE_HOME/.m2/repository	1240000
$FAKE_HOME/.Trash	2210000
$AS/Perplexity/CometUpdater	340000
$AS/Perplexity	340000
$AS/Comet	403000
EOF
cat >"$FAKE_BIN/du" <<EOF
#!/bin/bash
# a listed folder has its listed size until it is emptied; -d 1 lists each child the same way
last=\${!#}; last=\${last%/}
size(){ local listed; [ -d "\$1" ] && [ -z "\$(ls -A "\$1" 2>/dev/null)" ] && { echo 0; return; }
  listed=\$(awk -F'\t' -v path="\$1" '\$1 == path {print \$2; exit}' "$WORK/sizes"); [ -n "\$listed" ] && echo "\$listed" || /usr/bin/du -sk "\$1" 2>/dev/null | awk '{print \$1}'; }
case " \$* " in
  *" -d 1 "*) for child in "\$last"/* "\$last"/.[!.]*; do [ -e "\$child" ] && printf '%s\t%s\n' "\$(size "\$child")" "\$child"; done; printf '%s\t%s\n' "\$(size "\$last")" "\$last" ;;
  *) printf '%s\t%s\n' "\$(size "\$last")" "\$last" ;;
esac
EOF
cat >"$FAKE_BIN/df" <<'EOF'
#!/bin/bash
printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\n/dev/disk3s5 482797652 300297652 182500000 63%% /System/Volumes/Data\n'
EOF
# no app is running, nothing is open, nothing is loaded; the updater is signed by a team no installed app has
printf '#!/bin/bash\nexit 1\n' >"$FAKE_BIN/pgrep"
printf '#!/bin/bash\nprintf "p1\\ncsh\\nn/\\n"\n' >"$FAKE_BIN/lsof"
printf '#!/bin/bash\nexit 0\n' >"$FAKE_BIN/sfltool"; printf '#!/bin/bash\nexit 0\n' >"$FAKE_BIN/osascript"
# system tools that would read this Mac (simulators, Spotlight, pip's own cache) answer nothing
for tool in xcrun pip3 mdfind qlmanage tmutil; do printf '#!/bin/bash\nexit 1\n' >"$FAKE_BIN/$tool"; done
printf '#!/bin/bash\n[ "$1" = print ] && exit 113\nexit 0\n' >"$FAKE_BIN/launchctl"
cat >"$FAKE_BIN/codesign" <<EOF
#!/bin/bash
case "\${!#}" in "$AS/Perplexity/"*) echo "Authority=Developer ID Application: Perplexity AI Inc. (7S8W4W365S)" >&2; echo "TeamIdentifier=7S8W4W365S" >&2; exit 0 ;; esac
exit 1
EOF
chmod +x "$FAKE_BIN"/*

waitfor(){ local tries=0; while [ $tries -lt 240 ]; do grep -qF "$2" "$1" 2>/dev/null && return; sleep 0.5; tries=$((tries + 1)); done; }
run(){ # file prompt input macup-args… — macup in a terminal; the input is typed once the prompt shows (no prompt: none)
  local out=$1 prompt=$2 input=$3; shift 3; : >"$out"
  ( [ -n "$prompt" ] && { waitfor "$out" "$prompt"; printf '%s' "$input"; }; waitfor "$out" "${DONE:-Report: }"; sleep 1 ) | script -q /dev/null env -i MACUP_PATH=keep HOME="$FAKE_HOME" PATH="$FAKE_BIN:/usr/bin:/bin:/usr/sbin:/sbin" TERM=xterm-256color LANG=en_US.UTF-8 \
    MACUP_APPS="$FAKE_HOME/Apps" MACUP_SYSLIB="$WORK/SysLib" "$MACUP" "$@" >"$out" 2>&1 || true
  # the clock: a fixed report name and run time
  sed -i '' -E 's/macup_[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9-]{8}/macup_2026-11-21_09-41-07/g; s/· [0-9]+m [0-9]+s/· 0m 38s/g' "$out"
}
[ -n "$SHOTS_RAW" ] && trap 'cp "$WORK"/*.txt "$SHOTS_RAW"/ 2>/dev/null; chflags -R nouchg "$WORK" 2>/dev/null; rm -rf "$WORK"' EXIT
FILES='clean.derived_data,clean.xcode_previews,clean.sim_caches,clean.spm,clean.cocoapods,clean.gradle,clean.maven,clean.editors,clean.browsers'
run "$WORK/check.txt" 'Clean now?' $'\n' check --only "check.startup,$FILES,clean.trash,clean.orphan_agents,clean.orphan_data"
python3 tools/screenshots/ansi2svg.py "macup check" "macup check" "$WORK/check.txt" "$OUT/check.svg" --until 'Clean now?' --cursor
run "$WORK/clean.txt" '' '' clean --level standard --only "$FILES"
python3 tools/screenshots/ansi2svg.py "macup clean" "macup clean --level standard" "$WORK/clean.txt" "$OUT/summary.svg"
DONE='Choose [1]' run "$WORK/menu.txt" 'Choose [1]' $'q\n'
sed -i '' -E 's/(Choose \[1\]: )q/\1/' "$WORK/menu.txt"   # the answer typed to close it
python3 tools/screenshots/ansi2svg.py "macup" "macup" "$WORK/menu.txt" "$OUT/menu.svg" --until 'Choose [1]' --cursor
ls -l "$OUT"/*.svg

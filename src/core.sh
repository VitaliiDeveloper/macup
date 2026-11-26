#!/bin/bash
# shellcheck disable=SC2088,SC2034,SC2059
# macup — keep a Mac healthy: update tools, clean safe caches, check the system, track trends.
# https://github.com/VitaliiDeveloper/macup · MIT License
#
# Compatible with the stock macOS bash 3.2. No sudo required.
# Languages: English (en), Українська (uk), Русский (ru) — `macup lang`.

MACUP_VERSION="2.9.2"
MACUP_REPO="${MACUP_REPO:-VitaliiDeveloper/macup}"
MACUP_RAW="https://raw.githubusercontent.com/$MACUP_REPO"   # + /<branch or tag>/<file>
set -o pipefail
# every path below hangs off $HOME: with none, "$HOME/Library/Caches" would be the system's /Library/Caches
case "${HOME:-}" in /?*) ;; *) echo "macup: HOME is not set" >&2; exit 1 ;; esac

case "${LC_ALL:-${LC_CTYPE:-$LANG}}" in *UTF-8*|*utf-8*|*UTF8*|*utf8*) ;; *) { export LC_CTYPE=en_US.UTF-8; } 2>/dev/null ;; esac

# ---------------------------------------------------------------- paths
CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/macup"
CONF="$CONF_DIR/config"
STATE_DIR="$HOME/Library/Application Support/macup"
CACHE_DIR="$HOME/Library/Caches/macup"
HISTORY="$STATE_DIR/history.csv"
LOGDIR="$HOME/Library/Logs/macup"
DEV="$HOME/Library/Developer"
SCHED_LABEL="com.vitaliideveloper.macup"
SCHED_PLIST="$HOME/Library/LaunchAgents/$SCHED_LABEL.plist"
USER_PATH=$PATH   # as the terminal has it: check.commands reports its folders that do not exist
# MACUP_PATH=keep: PATH stays as given, for tests that put fakes first (brew, npm…) and must never reach the real ones
[ "${MACUP_PATH:-}" = keep ] || export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:$HOME/.local/bin:$HOME/.npm-global/bin:$HOME/.cargo/bin:$PATH"
# Without the Command Line Tools, /usr/bin/python3, swift, xcrun, git are stubs that pop up an install dialog
CLT_OK=0; [ -d "$(xcode-select -p 2>/dev/null)" ] && CLT_OK=1

# ---------------------------------------------------------------- task registry
# id | default (on/off) | description          `macup tasks` prints this table.
TASKS='check.system|on|macOS version, model, uptime (warns after 14 days without restart)
check.disk|on|Free space, disk health (SMART), local Time Machine snapshots
check.memory|on|Memory pressure and swap usage
check.cpu|on|Load average, top CPU and memory processes, thermal throttling
check.battery|on|Charge, cycle count, maximum capacity, condition
check.security|on|FileVault, Firewall, SIP, Gatekeeper, automatic updates
check.time_machine|on|Time Machine: last backup date (part of check.security)
check.startup|on|Third-party launch agents/daemons, orphaned ones pointing at deleted apps
check.mcp|on|Claude Code MCP servers that fail to connect
check.brew_doctor|on|brew doctor warnings
check.macos_updates|on|Pending macOS updates (never installed automatically)
check.xcode|on|Xcode, command line tools, simulator runtimes
check.devtools|on|Versions of Swift, CocoaPods, Flutter, Node, Ruby, Python, Codex
check.commands|on|Commands that cannot start: a missing interpreter (node, python) or a broken link
check.docker|on|Docker disk usage (if Docker is running)
check.gh|on|GitHub CLI: a saved login that no longer works
check.certs|on|Code signing certificates that expire within 30 days
check.crashes|on|Apps that crashed several times in the last 7 days
check.sizes|on|Sizes of things macup never deletes: Archives, Trash, caches, pub-cache
check.creative|on|Render and preview caches of Final Cut, Premiere, DaVinci, Lightroom, Camera Raw (measured only)
check.trends|on|Compare with the previous run: free space, swap, battery capacity
check.self_update|on|Tell when a newer macup is on GitHub (once a week)
update.claude|on|Claude Code CLI, plugin marketplaces, plugins
update.npm|on|Global npm packages (Codex, Playwright, ...)
update.skills|on|Agent skills in ~/.agents (npx skills update -g)
update.brew|on|Homebrew formulae and casks
update.mas|on|App Store apps (needs mas)
update.pipx|on|pipx-installed tools
update.uv|on|uv-installed tools
update.rustup|on|Rust toolchains
update.omz|on|Oh My Zsh
update.gh_ext|on|GitHub CLI extensions
update.pnpm|on|Global pnpm packages
update.bun|on|Bun (bun upgrade; a Homebrew install is left to Homebrew)
update.deno|on|Deno (deno upgrade; a Homebrew install is left to Homebrew)
update.cargo|on|Programs installed with cargo install (needs cargo-update)
update.mise|on|Tools managed by mise
update.asdf|on|asdf plugins
update.editor_ext|on|VS Code, Cursor, Windsurf and VSCodium extensions
update.gcloud|on|Google Cloud SDK components (its own install; a Homebrew install is left to Homebrew)
update.dotnet|on|.NET global tools (needs .NET 9 or later)
update.composer|on|Composer global packages
update.gem|off|Ruby gems (opt-in; never the system Ruby)
update.grok|on|Grok CLI (grok update)
update.agy|on|Antigravity CLI (agy update)
update.apps|on|Apps outside Homebrew and the App Store that update themselves (only reported)
clean.derived_data|on|Xcode DerivedData (skipped while Xcode is open)
clean.xcode_previews|on|SwiftUI previews cache (skipped while Xcode is open)
clean.device_support|on|iOS/watchOS DeviceSupport folders older than device_support_days
clean.device_logs|on|iOS device logs older than 90 days
clean.sim_unavailable|on|Simulators whose runtime is gone
clean.sim_runtimes|off|Simulator runtimes you no longer need (only when you pick them; Xcode downloads them again)
clean.sim_erase|off|Erase the apps and data of a simulator (only when you pick it)
clean.sim_unused|off|Simulators unused for simulator_days (only when you pick them)
clean.sim_caches|on|CoreSimulator caches
clean.spm|on|SwiftPM cache
clean.cocoapods|on|CocoaPods cache
clean.carthage|on|Carthage cache
clean.brew|on|Old Homebrew versions and downloads
clean.npm|on|npm cache garbage (npm cache verify)
clean.yarn|on|Yarn cache
clean.pnpm|on|pnpm store: unreferenced packages
clean.pip|on|pip cache
clean.poetry|on|Poetry cache and downloads; its virtualenvs stay
clean.uv|on|uv cache: unused entries
clean.go|on|Go build cache
clean.go_mod|on|Go module cache (standard); go downloads the modules again
clean.bun|on|Bun install cache
clean.deno|on|Deno cache; localStorage and Deno KV data stay
clean.logs|on|Logs and crash reports older than 30 days, also npm and Gradle daemon logs
clean.quicklook|on|Quick Look thumbnail cache
clean.reports|on|Old macup reports (keep_reports_days, keep_reports), on every run; its history and leftover temp files are trimmed too
clean.gradle|on|Gradle caches and old Gradle wrappers (standard)
clean.android|on|Android and Android Studio caches (standard); SDK, emulators and keys stay
clean.maven|on|Maven repository ~/.m2/repository (standard); settings.xml stays
clean.cargo|on|Cargo registry and git downloads (standard, skipped while cargo runs)
clean.jetbrains|on|JetBrains IDE caches (standard, skipped while open)
clean.docker|on|Docker build cache and dangling images (standard); never volumes
clean.docker_images|off|Docker images no container uses (only when you pick them)
clean.docker_containers|off|Stopped Docker containers (only when you pick them)
clean.old_versions|on|Older patch versions in nvm, fnm, Volta, rbenv, pyenv, mise, asdf (standard); pinned ones stay
clean.playwright|on|Old Playwright, Puppeteer and Cypress builds (standard); the newest of each stays
clean.profiles|on|Expired provisioning profiles
clean.ai_tools|on|Leftovers of AI coding tools: Codex temporary files, backups and unfinished downloads, old Grok and Antigravity CLI versions, edit backups of deleted Claude Code sessions; chat history is never touched
clean.editor_workspaces|on|Data VS Code, Cursor and similar editors keep for a workspace whose folder is gone, AI chats included (only when you pick it, to the Trash)
clean.editors|on|Caches of Electron apps: VS Code, Cursor, Claude, Slack, Discord and any other found by its folder layout (skipped while open)
clean.browsers|on|Browser caches: Chrome, Arc, Edge, Brave, Firefox and any other Chromium or Firefox-based browser (aggressive, skipped while open)
clean.app_caches|off|Other big folders in ~/Library/Caches (aggressive, only when you pick them)
clean.stale_node_modules|off|node_modules in projects untouched for stale_project_days (opt-in)
clean.stale_artifacts|off|Build folders in projects untouched for stale_project_days: Pods, .build, .dart_tool, .next, target, build (opt-in)
clean.brew_autoremove|off|Homebrew packages installed only as dependencies that nothing needs any more (only when you pick them)
clean.trash|off|Empty the Trash (opt-in)
clean.orphan_agents|off|Background programs of deleted apps and their folders (only when you pick them)
clean.orphan_data|off|Data of deleted apps: settings, history, saved passwords (only when you pick them)
clean.dev_containers|off|Containers in ~/Library/Containers named by dev_container_prefixes whose app is gone (only when you pick them)'

# ---------------------------------------------------------------- config
conf(){ # key default
  local v=""
  [ -f "$CONF" ] && v=$(sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*//p" "$CONF" | sed 's/[[:space:]]*#.*$//; s/[[:space:]]*$//' | tail -1)
  echo "${v:-$2}"
}
conf_set(){ # key value — replace or append
  mkdir -p "$CONF_DIR"; [ -f "$CONF" ] || write_default_conf
  if grep -qE "^[[:space:]]*$1[[:space:]]*=" "$CONF"; then
    sed -i '' -E "s|^[[:space:]]*$1[[:space:]]*=.*|$1 = $2|" "$CONF" 2>/dev/null || sed -i -E "s|^[[:space:]]*$1[[:space:]]*=.*|$1 = $2|" "$CONF"
  else printf '%s = %s\n' "$1" "$2" >>"$CONF"; fi
}
CLI_SKIP=""; CLI_ONLY=""; CLI_ENABLE=""; PICK=""; LEVEL=""
level_num(){ case "$1" in safe|1) echo 1 ;; standard|2) echo 2 ;; aggressive|3) echo 3 ;; esac; }
num(){ case "$1" in ''|*[!0-9]*|0) echo "$2" ;; *) echo "$1" ;; esac; }   # positive integer or the default
load_conf(){
  SKIP=",$(conf skip "" | tr -d ' '),$(echo "$CLI_SKIP" | tr -d ' '),"
  ENABLE=",$(conf enable "" | tr -d ' '),$(echo "$CLI_ENABLE" | tr -d ' '),"
  CLI_ONLY=$(echo "$CLI_ONLY" | tr -d ' ')
  DS_DAYS=$(num "$(conf device_support_days 90)" 90)
  KEEP_DAYS=$(num "$(conf keep_reports_days 30)" 30)
  KEEP_RUNS=$(num "$(conf keep_reports 20)" 20)
  STALE_DAYS=$(num "$(conf stale_project_days 90)" 90)
  SIM_DAYS=$(num "$(conf simulator_days 30)" 30)
  STEP_SECS=$(( $(num "$(conf step_timeout_minutes 60)" 60) * 60 ))
  [ -n "${MACUP_STEP_SECS:-}" ] && STEP_SECS=$(num "$MACUP_STEP_SECS" "$STEP_SECS")   # seconds, for the tests
  [ -z "$LEVEL" ] && { LEVEL=$(level_num "$(conf clean_level safe)"); [ -z "$LEVEL" ] && LEVEL=1; }
  DEV_PREFIXES=$(conf dev_container_prefixes "")
  PROJECT_DIRS=$(conf project_dirs "~/Developer, ~/Projects, ~/Code, ~/dev, ~/src, ~/repos, ~/work")
}
task_default(){ printf '%s\n' "$TASKS" | awk -F'|' -v id="$1" '$1==id{print $2}'; }
task_allowed(){ # not skipped by config, --skip or --only
  local id=$1 grp=${1%%.*}
  if [ -n "$CLI_ONLY" ]; then case ",$CLI_ONLY," in *",$id,"*|*",$grp.*,"*) ;; *) return 1 ;; esac; fi
  case "$SKIP" in *",$id,"*|*",$grp.*,"*) return 1 ;; esac
  return 0
}
task(){ # true when the task should run: allowed, and opt-in tasks only when enabled
  task_allowed "$1" || return 1
  if [ "$(task_default "$1")" = off ]; then case "$ENABLE" in *",$1,"*) return 0 ;; esac; return 1; fi
  return 0
}

# ---------------------------------------------------------------- language
system_lang(){
  local l; l=$(defaults read -g AppleLanguages 2>/dev/null | sed -n '2p' | tr -d ' ",')
  case "$l" in uk*) echo uk ;; ru*) echo ru ;; *) echo en ;; esac
}
MSG_LANG="${MACUP_LANG:-$(conf language "")}"
[ -z "$MSG_LANG" ] && MSG_LANG=$(system_lang)
case "$MSG_LANG" in en|uk|ru) ;; *) MSG_LANG=en ;; esac
LANGFILE=""
load_lang(){
  [ -n "$LANGFILE" ] && rm -f "$LANGFILE"; LANGFILE=""
  [ "$MSG_LANG" = en ] && return
  LANGFILE=$(mktemp "${TMPDIR:-/tmp}/macup-lang.XXXXXX")
  lang_table "$MSG_LANG" >"$LANGFILE"
}
_(){ # translate a message (English text is the key)
  local v=""
  [ -n "$LANGFILE" ] && v=$(awk -F' [|][|] ' -v k="$1" '$1==k{print $2; exit}' "$LANGFILE")
  printf '%s' "${v:-$1}"
}
_f(){ local f; f=$(_ "$1"); shift; printf "$f" "$@"; }
lang_name(){ case "$1" in uk) echo "Українська" ;; ru) echo "Русский" ;; *) echo "English" ;; esac; }

# ---------------------------------------------------------------- output
if [ -t 1 ] && [ -z "$NO_COLOR" ]; then
  B=$'\033[1m'; G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[31m'; C=$'\033[36m'; D=$'\033[2m'; N=$'\033[0m'; CL=$'\r\033[K'
else B=; G=; Y=; R=; C=; D=; N=; CL=; fi

WARN=(); SKIPPED=(); UPDATED=(); FREED=0; BODY=""; PENDING=""; ERRS=0; STEP_SECS=3600
# --json: every line of the run, for a program that shows them its own way. kind: ok | info | warn | fail
IT_N=0; IT_SEC=(); IT_KIND=(); IT_MSG=(); SEC=""
item()    { [ "${JSON:-0}" = 1 ] || return 0; IT_SEC[IT_N]=$SEC; IT_KIND[IT_N]=$1; IT_MSG[IT_N]=$2; IT_N=$((IT_N + 1)); }
# the lines under an item go to a file: many are printed from the far end of a pipe, where a variable would be lost
detail()  { [ "${JSON:-0}" = 1 ] && [ "$IT_N" -gt 0 ] && [ -n "$BODY" ] && printf '%s\t%s\n' "$((IT_N - 1))" "$1" >>"$BODY.det"; return 0; }
md()      { [ -n "$BODY" ] && printf '%s\n' "$*" >>"$BODY"; }
section() { PENDING=$(_ "$1"); SEC=$PENDING; }   # printed lazily: sections with nothing to say stay hidden
flush()   { [ -z "$PENDING" ] && return; printf '%s\n%s▸ %s%s\n' "$CL" "$B$C" "$PENDING" "$N"; md ""; md "## $PENDING"; md ""; PENDING=""; }
# ok/info/warn/fail take a format string (translated) and its arguments
ok()      { local m; m=$(_f "$@"); flush; printf '%s  %s✓%s %s\n' "$CL" "$G" "$N" "$m"; md "- ✅ $m"; item ok "$m"; }
info()    { local m; m=$(_f "$@"); flush; printf '%s  %s·%s %s\n' "$CL" "$D" "$N" "$m"; md "- $m"; item info "$m"; }
warn()    { local m; m=$(_f "$@"); flush; printf '%s  %s!%s %s\n' "$CL" "$Y" "$N" "$m"; md "- ⚠️ $m"; WARN+=("$m"); item warn "$m"; }
fail()    { local m; m=$(_f "$@"); flush; printf '%s  %s✗%s %s\n' "$CL" "$R" "$N" "$m"; md "- ❌ $m"; WARN+=("$m"); item fail "$m"; }
err()     { fail "$@"; ERRS=$((ERRS + 1)); }   # a step that did not do its job: the run ends with exit status 3
sub()     { flush; printf '      %s%s%s\n' "$D" "$*" "$N"; md "    - $*"; detail "$*"; }
mdonly()  { md "    - $*"; detail "$*"; }
step()    { [ -t 1 ] && [ -n "$CL" ] && printf '%s  %s… %s%s' "$CL" "$D" "$(_f "$@")" "$N"; return 0; }
done_upd(){ UPDATED+=("$(_f "$@")"); }
tl()      { # seconds cmd… — the command, stopped after that long (macOS has no `timeout`); 124 when it was stopped
            # the command stays in the foreground, so Ctrl-C reaches it; shell functions run without a limit
            local secs=$1 wd rc; shift
            if [ "$secs" -le 0 ] || [ -z "$BODY" ] || [ "$(type -t "$1")" != file ]; then "$@"; return; fi
            rm -f "$BODY.to"
            ( end=$((SECONDS + secs))
              while [ "$SECONDS" -lt "$end" ]; do kill -0 $$ 2>/dev/null || exit 0; sleep 2; done
              p=$(cat "$BODY.pid" 2>/dev/null); [ -n "$p" ] || exit 0
              # with what it started: brew's curl and ruby would go on downloading after brew itself is stopped
              all=$(ps -Ao pid=,ppid= 2>/dev/null | awk -v r="$p" '{par[$1]=$2} END{for(c in par){x=c; while(x in par && x!=r && x>1) x=par[x]; if(x==r) print c} print r}')
              : >"$BODY.to"; kill -TERM $all 2>/dev/null; sleep 5; kill -KILL $all 2>/dev/null ) >/dev/null 2>&1 &
            wd=$!
            /bin/bash -c 'echo $$ >"$0"; exec "$@"' "$BODY.pid" "$@"; rc=$?
            kill "$wd" 2>/dev/null; wait "$wd" 2>/dev/null
            [ -f "$BODY.to" ] && { rm -f "$BODY.to"; return 124; }
            return $rc; }
run()     { local rc; echo "\$ $*" >>"$RAW"; tl "${RUN_SECS:-$STEP_SECS}" "$@" >>"$RAW" 2>&1 </dev/null; rc=$?
            if [ $rc = 124 ]; then
              echo "macup: stopped after $(( ${RUN_SECS:-$STEP_SECS} / 60 )) minutes: $*" >>"$RAW"
              warn '%s: stopped after %s minutes without finishing (step_timeout_minutes in %s)' "$1" "$(( ${RUN_SECS:-$STEP_SECS} / 60 ))" "$(tildify "$CONF")"
            fi
            return $rc; }
jstr()    { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\000-\037'; }   # a string for JSON and AppleScript
jlines()  { local l first=1; printf '['; while IFS= read -r l; do [ -n "$l" ] || continue; [ $first = 1 ] || printf ','; first=0; printf '"%s"' "$(jstr "$l")"; done <<EOF
$1
EOF
            printf ']'; }
jarr()    { local x first=1; printf '['; for x in "$@"; do [ $first = 1 ] || printf ','; first=0; printf '"%s"' "$(jstr "$x")"; done; printf ']'; }
TICK=""
tick()    { # label cmd… — run; on a terminal the step line counts the time and shows the command's latest "==> " phase, so a long job does not look hung
            [ -t 1 ] && [ -n "$CL" ] || { shift; run "$@"; return; }
            local label=$1 from w rc; shift
            from=$(($(cat "$RAW" 2>/dev/null | wc -l) + 2))   # past the "$ cmd" line run writes
            w=$(($(tput cols 2>/dev/null || echo 80) - 30)); [ "$w" -lt 10 ] && w=10
            label=${label:0:$w}   # a wrapped line would be left behind on every redraw
            ( t0=$SECONDS
              while kill -0 $$ 2>/dev/null; do
                ph=$(tail -n +"$from" "$RAW" | sed -n 's/^==> \([A-Za-z]*\).*/\1/p' | tail -1); s=$((SECONDS - t0))
                printf '%s  %s… %s%s · %d:%02d%s' "$CL" "$D" "$label" "${ph:+ · $(_ "$ph")}" $((s / 60)) $((s % 60)) "$N"
                sleep 1
              done ) & TICK=$!
            run "$@"; rc=$?
            kill "$TICK" 2>/dev/null; wait "$TICK" 2>/dev/null; TICK=""
            return $rc; }
have()    { local p; p=$(command -v "$1" 2>/dev/null) || return 1
            case "$p" in /usr/bin/python3|/usr/bin/pip3|/usr/bin/swift|/usr/bin/xcrun|/usr/bin/xcodebuild|/usr/bin/git) [ "$CLT_OK" = 1 ] ;; esac; }
link_fix(){ # interpreter → the brew link that puts it back on PATH; nothing when no formula has it
            local p v=""
            have "$1" && return   # a dead venv interpreter named python3: brew's python3 is linked, a link fixes nothing
            for p in ${HOMEBREW_PREFIX:-} /opt/homebrew /usr/local; do
              [ -x "$p/opt/$1/bin/$1" ] && { echo "brew link --overwrite $1"; return; }
              v="$v$(ls -d "$p/opt/$1"@*/bin/"$1" 2>/dev/null)"$'\n'
            done
            # --overwrite too: a leftover npm in the prefix blocks the link, and brew's own advice for that omits --force
            v=$(printf '%s' "$v" | awk -F/ 'NF{print $(NF-2)}' | sort -t@ -k2 -V | tail -1)
            [ -n "$v" ] && echo "brew link --force --overwrite $v"; }
cnt()     { if [ -z "$1" ]; then echo 0; else printf '%s\n' "$1" | grep -c .; fi; }
lines()   { [ -n "$1" ] && printf '%s\n' "$1" | while IFS= read -r l; do [ -n "$l" ] && sub "$l"; done; }
kb()      { if [ -e "$1" ]; then du -sk "$1" 2>/dev/null | awk '{s+=$1} END{print s+0}'; else echo 0; fi; }
hum()     { awk -v k="${1:-0}" 'BEGIN{ s=""; if(k<0){s="-";k=-k} b=k*1024; if(b>=1e9) printf "%s%.1f GB",s,b/1e9; else if(b>=1e6) printf "%s%.0f MB",s,b/1e6; else printf "%s%d KB",s,b/1e3 }'; }   # decimal, like Finder
tokb()    { echo "$1" | awk '{n=$1+0; u=$1; gsub(/[0-9.]/,"",u); u=toupper(u); m=(u=="TB")?1073741824:(u=="GB")?1048576:(u=="MB")?1024:(u=="KB")?1:0; printf "%d", n*m}'; }
tokb10()  { echo "$1" | awk '{n=$1+0; u=$1; gsub(/[0-9.]/,"",u); u=toupper(u); m=(u=="TB")?1e12:(u=="GB")?1e9:(u=="MB")?1e6:(u=="KB")?1e3:(u=="B")?1:0; printf "%d", n*m/1024}'; }   # Docker counts in decimal units
nocolor() { sed $'s/\x1b\\[[0-9;?]*[A-Za-z]//g'; }
tildify() { echo "$1" | sed "s|^$HOME|~|"; }
expand()  { echo "$1" | sed "s|^~|$HOME|"; }
ulen()    { printf '%s' "$1" | LC_ALL=C tr -d '\200-\277' | wc -c | tr -d ' '; }   # characters, not bytes
pad()     { local n; n=$(( $2 - $(ulen "$1") )); [ "$n" -lt 1 ] && n=1; printf '%s%*s' "$1" "$n" ''; }
UPD()     { [ "$DRY" = 0 ] && [ "$DO_UPDATE" = 1 ]; }
CLEAN()   { [ "$DRY" = 0 ] && [ "$DO_CLEAN" = 1 ]; }
WANT_UPD(){ [ "$DO_UPDATE" = 1 ] || [ "$DRY" = 1 ]; }
WANT_CLN(){ [ "$DO_CLEAN" = 1 ] || [ "$DRY" = 1 ]; }
upd()     { [ -z "$3" ] && return; if [ -n "$2" ] && [ "$2" != "$3" ]; then ok '%s: %s → %s' "$1" "$2" "$3"; UPDATED+=("$1 $2 → $3"); else ok '%s %s' "$1" "$3"; fi; }
ask()     { local a; printf '%s' "$1" >/dev/tty; read -r a </dev/tty; echo "$a"; }


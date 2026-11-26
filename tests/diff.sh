#!/bin/bash
# Differential harness: the bash build (./macup) and the Swift build (MACUP_BIN, else .build/debug/macup) run the same
# case on the same fake home, and what they leave must be the same after normalising (docs/swift-port-plan.md, "Parity").
#   tests/diff.sh              every case
#   tests/diff.sh tasks help   the cases whose name starts with one of these words
# Every case runs in en, uk and ru (MACUP_LANG), without a terminal and on one (through script), unless its last field
# says "pipe". Compared: stdout and stderr together as macup writes them (--json included), the exit status, the newest
# report, the files in the fake home. The system tools a run asks (df, diskutil, tmutil, brew, sudo, pgrep, osascript)
# are fakes (tests/fakes.sh), first in PATH and kept there (MACUP_PATH=keep).
cd "$(dirname "$0")/.." || exit 1
work=$(mktemp -d "${TMPDIR:-/tmp}/macup-diff.XXXXXX"); trap 'rm -rf "$work"' EXIT
export MACUP_BIN=${MACUP_BIN:-$PWD/.build/debug/macup}
[ -f macup ] && [ -x "$MACUP_BIN" ] || { echo "build both first: ./build.sh"; exit 1; }
failed=0; runs=0
# shellcheck source=tests/fakes.sh
. tests/fakes.sh
fakes "$work/bin" pgrep df diskutil tmutil brew sudo osascript; export PATH="$work/bin:$PATH"

# name | fixture | environment | arguments [| pipe | tty]   (the fixture is a fix_* function below; the environment is VAR=value words)
# ANSWERS=a/b in the environment is typed into the terminal, each answer when macup asks (bash's ask reads /dev/tty);
# ANSWERS=/ is one empty answer. A case that asks without answers waits for ever on a terminal: make it pipe.
# A check of a clean task on a terminal ends with the pick, which waits for an answer: such cases run without one.
CASES='help|||help
help-no-color|||help --no-color
help-lang||MACUP_LANG=|--lang uk help
help-NO_COLOR||NO_COLOR=1|help
help-config-lang|lang|MACUP_LANG=|help
tasks-config-lang|lang|MACUP_LANG=|tasks
version|||version
version-flag|||-v
tasks|config||tasks
tasks-empty-home|||tasks
tasks-json|config||tasks --json
tasks-only|config||tasks --only check.*,update.brew --skip check.disk
tasks-enable|config||tasks --enable clean.trash,clean.sim_erase --no-color
tasks-pick|config||tasks --pick some:key
tasks-xdg|config|XDG_CONFIG_HOME=@H/xdg|tasks --json
tasks-after-check|config||check tasks
tasks-unicode-blanks|blanks||tasks
tasks-latin1-config|latin1||tasks --json
help-latin1-config|latin1|MACUP_LANG=|help
tasks-step-09|octal||tasks
disk|||check --only check.disk
disk-low||FAKE_DF_FREE=75000000 FAKE_SWAP_KB=2097152 FAKE_SNAPS=3|check --only check.disk
disk-critical||FAKE_DF_FREE=10000000 FAKE_SMART=Failing|check --only check.disk
disk-no-smart||FAKE_SMART=|check --only check.disk --no-color
disk-json|||check --only check.disk --json
disk-quiet|||check --only check.disk --quiet
disk-unknown-in-config|badconf||check --only check.disk
disk-locked|locked||check --only check.disk
brew-check|brew||check --only update.brew
brew-check-current|brewcurrent||check --only update.brew
brew-check-json|brew||check --only update.brew --json
brew-update|brew||update --only update.brew
brew-update-current|brewcurrent||update --only update.brew
brew-upgrade-fails|brew|FAKE_BREW_FAIL=1 FAKE_SUDO_RC=0|update --only update.brew
brew-timeout|brew|MACUP_STEP_SECS=2 FAKE_BREW_SLEEP=30|update --only update.brew
brew-not-utf8|brew|FAKE_BREW_BYTES=1|update --only update.brew
brew-not-utf8-c|brew|FAKE_BREW_BYTES=1 LC_ALL=C|update --only update.brew
dd-check|dd||check --only clean.derived_data|pipe
dd-check-json|dd||check --only clean.derived_data --json
dd-clean|dd||clean --only clean.derived_data
dd-standard|dd||clean --level standard --only clean.derived_data
dd-aggressive|dd||all --level aggressive --only clean.derived_data
dd-busy|dd|FAKE_RUNNING=/Applications/Xcode.app/Contents/MacOS/Xcode|clean --only clean.derived_data
dd-busy-check|dd|FAKE_RUNNING=/Applications/Xcode.app/Contents/MacOS/Xcode|check --only clean.derived_data|pipe
dd-none|||clean --only clean.derived_data
dd-none-check|||check --only clean.derived_data
dd-small|ddsmall||check --only clean.derived_data
dd-symlink|ddlink||clean --only clean.derived_data
slice-all|slice|FAKE_SUDO_RC=0|all --only check.disk,update.brew,clean.derived_data --notify
slice-quiet-notify|dd|FAKE_DF_FREE=10000000|check --only check.disk,clean.derived_data --quiet --notify
trends|history||check --only check.trends,check.disk
trends-filling|historyfilling||check --only check.trends
reports|reports||check --only clean.reports'

fix_config(){ mkdir -p "$1/.config/macup" "$1/xdg/macup"
  printf 'language = en\nskip = check.docker, update.*  # not these\nenable = clean.trash\nclean_level = standard\n' >"$1/.config/macup/config"
  printf 'skip = clean.*\n' >"$1/xdg/macup/config"; }
fix_blanks(){ mkdir -p "$1/.config/macup"; printf 'skip = clean.brew\302\240\nenable = clean.trash\343\200\200 # ideographic space\n' >"$1/.config/macup/config"; }
fix_latin1(){ mkdir -p "$1/.config/macup"; printf 'language = uk\n# caf\351\nskip = clean.*\n' >"$1/.config/macup/config"; }   # sed stops at the byte
fix_octal(){ mkdir -p "$1/.config/macup"; printf 'step_timeout_minutes = 09\n' >"$1/.config/macup/config"; }   # bash's arithmetic fails
fix_lang(){ mkdir -p "$1/.config/macup"; printf 'language = ru\n' >"$1/.config/macup/config"; }
fix_badconf(){ mkdir -p "$1/.config/macup"; printf 'skip = check.bogus\nenable = clean.nope\n' >"$1/.config/macup/config"; }
fix_locked(){ mkdir -p "$1/Library/Application Support/macup/lock"; echo $$ >"$1/Library/Application Support/macup/lock/pid"; }   # this script runs
blob(){ mkdir -p "$1"; dd if=/dev/zero of="$1/blob" bs=1024 count="$2" 2>/dev/null; }
fix_dd(){ blob "$1/Library/Developer/Xcode/DerivedData/App-abc" 6144; blob "$1/Library/Developer/Xcode/DerivedData/Other-def/Build" 2048; }
fix_ddsmall(){ blob "$1/Library/Developer/Xcode/DerivedData/App-abc" 1024; }
fix_ddlink(){ fix_dd "$1"; blob "$1/elsewhere" 64; ln -s "$1/elsewhere" "$1/Library/Developer/Xcode/DerivedData/linked"; }
fix_brew(){ mkdir -p "$1/.fake/brewrepo/.git" "$1/.fake/brewcache/api"; : >"$1/.fake/brewrepo/.git/FETCH_HEAD"; touch -t 202001010000 "$1/.fake/brewrepo/.git/FETCH_HEAD"
  printf 'node (24.1.0) < 24.2.0\nwget (1.24) < 1.25\n' >"$1/.fake/brew-formulae"; printf 'firefox (140.0) != 141.0\n' >"$1/.fake/brew-casks"
  printf 'firefox\n' >"$1/.fake/brew-greedy"; for cask in a b c d e f g h i j k; do printf 'cask-%s\n' "$cask" >>"$1/.fake/brew-greedy"; done; }
fix_brewcurrent(){ mkdir -p "$1/.fake/brewcache/api"; : >"$1/.fake/brewcache/api/cask.jws.json"; }
fix_slice(){ fix_dd "$1"; fix_brew "$1"; }
fix_history(){ mkdir -p "$1/Library/Application Support/macup"; echo "2026-11-01 10:00,check,199000000,500000000,50,0,,,0,0,0" >"$1/Library/Application Support/macup/history.csv"; }
fix_historyfilling(){ mkdir -p "$1/Library/Application Support/macup"; echo "2026-11-01 10:00,check,250000000,500000000,50,0,612,80,0,0,0" >"$1/Library/Application Support/macup/history.csv"; }
fix_reports(){ local log="$1/Library/Logs/macup" state="$1/Library/Application Support/macup" day; mkdir -p "$log" "$state"
  for day in 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25; do : >"$log/macup_2026-10-${day}_10-00-00.md"; touch -t "202610${day}1000" "$log/macup_2026-10-${day}_10-00-00.md"; done
  for day in $(seq 1 1200); do echo "2026-10-01 10:00,check,$day,500000000,50,0,,,0,0,0"; done >"$state/history.csv"; }

# checks unit: the system tools answer from FAKE_* (tests/checks_fakes.sh); FAKE_SYSTEM=1 turns them on
# shellcheck source=tests/checks_fakes.sh
. tests/checks_fakes.sh; checks_fakes "$work/bin"
CASES="$CASES
chk-system||FAKE_SYSTEM=1|check --only check.system,check.memory,check.cpu,check.battery
chk-system-json||FAKE_SYSTEM=1 FAKE_BATT=83%|check --only check.system,check.memory,check.cpu,check.battery --json
chk-system-warn||FAKE_SYSTEM=1 FAKE_UP_DAYS=20 FAKE_UPTIME=4:05 FAKE_MEMFREE=9 FAKE_SWAP_USED=7.5G FAKE_LOAD=13.00 FAKE_THERM=CPU_Speed_Limit=80 FAKE_BATT=83% FAKE_CAPACITY=76%|check --only check.system,check.memory,check.cpu,check.battery
chk-system-odd||FAKE_SYSTEM=1 FAKE_MEMFREE= FAKE_SWAP_USED=x FAKE_LOAD=busy FAKE_CORES=x FAKE_MODEL= FAKE_BATT=55% FAKE_CONDITION=Service FAKE_CYCLES= FAKE_CAPACITY=|check --only check.system,check.memory,check.cpu,check.battery
chk-trends|historyfilling|FAKE_SYSTEM=1 FAKE_BATT=83% FAKE_CYCLES=650 FAKE_CAPACITY=76% FAKE_SWAP_USED=3.5G|check --only check.trends,check.memory,check.battery
chk-security||FAKE_SYSTEM=1 FAKE_TM_DEST=Backup FAKE_TM_DAYS=2|check --only check.security
chk-security-off||FAKE_SYSTEM=1 FAKE_FILEVAULT=Off FAKE_SIP=disabled FAKE_GATEKEEPER=disabled FAKE_AUTO_CHECK=0 FAKE_TM_DEST=Backup FAKE_TM_DAYS=30 FAKE_PROCS=ARDAgent|check --only check.security
chk-security-none||FAKE_SYSTEM=1 FAKE_FILEVAULT= FAKE_SIP= FAKE_GATEKEEPER= FAKE_CRITICAL=0|check --only check.security
chk-security-tm-unknown||FAKE_SYSTEM=1 FAKE_TM_DEST=Backup|check --only check.security --json
chk-security-skip-tm||FAKE_SYSTEM=1|check --only check.security --skip check.time_machine
chk-sizes|sizes|FAKE_SYSTEM=1|check --only check.sizes,check.creative
chk-sizes-update|sizes|FAKE_SYSTEM=1|update --only check.sizes
chk-deep|deep|FAKE_SYSTEM=1|check --deep --only check.disk
chk-deep-update|deep|FAKE_SYSTEM=1|update --deep --only check.sizes --json
chk-deep-no-roots|||check --deep --only check.disk
chk-deep-no-artifacts|emptycode||check --deep --only check.disk"
big(){ [ -f "$work/big" ] || dd if=/dev/zero of="$work/big" bs=1048576 count=101 2>/dev/null; mkdir -p "$(dirname "$1")"; cp -c "$work/big" "$1"; }   # a clone takes no space
fix_sizes(){ local dev="$1/Library/Developer" support="$1/Library/Application Support"
  blob "$dev/Xcode/Archives/App.xcarchive" 1024; blob "$dev/CoreSimulator/Devices/ABC" 512; blob "$1/.pub-cache" 64; blob "$1/Library/Caches/Some" 256
  blob "$1/.codex/sessions" 16; big "$1/.codex/state.sqlite"; big "$1/.codex/.hidden.sqlite"; blob "$1/.claude/projects" 32; blob "$1/.Trash" 128
  big "$1/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw"; big "$1/elsewhere/vm"; ln -s "$1/elsewhere" "$1/.lima"
  big "$1/Library/Caches/Adobe Camera Raw 2/cache"; blob "$support/Adobe/Common/Media Cache" 64; }
fix_deep(){ local support="$1/Library/Application Support"
  blob "$1/Code/web/node_modules/left-pad" 256; blob "$1/Code/rs/target/debug" 512; echo '[package]' >"$1/Code/rs/Cargo.toml"; blob "$1/Code/plain/target/data" 64
  blob "$support/Alpha" 64; blob "$support/beta" 64; blob "$1/dev/tool" 64; blob "$1/.hidden" 32; blob "$1/..dots" 32
  blob "$1/Downloads/old" 128; touch -t 202001010000 "$1/Downloads/old"; blob "$1/Downloads/new" 64
  dd if=/dev/zero of="$1/Downloads/disk.img" bs=1 count=0 seek=1100m 2>/dev/null; }   # sparse: over 1 GB, taking nothing
fix_emptycode(){ mkdir -p "$1/Code/notes"; }

# updates unit
# The updaters are answering fakes in the fake home (tests/fakes.sh): its .fake/bin, the shared fakes and /usr/bin and
# /bin are all PATH holds, so no real npm, mas or download is ever reached. calls.log in the home lists what was run.
# The bash build reads npm's, the plugins' and the catalog's JSON only with the Command Line Tools' python3: these cases
# need them (without, bash skips those sections, an intended difference).
upd_path="PATH=@H/.fake/bin:$work/bin:/usr/bin:/bin"
upd_simple=update.pipx,update.uv,update.rustup,update.omz,update.gh_ext,update.pnpm,update.bun,update.deno,update.cargo,update.mise,update.asdf,update.editor_ext,update.gcloud,update.dotnet,update.composer,update.gem
CASES+="
upd-claude-check|claude|$upd_path|check --only update.claude
upd-claude-check-json|claude|$upd_path|check --only update.claude --json
upd-claude-update|claude|$upd_path|update --only update.claude
upd-claude-fails|claudefail|$upd_path|update --only update.claude
upd-claude-timeout|claudeslow|$upd_path MACUP_STEP_SECS=2|update --only update.claude
upd-claude-current|claudecurrent|$upd_path|update --only update.claude
upd-npm-check|npm|$upd_path|check --only update.npm
upd-npm-update|npm|$upd_path|update --only update.npm
upd-npm-current|npmcurrent|$upd_path|update --only update.npm
upd-npm-bad-json|npmbad|$upd_path|check --only update.npm
upd-no-node|nonode|$upd_path HOMEBREW_PREFIX=@H/brew|check --only update.npm,update.skills
upd-skills-check|skills|$upd_path|check --only update.skills
upd-skills-update|skills|$upd_path|update --only update.skills
upd-skills-fails|skillsfail|$upd_path|update --only update.skills
upd-mas-check|mas|$upd_path|check --only update.mas
upd-mas-update|mas|$upd_path FAKE_SUDO_RC=0|update --only update.mas
upd-mas-asks|mas|$upd_path|update --only update.mas
upd-mas-sudo-refused|mas|$upd_path FAKE_SUDO_ASK_RC=1|update --only update.mas
upd-mas-timeout|masslow|$upd_path FAKE_SUDO_RC=0 MACUP_STEP_SECS=1|update --only update.mas
upd-mas-longer-limit|maslong|$upd_path FAKE_SUDO_RC=0 MACUP_STEP_SECS=1|update --only update.mas
upd-mas-current|mascurrent|$upd_path|update --only update.mas
upd-mas-missing||$upd_path|update --only update.mas
upd-apps-cached|apps|$upd_path|check --only update.apps
upd-apps-download|appsdownload|$upd_path|update --only update.apps
upd-apps-current|appscurrent|$upd_path|check --only update.apps
upd-apps-no-catalog|appsnone|$upd_path|check --only update.apps
upd-simple-check|simple|$upd_path|check --only $upd_simple --enable update.gem
upd-simple-update|simple|$upd_path|update --only $upd_simple --enable update.gem
upd-simple-fails|simplefail|$upd_path|update --only $upd_simple --enable update.gem
upd-simple-timeout|simpleslow|$upd_path MACUP_STEP_SECS=1|update --only update.rustup,update.mise
upd-simple-none|simplenone|$upd_path|update --only $upd_simple --enable update.gem
upd-grok-check|grok|$upd_path|check --only update.grok
upd-grok-update|grok|$upd_path|update --only update.grok
upd-grok-fails|grokfail|$upd_path|update --only update.grok
upd-grok-offline|grokoffline|$upd_path|check --only update.grok
upd-grok-brew|grokbrew|$upd_path|update --only update.grok
upd-grok-current|grokcurrent|$upd_path|check --only update.grok
upd-agy-check|agy|$upd_path|check --only update.agy
upd-agy-update|agy|$upd_path|update --only update.agy
upd-agy-fails|agyfail|$upd_path|update --only update.agy
upd-all-check|everything|$upd_path|check --only update.* --enable update.gem
upd-all-update|everything|$upd_path FAKE_SUDO_RC=0|update --only update.* --enable update.gem
upd-all-json|everything|$upd_path FAKE_SUDO_RC=0|update --only update.* --json"

upd_tools(){ local home=$1; shift; answering "$home/.fake/bin" "$@"; }
fix_claude(){ upd_tools "$1" claude npm node; mkdir -p "$1/.claude/plugins"
  answer "$1" claude --version '2.0.1 (Claude Code)'; answer "$1" npm view 2.1.0
  printf '%s' '{"version":2,"plugins":{"zeta@market":[{"scope":"project","version":"1.0.0"},{"scope":"user","version":"1.2.0"}],"alpha@market":[{"scope":"user","gitCommitSha":"abcdef1234567"}],"Beta@m":{"version":"0.9"},"local@m":[{"scope":"local","version":"3"}]}}' >"$1/.claude/plugins/installed_plugins.json"
  printf '%s' '{"version":2,"plugins":{"zeta@market":[{"scope":"user","version":"1.3.0"}],"alpha@market":[{"scope":"user","gitCommitSha":"9876543210"}],"Beta@m":{"version":"0.9"}}}' >"$1/.fake/plugins-new.json"
  echo 'echo "2.0.5 (Claude Code)" >"$HOME/.fake/claude/--version"' >"$1/.fake/claude/update.then"
  echo 'cp "$HOME/.fake/plugins-new.json" "$HOME/.claude/plugins/installed_plugins.json"' >"$1/.fake/claude/plugin.then"; }
fix_claudefail(){ fix_claude "$1"; echo 1 >"$1/.fake/claude/update.rc"; rm "$1/.fake/claude/update.then" "$1/.fake/claude/plugin.then"; echo 1 >"$1/.fake/claude/plugin marketplace update.rc"; }
fix_claudeslow(){ fix_claude "$1"; echo 30 >"$1/.fake/claude/update.sleep"; }
fix_claudecurrent(){ upd_tools "$1" claude; answer "$1" claude --version '2.0.1 (Claude Code)'; }
fix_npm(){ upd_tools "$1" npm node; mkdir -p "$1/npmroot" "$1/elsewhere"; ln -s "$1/elsewhere" "$1/npmroot/linked"; answer "$1" npm root "$1/npmroot"
  answer "$1" npm outdated '{"zlib-x":{"current":"1.0.0","wanted":"1.1.0","latest":"1.1.0"},"aaa":{"current":"2.0.0","latest":"3.0.0-beta.1"},"linked":{"current":"1.0.0","latest":"2.0.0"},"git-dep":{"current":"git","latest":"1.0.0"},"same":{"current":"1.0.0","latest":"1.0.0"},"num":{"current":1.5,"latest":"2.0.0"}}'
  echo 1 >"$1/.fake/npm/install -g aaa@3.0.0-beta.1.rc"; }
fix_npmcurrent(){ upd_tools "$1" npm node; answer "$1" npm outdated '{}'; }
fix_npmbad(){ upd_tools "$1" npm node; answer "$1" npm outdated 'npm ERR! offline'; }
fix_nonode(){ upd_tools "$1" npm npx; mkdir -p "$1/.agents" "$1/brew/opt/node@22/bin" "$1/brew/opt/node@24/bin"; echo '{"skills":{}}' >"$1/.agents/.skill-lock.json"
  : >"$1/brew/opt/node@22/bin/node"; : >"$1/brew/opt/node@24/bin/node"; }
fix_skills(){ upd_tools "$1" npx node; mkdir -p "$1/.agents"
  printf '%s' '{"version":3,"skills":{"web":{"skillFolderHash":"aaaaaaa111"},"pdf":{"skillFolderHash":"bbbbbbb222"},"Zed":{}}}' >"$1/.agents/.skill-lock.json"
  printf '%s' '{"version":3,"skills":{"web":{"skillFolderHash":"ccccccc333"},"pdf":{"skillFolderHash":"bbbbbbb222"},"xlsx":{"skillFolderHash":"ddddddd444"},"Zed":{}}}' >"$1/.fake/skills-new.json"
  mkdir -p "$1/.fake/npx"; echo 'cp "$HOME/.fake/skills-new.json" "$HOME/.agents/.skill-lock.json"' >"$1/.fake/npx/-y.then"; }
fix_skillsfail(){ fix_skills "$1"; echo 1 >"$1/.fake/npx/-y.rc"; }
fix_mas(){ upd_tools "$1" mas; answer "$1" mas outdated "$(printf '        1  Foo          (1.0    -> 1.1)\n123456789  Bar Baz Pro  (2.10.3 -> 3.0)')"; echo 1 >"$1/.fake/mas/upgrade 123456789.rc"; }
fix_masslow(){ fix_mas "$1"; echo 30 >"$1/.fake/mas/upgrade 1.sleep"; }
fix_maslong(){ fix_mas "$1"; echo 2 >"$1/.fake/mas/upgrade 1.sleep"; }   # longer than the step limit, within the App Store's four times that
fix_mascurrent(){ upd_tools "$1" mas; : >"$1/.fake/mas/outdated"; }
upd_app(){ mkdir -p "$1/Applications/$2.app/Contents"
  printf '<?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleShortVersionString</key><string>%s</string></dict></plist>' "$3" >"$1/Applications/$2.app/Contents/Info.plist"; }
upd_cask(){ printf '{"token":"%s","version":"%s","artifacts":[{"zap":["x"]},{"app":["%s.app"]}]}' "$@"; }
upd_catalog(){ printf '[%s,%s,%s,%s,%s,%s,%s,%s,%s]' "$(upd_cask macup-old 2.0,abc MacupOld)" "$(upd_cask macup-old@beta 3.0 MacupOld)" "$(upd_cask macup-new 2.0 MacupNew)" \
  "$(upd_cask macup-mas 2.0 MacupMas)" "$(upd_cask macup-twin 2.0 MacupTwin)" "$(upd_cask macup-twin-desktop 7.0 MacupTwin)" "$(upd_cask macup-cafe 1.10 'Macup Café')" \
  "$(upd_cask macup-bin 5.0.1 MacupBin)" "$(upd_cask macup-brewed 9.0 MacupBrewed)"; }
fix_apps(){ upd_tools "$1" curl; mkdir -p "$1/Library/Caches/macup"; upd_catalog >"$1/Library/Caches/macup/cask.json"
  upd_app "$1" MacupOld 1.0; upd_app "$1" MacupNew 2.0; upd_app "$1" MacupMas 1.0; upd_app "$1" MacupTwin 1.0; upd_app "$1" 'Macup Café' '1.9 (build 7)'
  upd_app "$1" MacupBin 5.0; plutil -convert binary1 "$1/Applications/MacupBin.app/Contents/Info.plist"; upd_app "$1" MacupBrewed 1.0
  mkdir -p "$1/Applications/MacupMas.app/Contents/_MASReceipt"; printf 'macup-brewed\n' >"$1/.fake/brew-list"; }
fix_appsdownload(){ fix_apps "$1"; mv "$1/Library/Caches/macup/cask.json" "$1/.fake/cask.json"; }
fix_appscurrent(){ upd_tools "$1" curl; mkdir -p "$1/Library/Caches/macup"; upd_catalog >"$1/Library/Caches/macup/cask.json"; upd_app "$1" MacupNew 2.0; }
fix_appsnone(){ upd_tools "$1" curl; }
fix_simple(){ upd_tools "$1" pipx uv rustup zsh gh pnpm node bun deno cargo cargo-install-update mise asdf code cursor windsurf codium gcloud dotnet composer gem
  mkdir -p "$1/.oh-my-zsh/tools" "$1/.dotnet/tools/x" "$1/.composer"; : >"$1/.oh-my-zsh/tools/upgrade.sh"; : >"$1/.composer/composer.json"
  answer "$1" gh 'extension list' 'dlvhdr/gh-dash  v4.0.0'; answer "$1" pnpm 'ls -g --json' '[{"dependencies":{"x":{"version":"1.0.0"}}}]'; answer "$1" dotnet --version 9.0.100; }
fix_simplefail(){ fix_simple "$1"; local tool first
  for tool in pipx:upgrade-all uv:tool rustup:update gh:extension pnpm:update bun:upgrade deno:upgrade cargo:install-update mise:upgrade asdf:plugin code:--update-extensions cursor:--update-extensions gcloud:components dotnet:tool composer:global gem:update; do
    first=${tool#*:}; mkdir -p "$1/.fake/${tool%%:*}"; echo 1 >"$1/.fake/${tool%%:*}/$first.rc"; done; }
fix_simpleslow(){ fix_simple "$1"; mkdir -p "$1/.fake/rustup"; echo 30 >"$1/.fake/rustup/update.sleep"; }
fix_simplenone(){ upd_tools "$1" gh pnpm dotnet; answer "$1" pnpm 'ls -g --json' '[]'; answer "$1" dotnet --version 8.0.400; mkdir -p "$1/.dotnet/tools/x"; : >"$1/.fake/gh/extension list"; }
fix_grok(){ upd_tools "$1" grok; answer "$1" grok 'update --check --json' '{"currentVersion":"1.0.70","latestVersion":"1.0.77","installer":"internal","error":null}'
  answer "$1" grok --version 'grok 1.0.70'; echo "echo 'grok 1.0.77' >\"\$HOME/.fake/grok/--version\"" >"$1/.fake/grok/update.then"; }
fix_grokfail(){ fix_grok "$1"; rm "$1/.fake/grok/update.then"; echo 1 >"$1/.fake/grok/update.rc"; }
fix_grokoffline(){ upd_tools "$1" grok; answer "$1" grok 'update --check --json' '{"currentVersion":"1.0.70","latestVersion":null,"installer":"internal","error":"offline"}'; }
fix_grokbrew(){ fix_grok "$1"; answer "$1" grok 'update --check --json' '{"currentVersion":"1.0.70","latestVersion":"1.0.77","installer":"brew","error":null}'; }
fix_grokcurrent(){ fix_grok "$1"; answer "$1" grok 'update --check --json' '{"currentVersion":"1.0.77","latestVersion":"1.0.77","installer":"internal"}'; }
fix_agy(){ upd_tools "$1" agy; answer "$1" agy --version 1.2.0; echo 'echo 1.3.0 >"$HOME/.fake/agy/--version"' >"$1/.fake/agy/update.then"; }
fix_agyfail(){ fix_agy "$1"; rm "$1/.fake/agy/update.then"; echo 1 >"$1/.fake/agy/update.rc"; }
fix_everything(){ fix_brew "$1"; fix_claude "$1"; fix_npm "$1"; fix_skills "$1"; fix_mas "$1"; fix_apps "$1"; fix_simple "$1"; fix_grok "$1"; fix_agy "$1"; }

# commands unit
# open and the editor only say what they were asked; the reports fixture has a cut report, one in Ukrainian and one with no mode
printf '#!/bin/bash\necho "open $*" >>"$HOME/open.log"\n' >"$work/bin/open"; printf '#!/bin/bash\necho "editor $*" >>"$HOME/editor.log"\n' >"$work/bin/editor"
chmod +x "$work/bin/open" "$work/bin/editor"; fakes "$work/bin" launchctl
CASES="$CASES"'
cmd-history-none|||history
cmd-history|cmd_history||history
cmd-history-no-color|cmd_history||history --no-color
cmd-history-one|history||history
cmd-history-long|reports||history
cmd-history-odd|cmd_history_odd||history
cmd-history-flat|cmd_history_flat||history
cmd-history-json|cmd_history_odd||history --json
cmd-history-json-none|||history --json
cmd-last-none|||last
cmd-last|cmd_reports||last
cmd-last-uncut|cmd_reports_uk||last
cmd-last-empty|reports||last
cmd-reports|cmd_reports||reports
cmd-reports-none|||reports
cmd-reports-json|cmd_reports||reports --json
cmd-reports-json-none|||--json reports
cmd-reports-kept|cmd_reports_kept||reports
cmd-reports-latin1|cmd_reports_latin1|MACUP_LANG=|reports
cmd-reports-empty-files|reports||reports clean --yes
cmd-reports-clean-no|cmd_reports|ANSWERS=n|reports clean
cmd-reports-clean-answer|cmd_reports|ANSWERS=Д|reports clean --no-color
cmd-reports-clean-yes|cmd_reports||reports clean -y
cmd-reports-open|||reports open
cmd-reports-bad|||reports nonsense
cmd-config-new|||config
cmd-config-new-lang|lang||config --lang uk
cmd-config-existing|config|VISUAL= EDITOR=editor|config
cmd-config-visual|config|VISUAL=editor EDITOR=nano|config
cmd-lang-uk|||lang uk
cmd-lang-ua|lang||language ua
cmd-lang-en-existing|lang||lang en --no-color
cmd-lang-bad|||lang xx
cmd-lang-asked||ANSWERS=2|lang
cmd-lang-asked-code|lang|ANSWERS=en|language
cmd-lang-asked-nonsense||ANSWERS=5|lang
cmd-uninstall-nothing|cmd_tmp|TMPDIR=@H/tmp/|uninstall
cmd-uninstall-yes|cmd_uninstall|TMPDIR=@H/tmp/|uninstall --yes
cmd-uninstall-yes-self|cmd_uninstall_self|TMPDIR=@H/tmp/ MACUP_AT=@H/.local/bin/macup|uninstall --yes --no-color
cmd-uninstall-yes-brew|cmd_uninstall_brew|TMPDIR=@H/tmp/ MACUP_AT=@H/brew/bin/macup|uninstall -y
cmd-uninstall-asked-no|cmd_uninstall|TMPDIR=@H/tmp/ ANSWERS=n|uninstall|tty
cmd-uninstall-asked-yes|cmd_uninstall|TMPDIR=@H/tmp/ ANSWERS=т|uninstall|tty
cmd-menu-help|||--no-color|pipe
cmd-menu-check|cmd_history|ANSWERS=1|--only check.disk
cmd-menu-default|cmd_history|ANSWERS=/|--only check.disk --no-color
cmd-menu-all|brew|ANSWERS=2 FAKE_SUDO_RC=0|--only check.disk,update.brew
cmd-menu-update|brew|ANSWERS=3|--only update.brew
cmd-menu-clean|dd|ANSWERS=4|--only clean.derived_data --lang ru
cmd-menu-deep|cmd_history|ANSWERS=5|--only check.disk
cmd-menu-history|cmd_history|ANSWERS=6|
cmd-menu-last|cmd_reports|ANSWERS=7|--no-color
cmd-menu-tasks|config|ANSWERS=8/n|
cmd-menu-tasks-config|config|ANSWERS=8/y EDITOR=editor|
cmd-menu-lang|lang|ANSWERS=9/3|
cmd-menu-help-choice||ANSWERS=h|--lang uk
cmd-menu-quit||ANSWERS=q|
cmd-menu-other||ANSWERS=x|--json'
fix_cmd_history(){ local state="$1/Library/Application Support/macup"; mkdir -p "$state"
  printf '%s\n' '2026-11-01 10:00,check,199000000,500000000,50,0,,,0,0,0' '2026-11-02 10:00,all,198000000,500000000,40,512,612,80,3,2048,1' \
    '2026-11-03 10:00,clean,201500000,500000000,,1024,613,79,0,500000,2' >"$state/history.csv"; }
fix_cmd_history_odd(){ local state="$1/Library/Application Support/macup"; mkdir -p "$state"   # no last newline, short and odd lines
  printf '2026-11-01 10:00,check,1500.5,500000000,50,0,,,0,-3,0\n2026-11-02 10:00,all,250\n2026-11-03 10:00,check,-7000,1e3,0x10,7,8,9,10,11.25,12' >"$state/history.csv"; }
fix_cmd_history_flat(){ local state="$1/Library/Application Support/macup" day; mkdir -p "$state"
  for day in 1 2 3; do echo "2026-11-0$day 10:00,check,250000000,500000000,50,0,612,80,0,,0"; done >"$state/history.csv"; }
fix_cmd_reports(){ local log="$1/Library/Logs/macup"; mkdir -p "$log"
  printf '# macup report — 2026-11-01 10:00\n\nMode: check · macup 2.9.2 · took 0m 5s\n\n## System\n\n✓ fine\n\n## Command output\n\n~~~~\n==> brew\n~~~~\n' >"$log/macup_2026-11-01_10-00-00.md"
  printf '# Звіт macup — 2026-11-02 11:30\n\nРежим: all+deep · macup 2.9.2 · took 1m 0s\n\n## Система\n' >"$log/macup_2026-11-02_11-30-00.md"
  printf 'no header\n' >"$log/macup_2026-11-03_09-15-00_4242.md"; blob "$log/blobs" 16; mv "$log/blobs/blob" "$log/macup_2026-11-01_10-00-00.log"
  : >"$log/schedule.log"; touch -t 202611031000 "$log"/macup_2026-11-0[13]*; touch -t 202611021130 "$log/macup_2026-11-02_11-30-00.md"; }
fix_cmd_reports_uk(){ fix_cmd_reports "$1"; touch -t 202611011000 "$1/Library/Logs/macup"/macup_2026-11-0[13]*; }
fix_cmd_reports_kept(){ fix_cmd_reports "$1"; mkdir -p "$1/.config/macup"; printf 'keep_reports_days = 007\nkeep_reports = 0\n' >"$1/.config/macup/config"; }
fix_cmd_reports_latin1(){ fix_cmd_reports "$1"; fix_latin1 "$1"; }
fix_cmd_tmp(){ mkdir -p "$1/tmp"; }
# 2.9 copies are found by their version line; the build under test ($build of run()) is copied where it runs itself
fix_cmd_uninstall(){ local home=$1
  mkdir -p "$home/tmp" "$home/.local/bin" "$home/.npm-global/bin" "$home/.config/macup" "$home/Library/Logs/macup" "$home/Library/Application Support/macup" \
    "$home/Library/Caches/macup" "$home/Library/LaunchAgents"
  printf '#!/bin/bash\n# macup\nMACUP_VERSION="2.9.0"\n' | tee "$home/.local/bin/macup" >"$home/.npm-global/bin/macup"; : >"$home/.npm-global/bin/other"; printf 'language = en\n' >"$home/.config/macup/config"
  blob "$home/Library/Logs/macup" 40; echo h >"$home/Library/Application Support/macup/history.csv"; : >"$home/Library/Caches/macup/cask.json"
  printf 'alias ll=ls\n\n# macup\nexport PATH="$HOME/.local/bin:$PATH"\nexport EDITOR=vim' >"$home/.zshrc"
  printf '# macup\nexport PATH="$HOME/.npm-global/bin:$PATH"\n' >"$home/.bash_profile"
  : >"$home/tmp/macup.Ab12Cd"; : >"$home/tmp/macup.Ab12Cd.rt"; : >"$home/tmp/macup.Zz99Yy."; : >"$home/tmp/macup-lang.Zz99Yy"; : >"$home/tmp/macup.sha256"
  : >"$home/tmp/macup.Ab_2Cd"; : >"$home/tmp/other.txt"; mkdir "$home/tmp/macup.Fold3r"; echo '<plist/>' >"$home/Library/LaunchAgents/com.vitaliideveloper.macup.plist"; }
fix_cmd_uninstall_self(){ fix_cmd_uninstall "$1"; rm "$1/.local/bin/macup"; if [ "$build" = swift ]; then cp "$MACUP_BIN" "$1/.local/bin/macup"; else cp macup "$1/.local/bin/macup"; fi; }
fix_cmd_uninstall_brew(){ local home=$1 copy; [ "$build" = swift ] && copy=$MACUP_BIN || copy=$PWD/macup
  mkdir -p "$home/tmp" "$home/brew/Cellar/macup/9.9.9/bin" "$home/brew/bin" "$home/.config/macup"; cp "$copy" "$home/brew/Cellar/macup/9.9.9/bin/macup"
  ln -s ../Cellar/macup/9.9.9/bin/macup "$home/brew/bin/macup"; printf 'language = en\n' >"$home/.config/macup/config"
  printf '#!/bin/bash\necho "brew $*" >>"$HOME/brew.log"\n[ "$1" = tap ] && printf "homebrew/core\\nvitaliideveloper/macup\\n"\n[ "$1" = uninstall ] && rm -rf "$HOME/brew/Cellar/macup"\nexit 0\n' >"$home/brew/bin/brew"; chmod +x "$home/brew/bin/brew"; }
# uninstall also looks at /usr/local/bin and /opt/homebrew/bin: --yes runs only where no macup but Homebrew's link is there
for real in /usr/local/bin/macup /opt/homebrew/bin/macup; do
  [ -e "$real" ] || [ -L "$real" ] || continue
  case "$(readlink "$real")" in */Cellar/macup/*) continue ;; esac
  echo "SKIP cmd-uninstall-yes: a macup is installed at $real"; CASES=$(printf '%s\n' "$CASES" | grep -v '^cmd-uninstall-yes')
done

# what may differ between two runs: dates and times, durations, report names, temporary paths, pids; on a terminal the
# transient step and tick lines, and the extra \r a terminal adds to a newline when a long write fills it; the script's name
# in bash's own diagnostics (the Swift build runs it as /dev/fd/N)
norm(){ # file home
  perl -pe '
    s/\r\e\[K  \e\[2m… [^\r\n]*(?=\r)//g;
    s/\r+\n/\r\n/g;
    s/\d{4}-\d\d-\d\d[ _]\d\d[:-]\d\d(?:[:-]\d\d)?/DATE/g;
    s/\b\d+m \d+s\b/Tm Ts/g;
    s/"seconds":\d+/"seconds":N/g;
    s/macup_DATE(?:_\d+)?\.md/macup_DATE.md/g;
    s{\Q'"${TMPDIR:-/tmp}"'\E/?macup[.-][A-Za-z0-9.]+}{TMP}g;
    s/\bpid \d+/pid N/g;
    s{^(?:/dev/fd/\d+|\S*macup): line (\d+): }{macup: line $1: }mg;
  ' "$1" | sed "s|$2|HOME|g"
}

type_answers(){ # a/b output-file done-file
  local answer list=() size=0
  IFS=/ read -ra list <<<"$1"
  for answer in ${list[@]+"${list[@]}"}; do
    # typed once the output has grown since the last answer (its echo) and ends with a question: "[y/N] ", "Choose [1]: ", "[1]:"
    until [ -e "$3" ] || { [ "$(wc -c <"$2")" -gt "$size" ] && tail -c 2 "$2" | grep -qE '[]:] ?$'; }; do sleep 0.1; done
    size=$(wc -c <"$2"); printf '%s\n' "$answer"   # measured while macup waits: a fast build answers before a later wc
  done
  until [ -e "$3" ] || [ ! -d "${3%/*}" ]; do sleep 0.1; done   # the work folder goes when diff.sh ends
}

run(){ # build lang tty fixture env args… → $work/<build>.{out,rc,report,files}
  local build=$1 lang=$2 tty=$3 fix=$4 envs=$5 home="$work/home" out="$work/$1"; shift 5
  rm -rf "$home"; mkdir -p "$home"; [ -n "$fix" ] && "fix_$fix" "$home"
  # bash runs python3, which on some Macs (Xcode's 3.9) leaves its bytecode in the fake home's Library/Caches/com.apple.python
  local vars=(HOME="$home" MACUP_LANG="$lang" MACUP_BUILD="$build" PATH="$PATH" MACUP_PATH=keep PYTHONDONTWRITEBYTECODE=1)
  local answers=""
  for word in $envs; do case "$word" in ANSWERS=*) answers=${word#ANSWERS=} ;; *) vars+=("${word//@H/$home}") ;; esac; done
  if [ "$tty" = tty ]; then
    # the terminal's input stays open until macup is done: at its end script would echo a ^D somewhere into the output.
    # A pipe, not a fifo: script on macOS 27 cannot take a fifo as its input.
    runs_done="$work/done.$runs.$build.$tty"
    script -q /dev/null env "${vars[@]}" tests/macup_run "$@" < <(type_answers "$answers" "$out.out" "$runs_done") >"$out.out" 2>&1; echo $? >"$out.rc"
    : >"$runs_done"
  else env "${vars[@]}" tests/macup_run "$@" </dev/null >"$out.out" 2>&1; echo $? >"$out.rc"; fi
  local report; report=$(ls -t "$home"/Library/Logs/macup/macup_*.md 2>/dev/null | head -1)
  if [ -n "$report" ]; then norm "$report" "$home" >"$out.report"; else : >"$out.report"; fi
  norm "$out.out" "$home" >"$out.norm"; mv "$out.norm" "$out.out"
  # the history's lines start with the date and time of the run
  local history="$home/Library/Application Support/macup/history.csv"
  { (cd "$home" && { find . ! -path './Library/Logs/macup/*' ! -path './Library/Application Support/macup/history.csv' -type f -exec cksum {} +
      find . -type l -exec sh -c 'for link; do echo "link $link -> $(readlink "$link")"; done' sh {} +; } | LC_ALL=C sort -k3)
    [ -f "$history" ] && norm "$history" "$home" | cksum; } >"$out.files"
}

while IFS='|' read -r name fix envs args modes <&3; do
  if [ $# -gt 0 ]; then matched=0; for prefix in "$@"; do case "$name" in "$prefix"*) matched=1 ;; esac; done; [ $matched = 1 ] || continue; fi
  for lang in en uk ru; do
    for tty in ${modes:-pipe tty}; do
      runs=$((runs + 1))
      # shellcheck disable=SC2086 # the arguments are words
      run bash "$lang" "$tty" "$fix" "$envs" $args
      # shellcheck disable=SC2086
      run swift "$lang" "$tty" "$fix" "$envs" $args
      bad=""
      for kind in out rc report files; do cmp -s "$work/bash.$kind" "$work/swift.$kind" || bad="$bad $kind"; done
      if [ -z "$bad" ]; then echo "SAME $name $lang $tty"
      else failed=1; echo "DIFF $name $lang $tty:$bad"
        for kind in $bad; do diff "$work/bash.$kind" "$work/swift.$kind" | head -10 | sed 's/^/    /'; done
      fi
    done
  done
done 3<<<"$CASES"
echo; [ $runs -gt 0 ] || { echo "no case matches: $*"; exit 2; }
[ $failed = 0 ] && echo "ALL SAME ($runs runs)" || { echo "SOME DIFFER"; exit 1; }

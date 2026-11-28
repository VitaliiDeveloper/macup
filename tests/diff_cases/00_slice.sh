# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # SC2034: CASES is read by tests/diff.sh; SC2154: work, build and the helpers come from it
# Sourced by tests/diff.sh, in name order: phase 1's cases: help, tasks, config, disk, clean, update, the run itself.
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
tasks-step-010|octal||tasks
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
fix_octal(){ mkdir -p "$1/.config/macup"; printf 'step_timeout_minutes = 010\n' >"$1/.config/macup/config"; }   # octal 8 in bash, 10 in Swift; 09 is in 95_args.sh
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

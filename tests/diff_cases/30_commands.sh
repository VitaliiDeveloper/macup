# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # SC2034: CASES is read by tests/diff.sh; SC2154: work, build and the helpers come from it
# Sourced by tests/diff.sh, in name order: the commands unit.
# commands unit
# open and the editor only say what they were asked; the reports fixture has a cut report, one in Ukrainian and one with no mode
printf '#!/bin/bash\necho "open $*" >>"$HOME/open.log"\n' >"$work/bin/open"; printf '#!/bin/bash\necho "editor $*" >>"$HOME/editor.log"\n' >"$work/bin/editor"
# main's macup as the version check fetches it: $HOME/.fake/remote-macup, a failed download without it; other URLs are real
printf '#!/bin/bash\nfor url; do :; done\ncase "$url" in */main/macup) ;; *) exec /usr/bin/curl "$@" ;; esac\necho "curl $url" >>"$HOME/curl.log"\ncat "$HOME/.fake/remote-macup" 2>/dev/null || exit 22\n' >"$work/bin/curl"
chmod +x "$work/bin/open" "$work/bin/editor" "$work/bin/curl"; fakes "$work/bin" launchctl
# history's trend line is bold, with nothing before its label: bash's awk h() set the global b, the bold colour, to the last
# freed value in bytes
known_trend(){ perl -pe '/(?:▁|▂|▃|▄|▅|▆|▇|█)+  \(.* … .*\)\r*$/ and (s/^[-+.0-9a-z]+(?=.*\e\[0m )/\e[1m/ or s/^[-+.0-9a-z]+//)'; }
known_cmd_history(){ known_trend; }
known_cmd_history_no_color(){ known_trend; }
known_cmd_history_long(){ known_trend; }
known_cmd_history_odd(){ known_trend; }
known_cmd_history_flat(){ known_trend; }
known_cmd_menu_history(){ known_trend; }
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
cmd-last-utf8|cmd_reports_uk|LANG=en_US.UTF-8 LC_ALL= LC_COLLATE=|last
cmd-reports|cmd_reports||reports
cmd-reports-none|||reports
cmd-reports-json|cmd_reports||reports --json
cmd-reports-json-utf8|cmd_reports|LANG=en_US.UTF-8 LC_ALL= LC_COLLATE=|reports --json
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
cmd-newer|cmd_remote_newer||check --only check.self_update
cmd-newer-json|cmd_remote_newer||check --only check.self_update --json
cmd-newer-brew|cmd_remote_newer_brew|MACUP_AT=@H/../brew/bin/macup|check --only check.self_update
cmd-newer-same|cmd_remote_same||check --only check.self_update
cmd-newer-older|cmd_remote_older||check --only check.self_update
cmd-newer-offline|||check --only check.self_update --no-color
cmd-newer-asked-this-week|cmd_stamp_fresh||check --only check.self_update
cmd-newer-asked-long-ago|cmd_stamp_stale||check --only check.self_update
cmd-newer-no-repo|cmd_remote_newer|MACUP_REPO=__REPO__|check --only check.self_update
cmd-newer-skipped|cmd_remote_newer||check --only check.disk
cmd-uninstall-nothing|cmd_tmp|TMPDIR=@H/tmp/|uninstall
cmd-uninstall-yes|cmd_uninstall|TMPDIR=@H/tmp/|uninstall --yes
cmd-uninstall-yes-utf8|cmd_uninstall|TMPDIR=@H/tmp/ LANG=en_US.UTF-8 LC_ALL= LC_COLLATE=|uninstall --yes
cmd-uninstall-yes-self|cmd_uninstall_self|TMPDIR=@H/tmp/ MACUP_AT=@H/.local/bin/macup|uninstall --yes --no-color
cmd-uninstall-yes-brew|cmd_uninstall_brew|TMPDIR=@H/tmp/ MACUP_AT=@H/brew/bin/macup|uninstall -y
cmd-uninstall-asked-no|cmd_uninstall|TMPDIR=@H/tmp/ ANSWERS=n|uninstall|tty
cmd-uninstall-yes-asked|cmd_uninstall|TMPDIR=@H/tmp/ ANSWERS=т|uninstall|tty
cmd-menu-help|||--no-color|pipe
cmd-menu-check|cmd_history|ANSWERS=1|--only check.disk
cmd-menu-default|cmd_history|ANSWERS=/|--only check.disk --no-color
cmd-menu-all|brew|ANSWERS=2 FAKE_SUDO_RC=0|--only check.disk,update.brew
cmd-menu-update|brew|ANSWERS=3|--only update.brew
cmd-menu-clean|dd|ANSWERS=4|--only clean.derived_data --lang ru
cmd-menu-deep|cmd_history|ANSWERS=5|--only check.disk
cmd-menu-history|cmd_history|ANSWERS=6||tty
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
  printf 'no header\n' | tee "$log/macup_2026-11-03_09-15-00.md" "$log/macup_2026-11-03_09-15-00-x.md" >"$log/macup_2026-11-03_09-15-00_4242.md"; blob "$log/blobs" 16; mv "$log/blobs/blob" "$log/macup_2026-11-01_10-00-00.log"
  : >"$log/schedule.log"; touch -t 202611031000 "$log"/macup_2026-11-0[13]*; touch -t 202611021130 "$log/macup_2026-11-02_11-30-00.md"; }
fix_cmd_reports_uk(){ fix_cmd_reports "$1"; touch -t 202611011000 "$1/Library/Logs/macup"/macup_2026-11-0[13]*; }
fix_cmd_reports_kept(){ fix_cmd_reports "$1"; mkdir -p "$1/.config/macup"; printf 'keep_reports_days = 007\nkeep_reports = 0\n' >"$1/.config/macup/config"; }
fix_cmd_reports_latin1(){ fix_cmd_reports "$1"; fix_latin1 "$1"; }
fix_cmd_tmp(){ mkdir -p "$1/tmp"; }
remote_macup(){ mkdir -p "$1/.fake"; printf '#!/bin/bash\n# macup\nMACUP_VERSION="%s"\nMACUP_VERSION="0.0.1"\n' "$2" >"$1/.fake/remote-macup"; }
fix_cmd_remote_newer(){ remote_macup "$1" 9.9.9; }
fix_cmd_remote_same(){ remote_macup "$1" 2.9.2; }
fix_cmd_remote_older(){ remote_macup "$1" 2.10.0-beta; }   # sort -n reads 10-beta as 10: newer
fix_cmd_remote_newer_brew(){ local prefix="$1/../brew" copy; [ "$build" = swift ] && copy=$MACUP_BIN || copy=$PWD/macup   # next to the home: not compared
  rm -rf "$prefix"; mkdir -p "$prefix/Cellar/macup/3.0.0/bin" "$prefix/bin"; cp "$copy" "$prefix/Cellar/macup/3.0.0/bin/macup"
  ln -s ../Cellar/macup/3.0.0/bin/macup "$prefix/bin/macup"; remote_macup "$1" 3.0.0; }
fix_cmd_stamp_fresh(){ local state="$1/Library/Application Support/macup"; mkdir -p "$state"; echo 9.9.9 >"$state/last_version_check"; remote_macup "$1" 2.0.0; }
fix_cmd_stamp_stale(){ fix_cmd_stamp_fresh "$1"; touch -t 202001010000 "$1/Library/Application Support/macup/last_version_check"; }
# 2.9 copies are found by their version line; the build under test ($build of run()) is copied where it runs itself
fix_cmd_uninstall(){ local home=$1
  mkdir -p "$home/tmp" "$home/.local/bin" "$home/.npm-global/bin" "$home/.config/macup" "$home/Library/Logs/macup" "$home/Library/Application Support/macup" \
    "$home/Library/Caches/macup" "$home/Library/LaunchAgents"
  printf '#!/bin/bash\n# macup\nMACUP_VERSION="2.9.0"\n' | tee "$home/.local/bin/macup" >"$home/.npm-global/bin/macup"; : >"$home/.npm-global/bin/other"; : >"$home/.npm-global/bin/_under"; : >"$home/.npm-global/bin/#x"; : >"$home/.npm-global/bin/Beta"; printf 'language = en\n' >"$home/.config/macup/config"
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

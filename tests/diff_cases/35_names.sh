# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # SC2034: CASES is read by tests/diff.sh; SC2154: work, build and the helpers come from it
# Sourced by tests/diff.sh, in name order: names in the locale's order (Foundation's Names).
# names in the locale's order: the report tidy-up (ls -r) and bash's globs, in UTF-8, in C, and with a locale macOS lacks
# (forwarded by ssh from Linux), where bash falls back to LANG and ls to C
CASES="$CASES"'
names-tidy-utf8|names_tidy|LANG=en_US.UTF-8 LC_ALL= LC_COLLATE=|check --only check.disk|pipe
names-tidy-c|names_tidy|LC_ALL=C|check --only check.disk|pipe
names-glob-utf8|names_glob|TMPDIR=@H/tmp/ LANG=en_US.UTF-8 LC_ALL= LC_COLLATE= ANSWERS=n|uninstall|tty
names-glob-uk|names_glob|TMPDIR=@H/tmp/ LANG=uk_UA.UTF-8 LC_ALL= LC_COLLATE= ANSWERS=n|uninstall|tty
names-glob-c|names_glob|TMPDIR=@H/tmp/ LC_ALL=C ANSWERS=n|uninstall|tty
names-tidy-ssh|names_tidy|LANG=en_US.UTF-8 LC_ALL= LC_COLLATE= LC_TIME=en_DK.UTF-8|check --only check.disk|pipe
names-glob-ssh|names_glob|TMPDIR=@H/tmp/ LANG=en_US.UTF-8 LC_ALL= LC_COLLATE=bogus ANSWERS=n|uninstall|tty'
# two reports from the same second, keep_reports = 2: the tidy-up keeps the first ls -r lists. They are links, which the
# files list shows even in the log folder
fix_names_tidy(){ local log="$1/Library/Logs/macup" name; mkdir -p "$log" "$1/kept" "$1/.config/macup"; printf 'keep_reports = 2\n' >"$1/.config/macup/config"
  for name in macup_2026-11-01_10-00-00.md macup_2026-11-01_10-00-00_4242.md; do echo "# $name" >"$1/kept/$name"; ln -s "../../../kept/$name" "$log/$name"; done; }
# uninstall shows the first three other names in each PATH folder: strcoll ties Cyrillic names, and e with a decomposed é
# (as Finder writes it), so bash's qsort decides their order
fix_names_glob(){ local name; fix_cmd_uninstall "$1"
  for name in ärger Éclair Zed "$(printf 'e\314\201')" e; do : >"$1/.local/bin/$name"; done
  for name in Їжак яблуко Дім ґанок; do : >"$1/.npm-global/bin/$name"; done; }

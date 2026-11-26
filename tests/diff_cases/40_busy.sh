# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # SC2034: CASES is read by tests/diff.sh; SC2154: work, build and the helpers come from it
# Sourced by tests/diff.sh, in name order: the busy-folder unit's cases (lsof_snap, open_in).
# lsof busy check (cleanup.sh lsof_snap, open_in, mark_busy): a JetBrains cache is in use while a process has a file open
# inside it. The fake lsof answers from FAKE_OPEN, FAKE_LSOF_CMD and FAKE_LSOF_FAIL; nolsof is the fakes without it.
fakes "$work/bin" lsof
mkdir -p "$work/nolsof"; for tool in "$work"/bin/*; do [ "${tool##*/}" = lsof ] || ln -s "$tool" "$work/nolsof/"; done
fix_jb(){ local caches="$1/Library/Caches/JetBrains"; blob "$caches/IntelliJIdea2024.1/index" 6144; blob "$caches/PyCharm2024.2/index/deep" 5200
  blob "$caches/Small" 1024; blob "$1/elsewhere" 6144; ln -s "$1/elsewhere" "$caches/Linked"; }
jb_deep=FAKE_OPEN=@H/Library/Caches/JetBrains/PyCharm2024.2/index/deep/blob
CASES+="
jb-check|jb||check --only clean.jetbrains|pipe
jb-json|jb||check --only clean.jetbrains --json|pipe
jb-open-deep|jb|$jb_deep|check --only clean.jetbrains --json|pipe
jb-open-text|jb|$jb_deep|check --only clean.jetbrains|pipe
jb-open-folder|jb|FAKE_OPEN=@H/Library/Caches/JetBrains/PyCharm2024.2|check --only clean.jetbrains --json|pipe
jb-open-watcher|jb|$jb_deep FAKE_LSOF_CMD=mds|check --only clean.jetbrains --json|pipe
jb-lsof-fails|jb|FAKE_LSOF_FAIL=1|check --only clean.jetbrains --json|pipe
jb-no-lsof|jb|PATH=$work/nolsof:/usr/bin:/bin|check --only clean.jetbrains|pipe
jb-none|||check --only clean.jetbrains --json|pipe
jb-clean|jb||clean --level standard --only clean.jetbrains
jb-clean-open|jb|$jb_deep|clean --level standard --only clean.jetbrains
jb-clean-lsof-fails|jb|FAKE_LSOF_FAIL=1|clean --level standard --only clean.jetbrains
jb-clean-no-lsof|jb|PATH=$work/nolsof:/usr/bin:/bin|clean --level standard --only clean.jetbrains"

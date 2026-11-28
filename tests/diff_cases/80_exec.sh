# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # SC2034: CASES is read by tests/diff.sh; SC2154: work and the helpers come from it
# Sourced by tests/diff.sh, in name order: what a clean really deletes (cleanup.sh exec_cand, run_key, del, to_trash_path) and
# the dev container scan (cleaners.sh), on the fixtures of the cleaners and leftovers units (50_cleaners.sh, 60_leftovers.sh).
# Every tool a cleanup runs is a fake in the home's .fake/bin, qlmanage included: the real one would reset this Mac's Quick
# Look cache. A fake mdfind (Spotlight) in $work/spotlight answers from $HOME/.fake/spotlight, one bundle id per line;
# com.apple.finder is always there unless $HOME/.fake/spotlight-off exists.
mkdir -p "$work/spotlight"; cat >"$work/spotlight/mdfind" <<'FAKE'
#!/bin/bash
[ -e "$HOME/.fake/spotlight-off" ] && exit 0
id=$(printf '%s' "$*" | sed -n "s/^kMDItemCFBundleIdentifier == '\(.*\)'c*$/\1/p")
{ echo com.apple.finder; cat "$HOME/.fake/spotlight" 2>/dev/null; } | grep -ixF -- "$id" >/dev/null && echo "/Applications/$id.app"
exit 0
FAKE
chmod +x "$work/spotlight/mdfind"
exec_sims=clean.sim_runtimes,clean.sim_erase,clean.sim_unused
exec_dev="$lo_env PATH=$work/spotlight:$work/bin:/usr/bin:/bin"
CASES+="
exec-caches|exec_caches|$cln_path|clean --level aggressive --only $cln_caches
exec-caches-standard|exec_caches|$cln_path|all --only $cln_caches --json|pipe
exec-caches-busy|exec_caches|$cln_path FAKE_RUNNING=/usr/local/bin/cargo|clean --level aggressive --only $cln_caches|pipe
exec-xcode|exec_xcode|$cln_path|clean --level aggressive --only $cln_xcode --enable $exec_sims
exec-xcode-busy|exec_xcode|$cln_path FAKE_RUNNING=/Applications/Xcode.app/Contents/MacOS/Xcode|clean --level aggressive --only $cln_xcode --enable $exec_sims|pipe
exec-brew|exec_brew|$cln_path|clean --level aggressive --only $cln_brew --enable clean.docker_images,clean.docker_containers,clean.brew_autoremove
exec-brew-json|exec_brew|$cln_path|clean --level standard --only $cln_brew --json|pipe
exec-brew-fail|exec_brew_fail|$cln_path|clean --level aggressive --only $cln_brew --enable clean.docker_images,clean.docker_containers,clean.brew_autoremove
exec-projects|cln_projects|$cln_path|clean --level aggressive --only $cln_projects --enable clean.stale_node_modules,clean.stale_artifacts
exec-ai|exec_ai|$cln_path|clean --level aggressive --only $cln_ai
exec-ai-busy|exec_ai|$cln_path FAKE_RUNNING=/usr/local/bin/claude|clean --only $cln_ai|pipe
exec-logs-refused|exec_refused|$cln_path|clean --only clean.logs
exec-logs-locked|exec_locked|$cln_path|clean --only clean.logs
exec-dev|lo|$exec_dev|clean --only clean.dev_containers,clean.orphan_data|tty
exec-dev-spotlight-off|exec_dev_off|$exec_dev|clean --only clean.dev_containers|tty
exec-dev-app-back|exec_dev_app|$exec_dev|clean --only clean.dev_containers|tty
exec-dev-open|lo|$exec_dev FAKE_OPEN=@H/Library/Containers/com.teamed.dev.App/x|clean --only clean.dev_containers|tty
exec-dev-lsof-fails|lo|$exec_dev FAKE_LSOF_FAIL=1|clean --only clean.dev_containers|tty
exec-dev-unreadable|exec_dev_unreadable|$exec_dev|clean --only clean.dev_containers|tty
exec-dev-emptied|exec_dev_emptied|$exec_dev|all --only clean.dev_containers,check.disk|tty"

# what the cleanup's own commands print: what they freed, as brew and docker say it
fix_exec_caches(){ fix_cln_caches "$1"; answering "$1/.fake/bin" qlmanage; }
fix_exec_xcode(){ fix_cln_xcode "$1"; answering "$1/.fake/bin" qlmanage; }
fix_exec_brew(){ fix_cln_brew "$1"; answering "$1/.fake/bin" qlmanage
  answer "$1" brew 'cleanup -s --prune=7' "$(printf '==> Removing: x\n==> This operation has freed approximately 1.2GB of disk space.\nfreed approximately 340MB')"
  answer "$1" docker 'builder prune -f' "$(printf 'Deleted build cache objects:\nabc\n\nTotal reclaimed space: 1.2GB')"
  answer "$1" docker 'image prune -f' 'Total reclaimed space: 300MB'
  answer "$1" docker 'image prune -a -f' "$(printf 'Deleted Images:\nuntagged: foo:1\n\nTotal reclaimed space:   2.5GB')"
  answer "$1" docker 'container prune -f' "$(printf 'Deleted Containers:\nabc\n\nTotal reclaimed space: 300MB\nTotal reclaimed space: 12.3MB')"; }
# brew's cleanup fails (its status does not count), docker's build cache fails, the images say nothing, autoremove exits 2
# (read as "skipped", so it says nothing) and Quick Look fails
fix_exec_brew_fail(){ fix_cln_brew "$1"; answering "$1/.fake/bin" qlmanage
  answer "$1" brew 'cleanup -s --prune=7.rc' 1; answer "$1" docker 'builder prune -f.rc' 1; answer "$1" docker 'image prune -a -f' ''
  answer "$1" brew 'autoremove.rc' 2; answer "$1" qlmanage '-r cache.rc' 1; }
# a Trash that already holds a folder of that name, and a link to nothing under the next free one
fix_exec_ai(){ fix_cln_ai "$1"; mkdir -p "$1/.Trash/gone-2"; echo old >"$1/.Trash/gone-2/edit"; ln -s "$1/nowhere" "$1/.Trash/gone-2 2"
  echo new >"$1/.claude/file-history/gone-2/edit"; echo x >"$1/.codex/.tmp/plugins-backup-7/repo"; aged "$1/.claude/file-history" "$1/.codex/.tmp"; }
# an old log macup may not delete (*.sqlite) is the only one: nothing removed, an error
fix_exec_refused(){ blob "$1/Library/Logs/App" 1500; mv "$1/Library/Logs/App/blob" "$1/Library/Logs/App/db.sqlite"; aged "$1/Library/Logs"; }
# old logs in a folder macOS will not let macup write: they stay, an error
fix_exec_locked(){ blob "$1/Library/Logs/Locked" 1500; echo x >"$1/Library/Logs/Locked/b.log"; aged "$1/Library/Logs"; chmod 555 "$1/Library/Logs/Locked"; }
fix_exec_dev_off(){ fix_lo "$1"; : >"$1/.fake/spotlight-off"; }
fix_exec_dev_app(){ fix_lo "$1"; echo com.teamed.dev >"$1/.fake/spotlight"; }   # dev.app is there for dev.app.App
fix_exec_dev_unreadable(){ fix_lo "$1"; chmod 000 "$1/Library/Containers/com.teamed.dev.App"; }
fix_exec_dev_emptied(){ fix_lo "$1"; local container="$1/Library/Containers/com.teamed.dev.App"
  rm -rf "$container"; mkdir -p "$container"; echo marker >"$container/.com.apple.containermanagerd.metadata.plist"; }

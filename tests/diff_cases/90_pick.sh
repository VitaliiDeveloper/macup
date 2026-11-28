# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # SC2034: CASES is read by tests/diff.sh; SC2154: work and the helpers come from it
# Sourced by tests/diff.sh, in name order: the pick at the end of a check on a terminal, its confirmations, --pick
# (summary.sh, cleanup.sh pick, cleaners.sh), on the fixtures of 50_cleaners.sh, 60_leftovers.sh and 80_exec.sh.
# ANSWERS are typed when macup asks; the fake sudo (tests/fakes.sh) asks nothing and runs nothing, it only records.
# A picked leftover is stopped with launchctl first: a recording fake here, never this Mac's own.
fakes "$work/pickbin" launchctl
pick_path="PATH=@H/.fake/bin:$work/pickbin:$work/spotlight:$work/bin:/usr/bin:/bin"
pick_lo="$lo_env $pick_path"
key(){ printf '%s:%s' "$1" "$(printf '%s' "$2" | cksum | cut -d' ' -f1)"; }   # task source → the key a check gives (cleanup.sh cand)
pick_logs=$(key clean.logs logs); pick_brew=$(key clean.brew 'cmd|brew'); pick_docker=$(key clean.docker 'cmd|docker')
pick_agent=$(key clean.orphan_agents 'cmd|orph:0'); pick_data=$(key clean.orphan_data 'cmd|odata:0')
ctrl_c=$(printf '\003'); ctrl_d=$(printf '\004')   # keys typed into the terminal: SIGINT, the end of the input
pick_dev=$(key clean.dev_containers "cmd|devc:$work/home/Library/Containers/com.teamed.dev.App")
CASES+="
pick-enter|exec_caches|$pick_path ANSWERS=/|check --only $cln_caches|tty
pick-garbage|exec_caches|$pick_path ANSWERS=zzz,999|check --only $cln_caches|tty
pick-numbers|exec_caches|$pick_path ANSWERS=1,3|check --only $cln_caches|tty
pick-range-yes|exec_caches|$pick_path ANSWERS=1-30/y|check --level aggressive --only $cln_caches|tty
pick-range-no|exec_caches|$pick_path ANSWERS=1-30/n|check --only $cln_caches|tty
pick-level|exec_brew|$pick_path ANSWERS=standard|check --only $cln_brew --enable clean.docker_images|tty
pick-optin|exec_brew|$pick_path ANSWERS=1-20/y|check --only $cln_brew|tty
pick-xcode|exec_xcode|$pick_path ANSWERS=1-20/y|check --only $cln_xcode|tty
pick-ai|exec_ai|$pick_path ANSWERS=1-30/y|check --level aggressive --only $cln_ai|tty
pick-leftovers|lo|$pick_lo ANSWERS=1,2,3,4,5,6,7,8,9,10/y|check --only $lo_tasks|tty
pick-leftovers-range|lo|$pick_lo ANSWERS=1-30/y|check --only $lo_tasks|tty
pick-leftovers-no|lo|$pick_lo ANSWERS=1,2,3/n|check --only $lo_tasks|tty
pick-sudo-refused|lo|$pick_lo FAKE_SUDO_ASK_RC=1 ANSWERS=1,2,3,4,5,6,7,8,9,10/y|check --only $lo_tasks|tty
pick-leftovers-busy|lo|$pick_lo FAKE_RUNNING=/Applications/Gone.app/Contents/MacOS/Gone FAKE_OPEN=@H/Library/Perplexity/x ANSWERS=1,2,3,4,5,6,7,8,9,10/y|check --only $lo_tasks|tty
pick-leftovers-back|loapp|$pick_lo ANSWERS=1,2,3,4,5,6,7,8/y|check --only clean.orphan_agents,clean.orphan_data|tty
pick-dev|lo|$pick_lo ANSWERS=1/y|check --only clean.dev_containers|tty
pick-dev-open|lo|$pick_lo FAKE_OPEN=@H/Library/Containers/com.teamed.dev.App/x ANSWERS=1/y|check --only clean.dev_containers|tty
pick-busy|exec_caches|$pick_path FAKE_RUNNING=/usr/local/bin/cargo ANSWERS=1-30/y|check --level aggressive --only $cln_caches|tty
pick-ctrl-c|exec_caches|$pick_path ANSWERS=$ctrl_c|check --only $cln_caches|tty
pick-ctrl-c-confirm|exec_caches|$pick_path ANSWERS=1-30/$ctrl_c|check --only $cln_caches|tty
pick-ctrl-d|exec_caches|$pick_path ANSWERS=$ctrl_d|check --only $cln_caches|tty
pick-ctrl-d-confirm|exec_caches|$pick_path ANSWERS=1-30/$ctrl_d|check --only $cln_caches|tty
pick-quiet|exec_caches|$pick_path|check --only $cln_caches --quiet|tty
pick-json|exec_caches|$pick_path|check --only $cln_caches --json|tty
pick-level-uk|exec_caches|$pick_path ANSWERS=безпечна,стандартна|check --only $cln_caches|tty
pick-level-hidden|exec_caches|$pick_path ANSWERS=safe,14/y|check --only $cln_caches|tty
pick-cyrillic-yes|exec_caches|$pick_path ANSWERS=1-30/т|check --only $cln_caches|tty
pick-keys|exec_brew|$pick_path|clean --pick $pick_logs,$pick_brew,$pick_brew,clean.nope:1 --only $cln_brew
pick-keys-json|exec_brew|$pick_path|clean --pick $pick_docker,$pick_logs --only $cln_brew --json|pipe
pick-keys-none|exec_brew|$pick_path|clean --pick clean.nope:1,clean.logs:2|pipe
pick-keys-leftovers|lo|$pick_lo|clean --pick $pick_agent,$pick_data,$pick_dev --only $lo_tasks,clean.dev_containers"

# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # SC2034: CASES is read by tests/diff.sh; SC2154: the helpers come from it
# Sourced by tests/diff.sh, in name order: what arguments.sh says when it rejects a command line, and the unknown task ids
# it stops at once the config is loaded. Each message is said in the language known at that word: a --lang before it, else
# the config's or MACUP_LANG.
CASES+="
arg-unknown|||bogus
arg-unknown-option|||check --bogus
arg-unknown-after-lang|||--lang uk check bogus
arg-unknown-before-lang|||bogus --lang ru
arg-unknown-after-help|||help bogus
arg-level-bad|||check --level huge
arg-level-equals|||--level=x check
arg-level-missing|||check --level
arg-level-after-unknown|||bogus --level huge
arg-lang-bad|||--lang xx help
arg-lang-equals|||help --lang=de
arg-lang-missing|||check --lang
arg-lang-ua|||--lang ua bogus
arg-bad-config|arg_bad_config|MACUP_LANG=|bogus
arg-bad-config-ids|arg_bad_config|MACUP_LANG=|check --only chek.disk
arg-only-unknown|||check --only chek.disk,check.cpu,update.*
arg-skip-unknown|||all --skip=check.disk,,nope,clean.*
arg-enable-unknown|||clean --enable clean.nope --enable=x.y
arg-unknown-ids-many|||check --only a.b --skip c.d --enable e.f --json
arg-unknown-quiet|||update --only zzz --quiet
arg-unknown-pick|||clean --pick clean.x:1 --only chek.disk
zeros-09|zeros_09||check --only check.disk
zeros-010|zeros_010||check --only check.disk,check.trends
zeros-days-xcode|zeros_xcode|$cln_path|check --level aggressive --only $cln_xcode --json|pipe
zeros-days-projects|zeros_projects|$cln_path|check --level aggressive --only $cln_projects|pipe"

fix_arg_bad_config(){ mkdir -p "$1/.config/macup"; printf 'skip = caf\351\nlanguage = uk\n' >"$1/.config/macup/config"; }   # sed stops at the byte that is not UTF-8

# Leading zeros in the config's numbers are decimal in Swift (an intended difference). Bash read step_timeout_minutes 010 as
# octal 8 (seen only when a step times out) and gave up on 08 and 09: it said so with its own script's line, and its
# load_conf stopped there (`macup tasks` then printed the help and exited 2: XCTest). The day counts it showed as written (030).
zeros_config(){ mkdir -p "$1/.config/macup"; printf '%s\n' "$2" >"$1/.config/macup/config"; }
fix_zeros_09(){ zeros_config "$1" 'step_timeout_minutes = 09'; }
fix_zeros_010(){ zeros_config "$1" 'step_timeout_minutes = 010'; }
fix_zeros_xcode(){ fix_cln_xcode "$1"; zeros_config "$1" "$(printf 'simulator_days = 030\ndevice_support_days = 090')"; }
fix_zeros_projects(){ fix_cln_projects "$1"; zeros_config "$1" 'stale_project_days = 090'; }
known_zeros_09(){ grep -v ': 09: value too great for base (error token is "09")'; }
known_zeros_days_xcode(){ perl -pe 's/(?<=[ (])0(?=[39]0[+ ])//g'; }
known_zeros_days_projects(){ perl -pe 's/(?<=[ (])0(?=90 )//g'; }

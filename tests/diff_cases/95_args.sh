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
arg-bad-config|arg_bad_config||bogus
arg-only-unknown|||check --only chek.disk,check.cpu,update.*
arg-skip-unknown|||all --skip=check.disk,,nope,clean.*
arg-enable-unknown|||clean --enable clean.nope --enable=x.y
arg-unknown-ids-many|||check --only a.b --skip c.d --enable e.f --json
arg-unknown-quiet|||update --only zzz --quiet
arg-unknown-pick|||clean --pick clean.x:1 --only chek.disk"

fix_arg_bad_config(){ mkdir -p "$1/.config/macup"; printf 'skip = caf\351\nlanguage = uk\n' >"$1/.config/macup/config"; }   # sed stops at the byte that is not UTF-8

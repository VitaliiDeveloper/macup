# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # SC2034: CASES is read by tests/diff.sh; SC2154: work and the helpers come from it
# Sourced by tests/diff.sh, in name order: the leftovers unit's cases (orphaned agents and app data, the startup section).
# Fake apps (MACUP_APPS), a fake /Library (MACUP_SYSLIB) and a fake codesign (tests/leftovers_fakes.sh). A check of the
# clean tasks on a terminal ends with the pick and stays on bash; a clean on a terminal asks nothing, registers system
# items and containers, and runs on Swift: their sizes, in their own megabytes, reach only the summary's total. The dev
# container scan needs a terminal: with one it stays on bash until the pick.
# shellcheck source=tests/leftovers_fakes.sh
. tests/leftovers_fakes.sh; leftovers_fakes "$work/bin"
lo_env="MACUP_APPS=@H/Apps:@H/Applications MACUP_SYSLIB=@H/SysLib"
lo_tasks=check.startup,clean.orphan_agents,clean.orphan_data
CASES+="
lo-startup|lo|$lo_env|check --only check.startup
lo-startup-json|lo|$lo_env|check --only check.startup --json
lo-startup-quiet|lo|$lo_env|check --only check.startup --quiet|pipe
lo-startup-update|lo|$lo_env|update --only check.startup|pipe
lo-agents|lo|$lo_env|check --only clean.orphan_agents|pipe
lo-data|lo|$lo_env|check --only clean.orphan_data|pipe
lo-check|lo|$lo_env|check --only $lo_tasks|pipe
lo-safe-json|lo|$lo_env|check --level safe --only $lo_tasks --json
lo-standard-json|lo|$lo_env|check --level standard --only $lo_tasks --json
lo-aggressive-json|lo|$lo_env|check --level aggressive --only $lo_tasks --json
lo-clean|lo|$lo_env|clean --only $lo_tasks
lo-clean-agents|lo|$lo_env|clean --only clean.orphan_agents
lo-clean-data|lo|$lo_env|clean --only clean.orphan_data
lo-clean-startup|lo|$lo_env|clean --only check.startup
lo-all-aggressive|lo|$lo_env|all --level aggressive --only $lo_tasks
lo-clean-json|lo|$lo_env|clean --only $lo_tasks --json
lo-app-there|loapp|$lo_env|check --only $lo_tasks|pipe
lo-app-there-clean|loapp|$lo_env|clean --only $lo_tasks
lo-held|loheld|$lo_env|clean --only $lo_tasks
lo-dev|lo|$lo_env|check --only clean.dev_containers,clean.orphan_data|pipe
lo-dev-json|lo|$lo_env|check --only clean.dev_containers,clean.orphan_data --json
lo-none|||check --only $lo_tasks --json
lo-none-clean|||clean --only $lo_tasks"

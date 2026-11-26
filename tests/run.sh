#!/bin/bash
# shellcheck disable=SC2088  # a literal ~ is what users type into the installer
# macup test suite. Everything runs against throwaway fake home folders; the real one is never touched.
#   tests/run.sh                     all tests, on the bash build (./macup)
#   MACUP_BUILD=swift tests/run.sh   on the Swift binary (MACUP_BIN, else .build/debug/macup)
# Every run goes through tests/macup_run, which starts the build under test.
cd "$(dirname "$0")/.." || exit 1
work=$(mktemp -d "${TMPDIR:-/tmp}/macup-tests.XXXXXX"); trap 'rm -rf "$work"' EXIT
failed=0; pass(){ echo "PASS $*"; }; fail(){ echo "FAIL $*"; failed=1; }
export MACUP_BUILD=${MACUP_BUILD:-bash}
case "$MACUP_BUILD" in
  bash)  build_path="$PWD/macup" ;;
  swift) export MACUP_BIN=${MACUP_BIN:-$PWD/.build/debug/macup}; build_path=$MACUP_BIN ;;
  *)     echo "MACUP_BUILD is bash or swift"; exit 2 ;;
esac
[ -f "$build_path" ] || { echo "no $MACUP_BUILD build at $build_path: run ./build.sh"; exit 1; }
echo "testing the $MACUP_BUILD build: $build_path"
# tests that only make sense for the script (its syntax, its own self-update, the installer, the schedule until phase 4)
bash_only(){ [ "$MACUP_BUILD" = bash ] && return 0; echo "SKIP $* (bash build only)"; return 1; }
quick_skip='update.*,clean.brew,clean.npm,clean.pnpm,clean.pip,clean.uv,clean.go,clean.go_mod,clean.sim_unavailable,clean.quicklook,clean.docker,clean.docker_images,clean.docker_containers,clean.brew_autoremove,check.*'

# `running` asks pgrep which apps are open; a fake one answers from FAKE_RUNNING (command lines, one per line), so results never depend on this machine
mkdir -p "$work/bin"; cat >"$work/bin/pgrep" <<'FAKE'
#!/bin/bash
[ "$1" = "-x" ] && { printf '%s\n' "${FAKE_PROCS:-}" | grep -qx -- "$2"; exit; }
[ "$1" = "-f" ] && [ -n "$2" ] && printf '%s\n' "${FAKE_RUNNING:-}" | grep -qE -- "$2"
FAKE
# `lsof` tells which app folders have open files: a fake one lists FAKE_OPEN paths (one per line), or fails with FAKE_LSOF_FAIL
cat >"$work/bin/lsof" <<'FAKE'
#!/bin/bash
[ -n "$FAKE_LSOF_FAIL" ] && exit 1
printf 'p1\nc%s\nn/\n' "${FAKE_LSOF_CMD:-SomeApp}"; printf '%s\n' "${FAKE_OPEN:-}" | sed '/^$/d; s/^/n/'
FAKE
# launchctl and osascript only record what macup asked for: no test loads a LaunchAgent or shows a notification
# (print-disabled is a question, not a change: it answers from FAKE_SHARING and is not recorded)
for tool in launchctl osascript; do printf '#!/bin/bash\n[ "$1" = print-disabled ] && { printf "%%s\\n" "${FAKE_SHARING:-}"; exit 0; }\necho "$*" >>"$HOME/%s.log"\n' "$tool" >"$work/bin/$tool"; done
ln -s "$PWD/tests/macup_run" "$work/bin/macup_run"
chmod +x "$work/bin/pgrep" "$work/bin/lsof" "$work/bin/launchctl" "$work/bin/osascript"; export PATH="$work/bin:$PATH"
deleted(){ # fixture-dir macup-args… → files the run deleted
  local home=$1; shift; tests/fixture.sh "$home"; (cd "$home" && find . \( -type f -o -type l \) | sort) >"$home.b"
  env HOME="$home" macup_run "$@" </dev/null >"$home.out" 2>&1
  (cd "$home" && find . \( -type f -o -type l \) | sort) >"$home.a"
  comm -23 "$home.b" "$home.a" | grep -v -e '^./Library/Logs/macup/' -e '^./Library/Application Support/macup/'
}

. tests/cases/basics.sh
. tests/cases/pick_simulators.sh
. tests/cases/commands_uninstall.sh
. tests/cases/runs_dev_containers.sh
. tests/cases/system_schedule_install.sh
. tests/cases/own_files_json.sh
. tests/cases/stale_busy_docker.sh
. tests/cases/tools_misc.sh

# --- leftovers of deleted apps
tests/leftovers.sh || failed=1

echo; [ $failed = 0 ] && echo "ALL PASS" || { echo "SOME FAILED"; exit 1; }

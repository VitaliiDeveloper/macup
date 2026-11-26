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
# shellcheck disable=SC2034  # read by tests/cases/*.sh
quick_skip='update.*,clean.brew,clean.npm,clean.pnpm,clean.pip,clean.uv,clean.go,clean.go_mod,clean.sim_unavailable,clean.quicklook,clean.docker,clean.docker_images,clean.docker_containers,clean.brew_autoremove,check.*'

# shellcheck source=tests/fakes.sh
. tests/fakes.sh
fakes "$work/bin" pgrep lsof launchctl osascript
ln -s "$PWD/tests/macup_run" "$work/bin/macup_run"
export PATH="$work/bin:$PATH"
deleted(){ # fixture-dir macup-args… → files the run deleted
  local home=$1; shift; tests/fixture.sh "$home"; (cd "$home" && find . \( -type f -o -type l \) | sort) >"$home.b"
  env HOME="$home" macup_run "$@" </dev/null >"$home.out" 2>&1
  (cd "$home" && find . \( -type f -o -type l \) | sort) >"$home.a"
  comm -23 "$home.b" "$home.a" | grep -v -e '^./Library/Logs/macup/' -e '^./Library/Application Support/macup/'
}
# keeps the fake terminal open until macup has written its report (slow machines need longer than a fixed sleep)
until_done(){ local tries=0; while [ $tries -lt 240 ]; do grep -qE 'Report: |Звіт: |Отчёт: ' "$1" 2>/dev/null && return; sleep 0.5; tries=$((tries + 1)); done; }
jq(){ python3 -c "import json,sys; data=json.load(open(sys.argv[1])); $2" "$1"; }   # file, python that reads data

for case_file in basics pick_simulators commands_uninstall runs_dev_containers system_schedule_install own_files_json stale_busy_docker tools_misc; do   # the order the suite has always run in
  # shellcheck source=/dev/null
  if [ -f "tests/cases/$case_file.sh" ]; then . "tests/cases/$case_file.sh"; else fail "tests/cases/$case_file.sh is missing"; fi
done

# --- leftovers of deleted apps
tests/leftovers.sh || failed=1

echo; [ $failed = 0 ] && echo "ALL PASS" || { echo "SOME FAILED"; exit 1; }

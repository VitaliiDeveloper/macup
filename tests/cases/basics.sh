# shellcheck shell=bash
# shellcheck disable=SC2154  # SC2154: work, quick_skip, build_path and the helpers come from tests/run.sh
# Sourced by tests/run.sh: static checks, commands, check and clean levels, AI tools, open apps.
# --- static
./build.sh --check >/dev/null 2>&1 && pass "the translations, macup.sha256 and the package are current" || fail "out of date: run ./build.sh"
# the root macup is the bootstrap 2.9 copies update to: stock bash 3.2 must read it, as it must read the installer
/bin/bash -n macup && /bin/bash -n install.sh && pass "bash 3.2 syntax of the bootstrap and the installer" || fail syntax
if command -v shellcheck >/dev/null; then shellcheck -s bash -S warning macup install.sh && pass shellcheck || fail shellcheck; fi
# the binary runs everything itself: no bash inside it, only the two marker lines install.sh and uninstall look for
! LC_ALL=C grep -aqE '^(load_conf|exec_cand|run_key|leftovers_scan)\(\)\{' "$build_path" && LC_ALL=C grep -a -A1 -x '# macup' "$build_path" | grep -qx "MACUP_VERSION=\"$(sed -n 's/^MACUP_VERSION="\(.*\)"$/\1/p' macup)\"" \
  && pass "the binary carries no bash, and its marker names the bootstrap's version" || fail "the binary carries bash, or its marker does not name the bootstrap's version"

# --- nothing changes without a command
home="$work/h"; mkdir -p "$home"
for args in "" "--no-color" "--lang uk" "--level aggressive" "--skip check.docker"; do
  env HOME="$home" macup_run $args </dev/null >"$work/o" 2>&1; rc=$?
  [ $rc = 2 ] && grep -q 'macup check' "$work/o" && pass "no command '$args' prints help" || fail "no command '$args' (rc=$rc)"
done
env HOME="$home" macup_run --lang xx check </dev/null >/dev/null 2>&1; [ $? = 2 ] && pass "bad --lang" || fail "bad --lang"
env HOME="$home" macup_run --level huge clean </dev/null >/dev/null 2>&1; [ $? = 2 ] && pass "bad --level" || fail "bad --level"
env HOME="$home" macup_run bogus </dev/null >/dev/null 2>&1; [ $? = 1 ] && pass "unknown command" || fail "unknown command"
env HOME="$home" macup_run --deep --no-color --only check.system </dev/null 2>/dev/null | head -1 | grep -q 'check+deep' && pass "--deep alone is a check" || fail "--deep alone"
env HOME="$home" macup_run help --lang ru </dev/null | head -1 | grep -q 'уход за Маком' && pass "help --lang ru" || fail "help --lang ru"

# --- a non-interactive check deletes nothing, in every language, without errors
for lang in en uk ru; do   # the full set of checks once; the translations with the quick ones
  if [ $lang = en ]; then sk='update.*,check.macos_updates'; else sk="$quick_skip"; fi
  removed=$(deleted "$work/c$lang" check --lang $lang --no-color --skip "$sk")
  [ -z "$removed" ] && [ -z "$(grep -E 'line [0-9]+:|command not found|integer expression|unbound' "$work/c$lang.out")" ] && pass "check $lang: no errors, nothing deleted" || { fail "check $lang"; echo "$removed" | head -3; grep -E 'line [0-9]+:' "$work/c$lang.out" | head -3; }
done

# --- each level deletes exactly its set; data, secrets, pins and symlink targets always survive
exp=""; for lv in safe standard aggressive; do
  exp=$(printf '%s\n%s' "$exp" "$(cat tests/expect-$lv.txt)" | grep . | sort)
  got=$(deleted "$work/l$lv" clean --level $lv --skip "$quick_skip" --no-color)
  [ "$got" = "$(echo "$exp")" ] && pass "clean --level $lv deletes exactly the expected files" || { fail "clean --level $lv"; diff <(echo "$exp") <(echo "$got") | head; }
done
echo "$got" | grep -E 'codex/sessions|sqlite|gradle.properties|settings.xml|avd|debug.keystore|adbkey|/User/|Backups|Login Data|/History|/Cookies|QtApp|ShipIt|sparkle|Local Storage|elsewhere|Archives|Downloads|Documents|BigApp|com.apple|\.Trash|Code/old|3\.12\.1|3\.13\.1|3\.10\.2|v22\.1\.0|\.m2/|virtualenvs|v21\.2\.5|v21\.7\.0|v23\.|registry/index|location_data|Code/(rs|plain)' \
  && fail "protected files deleted" || pass "protected files survive --level aggressive"
[ -f "$work/laggressive/elsewhere2/big" ] && [ -f "$work/laggressive/elsewhere/precious" ] && [ -f "$work/laggressive/elsewhere3/Cache/big" ] && pass "symlinked cache targets survive" || fail "symlink target deleted"
aggressive_home="$work/laggressive"   # AI tools: what is not a pure cache goes to the Trash; transcripts, live state, the plugin in use and other workspaces stay
[ -f "$aggressive_home/.Trash/bbbb-2222/blob" ] && [ -f "$aggressive_home/.Trash/plugins-backup-Ab12Cd/repo/blob" ] && [ -f "$aggressive_home/.Trash/..codex-global-state.json.tmp-1784380121760-c8bf" ] && pass "AI tools: backups and unfinished writes go to the Trash" || fail "AI tools: Trash"
[ -f "$aggressive_home/.claude/projects/-Users-me-app/aaaa-1111.jsonl" ] && [ -f "$aggressive_home/.claude/file-history/aaaa-1111/blob" ] && [ -f "$aggressive_home/.claude/file-history/cccc-3333/blob" ] && [ -f "$aggressive_home/.claude/history.jsonl" ] \
  && [ -f "$aggressive_home/.claude/plugins/cache/mkt/plug/0.8.0/blob" ] && [ -f "$aggressive_home/.claude/plugins/cache/mkt/plug/1.0.0/blob" ] && [ -f "$aggressive_home/.claude/plugins/cache/mkt/plug/1.0.1/blob" ] \
  && [ -f "$aggressive_home/.grok/downloads/grok-1.0.92-macos-aarch64" ] && [ -f "$aggressive_home/.grok/downloads/grok-1.0.93-macos-aarch64" ] && [ -f "$aggressive_home/.codex/.codex-global-state.json" ] && [ -f "$aggressive_home/.codex/cache/remote_plugin_catalog/fresh.json" ] \
  && [ -f "$aggressive_home/Library/Application Support/Code/User/workspaceStorage/abc123/state.vscdb" ] && pass "AI tools: sessions, versions in use and workspaces survive --level aggressive" || fail "AI tools: something in use was deleted"
home="$work/ai"; tests/fixture.sh "$home"
FAKE_RUNNING="$home/.local/share/claude/versions/2.1.332" env HOME="$home" macup_run clean --only clean.ai_tools --no-color </dev/null >"$work/ai.out" 2>&1
[ -f "$home/.claude/file-history/bbbb-2222/blob" ] && [ ! -f "$home/.grok/downloads/grok-1.0.89-macos-aarch64" ] && grep -q 'Claude Code edit backups.*skipped' "$work/ai.out" \
  && pass "AI tools: Claude Code's leftovers wait while it runs" || fail "AI tools: cleaned while Claude Code runs"
tests/fixture.sh "$home"   # a check counts what would go to the Trash apart from what it frees
env HOME="$home" macup_run check --only clean.ai_tools --no-color </dev/null >"$work/ai.out" 2>&1
grep -q 'Would move to the Trash: ~4 MB' "$work/ai.out" && grep -q 'Could free: ~2[0-9] MB' "$work/ai.out" && pass "AI tools: a check counts the Trash apart" || { fail "AI tools: Trash total"; grep -E 'Could free|Trash' "$work/ai.out"; }
H2="$work/ai2"; mkdir -p "$H2/.codex/.tmp"; for index in $(seq 1 60); do mkdir -p "$H2/.codex/.tmp/git-$index/refs"; echo ref >"$H2/.codex/.tmp/git-$index/HEAD"; done; find "$H2/.codex/.tmp" -exec touch -t 202401010000 {} +
env HOME="$H2" macup_run clean --only clean.ai_tools --no-color </dev/null >"$work/ai2.out" 2>&1
[ -z "$(ls "$H2/.codex/.tmp")" ] && pass "AI tools: many tiny stale Codex git clones go though they are small" || fail "AI tools: tiny git clones stayed"
tests/fixture.sh "$home"
FAKE_RUNNING='/Applications/ChatGPT.app/Contents/MacOS/ChatGPT' env HOME="$home" macup_run clean --only clean.ai_tools --no-color </dev/null >"$work/ai.out" 2>&1
[ -f "$home/.codex/.tmp/plugins-backup-Ab12Cd/repo/blob" ] && [ -f "$home/.codex/.tmp/git-abc/blob" ] && [ ! -f "$home/.claude/file-history/bbbb-2222/blob" ] && pass "AI tools: Codex's leftovers wait while ChatGPT.app runs" || fail "AI tools: cleaned while ChatGPT.app runs"

# --- an app that is open is skipped, and the summary says so
home="$work/run"; tests/fixture.sh "$home"
FAKE_RUNNING='/Applications/Cursor.app/Contents/MacOS/Cursor' env HOME="$home" macup_run clean --skip "$quick_skip" --no-color </dev/null >"$work/run.out" 2>&1
[ -f "$home/Library/Application Support/Cursor/Cache/c/blob" ] && grep -q 'Cursor caches.*skipped' "$work/run.out" && pass "open app is skipped" || fail "open app was cleaned"
grep -q 'Skipped because the app is open (1)' "$work/run.out" && grep -q '    · Cursor caches' "$work/run.out" && pass "summary lists what was skipped" || fail "summary does not list the skipped app"
grep -q 'Needs attention: nothing' "$work/run.out" && pass "a skipped app is not a warning" || fail "skipped app became a warning"
tests/fixture.sh "$home"   # Application Support/Codex is used by ChatGPT.app, not Codex.app
FAKE_RUNNING="/Applications/ChatGPT.app/Contents/Frameworks/Codex Framework.framework/Helpers/Codex (Service).app/Contents/MacOS/Codex (Service) --type=gpu-process --user-data-dir=$home/Library/Application Support/Codex --standard-schemes" \
  env HOME="$home" macup_run clean --only clean.editors --no-color </dev/null >"$work/run.out" 2>&1
[ -f "$home/Library/Application Support/Codex/Default/Partitions/browser/Code Cache/js/blob" ] && [ ! -f "$home/Library/Application Support/Claude/Cache/c/blob" ] \
  && pass "an app open under another name is skipped by its --user-data-dir" || fail "app open under another name was cleaned"
tests/fixture.sh "$home"   # an app macup has no name for: open while it has files open in its folder; unknown when lsof fails
FAKE_OPEN="$home/Library/Application Support/SomeApp/Cookies" env HOME="$home" macup_run clean --only clean.editors --no-color </dev/null >"$work/run.out" 2>&1
[ -f "$home/Library/Application Support/SomeApp/Cache/c/blob" ] && [ -f "$home/Library/Caches/SomeApp/Default/Cache/blob" ] && grep -q 'SomeApp caches.*skipped' "$work/run.out" \
  && [ ! -f "$home/Library/Application Support/Claude/Cache/c/blob" ] && pass "an unknown app with open files is skipped" || fail "an unknown open app was cleaned"
tests/fixture.sh "$home"   # macOS's UserEventAgent keeps app folders open whether or not the app runs
FAKE_LSOF_CMD=UserEventAgent FAKE_OPEN="$home/Library/Application Support/SomeApp/Cookies" env HOME="$home" macup_run clean --only clean.editors --no-color </dev/null >"$work/run.out" 2>&1
[ ! -f "$home/Library/Application Support/SomeApp/Cache/c/blob" ] && pass "a folder only macOS's watchers hold open is not in use" || fail "UserEventAgent's open folder kept an app's cache"
tests/fixture.sh "$home"
FAKE_LSOF_FAIL=1 env HOME="$home" macup_run clean --only clean.editors --no-color </dev/null >"$work/run.out" 2>&1
[ -f "$home/Library/Application Support/SomeApp/Cache/c/blob" ] && [ ! -f "$home/Library/Application Support/Claude/Cache/c/blob" ] \
  && pass "lsof fails: unknown apps are left alone, known ones still cleaned" || fail "lsof failed and an unknown app was cleaned"


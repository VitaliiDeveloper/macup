#!/bin/bash
# Programs left running (clean.stray_processes) and Claude Code sessions open in the Claude app (check.memory).
# A fake ps gives a process table taken from a real Mac; the stopping is tested on real processes this script starts.
# tests/run.sh calls it.
cd "$(dirname "$0")/.." || exit 1
W=$(mktemp -d "${TMPDIR:-/tmp}/macup-processes.XXXXXX")
STARTED=""; stop_started(){ local p; for p in $STARTED; do pkill -KILL -P "$p" 2>/dev/null; kill -KILL "$p" 2>/dev/null; done; }
trap 'stop_started; rm -rf "$W"' EXIT
F=0; pass(){ echo "PASS $*"; }; fail(){ echo "FAIL $*"; F=1; }
M="$PWD/macup"; U=$(id -u)

# --- the table of a Mac after two days: apps, their helpers, launchd's jobs, Claude sessions, and one test run whose tool quit
# (what is offered has a pid no Mac gives out, above 99999: a pick stops nothing real)
mkdir -p "$W/fake" "$W/h/.config/macup"; printf 'language = en\n' >"$W/h/.config/macup/config"
T='Wed_Nov_25_20:04:15_2026'
cat >"$W/table" <<EOF
1 0 0 19472 1:00.00 02-19:28:17 ?? $T /sbin/launchd
820 1 $U 32464 0:10.00 02-19:27:44 ?? $T /Applications/Translatium.app/Contents/MacOS/Translatium
1679 1 $U 3104 0:01.00 02-19:26:51 ?? $T /Library/Developer/PrivateFrameworks/CoreSimulator.framework/Versions/A/XPCServices/com.apple.CoreSimulator.CoreSimulatorService.xpc/Contents/MacOS/com.apple.CoreSimulator.CoreSimulatorService
9712 1 $U 481104 9:00.00 02-19:00:18 ?? $T /Applications/Claude.app/Contents/MacOS/Claude
9715 1 $U 4672 0:01.00 02-19:00:18 ?? $T /Applications/Claude.app/Contents/Frameworks/Electron Framework.framework/Helpers/chrome_crashpad_handler --no-rate-limit
20396 9712 $U 1000 0:00.01 02-01:49:02 ?? $T /Applications/Claude.app/Contents/Helpers/disclaimer --pgroup -- /Users/me/Library/Application Support/Claude/claude-code/2.1.330/4262a1273231/claude.app/Contents/MacOS/claude --output-format stream-json --verbose
20397 20396 $U 100000 10:47.56 02-01:49:02 ?? $T /Users/me/Library/Application Support/Claude/claude-code/2.1.330/4262a1273231/claude.app/Contents/MacOS/claude --output-format stream-json --verbose --input-format stream-json
20500 20397 $U 50000 0:01.00 02-01:40:00 ?? $T node /Users/me/.npm/_npx/6583fba12287d067/node_modules/.bin/mcp-pdf-server --stdio
23770 9712 $U 1000 0:00.01 05:00:00 ?? $T /Applications/Claude.app/Contents/Helpers/disclaimer --pgroup -- /Users/me/Library/Application Support/Claude/claude-code/2.1.330/4262a1273231/claude.app/Contents/MacOS/claude --output-format stream-json
23771 23770 $U 150000 1:00.00 05:00:00 ?? $T /Users/me/Library/Application Support/Claude/claude-code/2.1.330/4262a1273231/claude.app/Contents/MacOS/claude --output-format stream-json --verbose
26402 1 $U 13216 0:01.00 01-18:38:05 ?? $T /Applications/Folder Preview.app/Contents/PlugIns/Folder Preview Extension.appex/Contents/MacOS/Folder Preview Extension
27374 1 $U 240 0:00.01 02-18:12:00 ?? $T /usr/bin/ssh-agent -l
57046 9712 $U 672 0:00.00 01-22:13:15 ?? $T /Applications/Claude.app/Contents/Helpers/disclaimer -- xcrun simctl spawn 11635C7D notifyutil -v -w com.apple.backboardd.orientation
57050 57046 $U 608 0:00.33 01-22:13:15 ?? $T /Library/Developer/PrivateFrameworks/CoreSimulator.framework/Versions/A/Resources/bin/simctl spawn 11635C7D notifyutil -v
68811 1 $U 60496 5:00.00 01-23:13:43 ?? $T /Applications/Visual Studio Code.app/Contents/MacOS/Code
193156 1 $U 1000 0:00.10 01-18:19:09 ?? $T script -q /dev/null env HOME=/var/folders/xx/T/macup-diff.geitFK/home MACUP_LANG=en tests/macup_run tasks
193160 193156 $U 704 0:00.25 01-18:19:09 ttys002 $T /bin/bash /Users/me/macup/macup tasks
172311 193160 $U 336 0:00.00 01-18:08:48 ttys002 $T /bin/bash /Users/me/macup/macup tasks
172313 172311 $U 320 0:00.00 01-18:08:48 ttys002 $T /bin/bash /Users/me/macup/macup tasks
5000 1 $U 2000 0:00.10 20:00 ?? $T /usr/local/bin/node server.js
5100 1 $U 2000 0:00.10 03-00:00:00 ?? $T /opt/homebrew/bin/tmux new-session -d
5200 1 0 2000 0:00.10 03-00:00:00 ?? $T /usr/local/bin/rootthing
5300 1 $U 9000 0:00.10 02-00:00:00 ttys009 $T /opt/homebrew/bin/python3 watcher.py
5301 777 $U 1000 0:00.10 02-00:00:00 ttys009 $T -zsh
5500 1 $U 1000 0:00.10 03-00:00:00 ?? $T SCREEN -S work
5501 1 $U 1000 0:00.10 03-00:00:00 ?? $T ssh: /Users/me/.ssh/cm-git@github.com:22 [mux]
5502 1 $U 90000 0:00.10 03-00:00:00 ?? $T /Library/Java/JavaVirtualMachines/jdk-21.jdk/Contents/Home/bin/java -Xmx2g -cp gradle-daemon-main.jar org.gradle.launcher.daemon.bootstrap.GradleDaemon 8.10
5503 1 $U 1000 0:00.10 03-00:00:00 ?? $T adb -L tcp:5037 fork-server server --reply-fd 4
5504 1 $U 1000 0:00.10 03-00:00:00 ?? $T git fsmonitor--daemon run --detach --ipc-threads=8
5505 1 $U 1000 0:00.10 03-00:00:00 ?? $T /opt/homebrew/opt/postgresql@16/bin/postgres -D /opt/homebrew/var/postgresql@16
105400 1 $U 40000 0:00.10 01-00:00:00 ?? $T /opt/homebrew/bin/node /Users/me/.npm/_npx/abc/node_modules/.bin/mcp-server-git --stdio
EOF
# ps: the table above for macup's question, the real ps for anything else; launchctl knows ssh-agent; lsof gives a folder
printf '#!/bin/bash\ncase "$*" in *lstart*) cat "%s" | awk %s ;; *) exec /bin/ps "$@" ;; esac\n' "$W/table" "'{ \$8 = substr(\$8,1,3) \" \" substr(\$8,5,3) \" \" substr(\$8,9,2) \" \" substr(\$8,12,8) \" \" substr(\$8,21); print }'" >"$W/fake/ps"
printf '#!/bin/bash\n[ "$1" = list ] && printf "PID\\tStatus\\tLabel\\n27374\\t0\\tcom.openssh.ssh-agent\\n-\\t0\\tcom.example.idle\\n"\nexit 0\n' >"$W/fake/launchctl"
printf '#!/bin/bash\nprintf "p1\\nfcwd\\nn/Users/me/work\\n"\n' >"$W/fake/lsof"
chmod +x "$W/fake/"*
env HOME="$W/h" PATH="$W/fake:$PATH" /bin/bash "$M" check --only check.memory,clean.stray_processes --no-color </dev/null >"$W/t.out" 2>&1
got=$(tr -d '\r' <"$W/t.out" | grep -E '^ +[0-9]+  ' | sed 's/  */ /g')
[ "$got" = "$(printf '%s\n' " 1 aggressive script · left running for 1 d (2 MB of memory) (only if you pick it)" " 2 aggressive mcp-server-git · left running for 1 d (41 MB of memory) (only if you pick it)")" ] \
  && grep -q 'Programs left running after what started them quit — found 2' "$W/t.out" && grep -q 'It started 3 more processes; they stop with it.' "$W/t.out" \
  && pass "left running: a test run and an MCP server whose tool quit; not apps, their helpers, launchd's jobs, tmux, screen, an ssh master, detached dev servers, another user's, a young one, one in an open terminal" \
  || { fail "left running"; cat "$W/t.out"; }
grep -q 'Claude Code sessions open in the Claude app for a day or more: 1, 154 MB of memory$' "$W/t.out" && grep -q '/Users/me/work · 2 d · 154 MB' "$W/t.out" \
  && pass "Claude sessions: one open for two days (with what it started), not the one open for five hours" || { fail "Claude sessions"; cat "$W/t.out"; }
env HOME="$W/h" PATH="$W/fake:$PATH" /bin/bash "$M" check --only check.memory,clean.stray_processes --json </dev/null >"$W/t.json" 2>/dev/null
python3 -c 'import json,sys; c=[x for x in json.load(open(sys.argv[1]))["cleanable"] if x["task"]=="clean.stray_processes"]; assert len(c)==2 and all(x["kb"]==0 and x["opt_in"] and not x["in_clean"] for x in c), c' "$W/t.json" \
  && pass "--json: listed with a key, nothing on disk, never in a plain clean" || { fail "--json"; cat "$W/t.json"; }

# --- real processes: a script that started another, its tool gone (its own session, no terminal)
mkdir -p "$W/p/.config/macup"; printf 'language = en\n' >"$W/p/.config/macup/config"
printf '#!/bin/bash\nsleep 300 &\nsleep 301\n' >"$W/stray-test.sh"
( perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV' /bin/bash "$W/stray-test.sh" </dev/null >/dev/null 2>&1 & echo $! >"$W/pid" )
sleep 2; P=$(cat "$W/pid"); STARTED="$P"
[ "$(ps -o ppid= -p "$P" | tr -d ' ')" = 1 ] || fail "test setup: the script is not left to launchd"
key(){ env HOME="$W/p" MACUP_STRAY_SECS=1 /bin/bash "$M" check --only clean.stray_processes --json </dev/null 2>/dev/null |
  python3 -c 'import json,sys; print(" ".join(x["key"] for x in json.load(sys.stdin)["cleanable"] if x["text"].startswith("stray-test.sh ·")))'; }
K=$(key)
[ -n "$K" ] && pass "a real script whose tool quit is listed by its name" || fail "real script not listed"
env HOME="$W/p" MACUP_STRAY_SECS=1 /bin/bash "$M" clean --only clean.stray_processes --level aggressive </dev/null >"$W/c.out" 2>&1
kill -0 "$P" 2>/dev/null && pass "a plain clean never stops it" || fail "a plain clean stopped a program"
env HOME="$W/p" MACUP_STRAY_SECS=1 /bin/bash "$M" clean --enable clean.stray_processes --only clean.stray_processes --level aggressive </dev/null >"$W/c.out" 2>&1
kill -0 "$P" 2>/dev/null && pass "enable does not make it automatic" || fail "enable stopped a program"
KIDS=$(ps -Ao pid=,ppid= | awk -v p="$P" '$2 == p { print $1 }' | paste -sd, -)   # not pgrep: tests/run.sh puts a fake one first
env HOME="$W/p" MACUP_STRAY_SECS=1 /bin/bash "$M" clean --pick "$K" --no-color </dev/null >"$W/c.out" 2>&1; rc=$?
sleep 1
[ $rc = 0 ] && [ -n "$KIDS" ] && ! kill -0 "$P" 2>/dev/null && [ -z "$(ps -o pid= -p "$KIDS" 2>/dev/null)" ] && grep -q 'stray-test.sh · left running for .*: stopped' "$W/c.out" \
  && pass "--pick stops it and what it started" || { fail "--pick (rc=$rc)"; cat "$W/c.out"; }
env HOME="$W/p" MACUP_STRAY_SECS=1 /bin/bash "$M" clean --pick "$K" --no-color </dev/null >"$W/c.out" 2>&1; rc=$?
[ $rc = 3 ] && grep -q 'no longer there' "$W/c.out" && pass "--pick of one that is gone: said, nothing else stopped" || { fail "--pick again (rc=$rc)"; cat "$W/c.out"; }

# --- a process whose start differs is another process under the same pid: never stopped
( perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV' /bin/bash "$W/stray-test.sh" </dev/null >/dev/null 2>&1 & echo $! >"$W/pid" )
sleep 2; P=$(cat "$W/pid"); STARTED="$STARTED $P"
env HOME="$W/p" MACUP_STRAY_SECS=1 /bin/bash "$M" clean --pick "clean.stray_processes:$(printf '%s' "cmd|proc:$P:Thu_Jan__1_00:00:00_1970" | cksum | cut -d' ' -f1)" --no-color </dev/null >"$W/c.out" 2>&1
kill -0 "$P" 2>/dev/null && pass "a key with another start time stops nothing" || fail "stopped a process by pid alone"

# --- picked after an interactive check: by its own number and a yes; a range never takes it (the table above)
until_done(){ local i=0; while [ $i -lt 240 ]; do grep -q 'Report: ' "$1" 2>/dev/null && return; sleep 0.5; i=$((i + 1)); done; }
ask(){ (sleep 2; printf '%s\n' "$1"; sleep 1; printf '%s\n' "${2:-}"; until_done "$W/i.out") | script -q /dev/null env HOME="$W/h" PATH="$W/fake:$PATH" /bin/bash "$M" check --only clean.stray_processes --no-color >"$W/i.out" 2>&1; }
ask '1-3' y; ! grep -q ': stopped' "$W/i.out" && pass "pick: a range never takes a program left running" || { fail "pick: a range"; cat "$W/i.out"; }
ask 1 n; ! grep -q ': stopped' "$W/i.out" && pass "pick: no to the question stops nothing" || { fail "pick: no"; cat "$W/i.out"; }
ask 1 y; grep -q 'The picked programs are stopped' "$W/i.out" && grep -q 'script · left running for 1 d (2 MB of memory): stopped' "$W/i.out" && ! grep -q 'mcp-server-git.*stopped' "$W/i.out" \
  && pass "pick: its number and a yes stop it, and only it" || { fail "pick: number and yes"; cat "$W/i.out"; }
! grep -q 'line [0-9]*:' "$W/i.out" "$W/t.out" && pass "no shell errors" || { fail "shell errors"; grep 'line [0-9]*:' "$W/i.out" "$W/t.out" | head -3; }

# --- macup inside such a program (a test harness, a script): that one is never offered
( perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV' /bin/bash "$W/stray-test.sh" </dev/null >/dev/null 2>&1 & echo $! >"$W/pid" )
sleep 2; STARTED="$STARTED $(cat "$W/pid")"
cat >"$W/runs-macup.sh" <<EOF
#!/bin/bash
sleep 2
env HOME="$W/p" MACUP_STRAY_SECS=1 /bin/bash "$M" check --only clean.stray_processes --json </dev/null >"$W/self.json" 2>/dev/null
EOF
( perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV' /bin/bash "$W/runs-macup.sh" </dev/null >/dev/null 2>&1 & )
i=0; until [ -s "$W/self.json" ] || [ $i -gt 120 ]; do sleep 0.5; i=$((i + 1)); done; sleep 0.5
python3 -c 'import json,sys; t=[x["text"] for x in json.load(open(sys.argv[1]))["cleanable"]]; assert not [x for x in t if x.startswith("runs-macup.sh")] and [x for x in t if x.startswith("stray-test.sh")], t' "$W/self.json" \
  && pass "the program macup runs inside is never offered" || { fail "macup offered its own parent"; cat "$W/self.json"; }

exit $F

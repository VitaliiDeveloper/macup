# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # SC2034: CASES is read by tests/diff.sh; SC2154: work, build and the helpers come from it
# Sourced by tests/diff.sh, in name order: the checks unit.
# checks unit: the system tools answer from FAKE_* (tests/checks_fakes.sh); FAKE_SYSTEM=1 turns them on
# shellcheck source=tests/checks_fakes.sh
. tests/checks_fakes.sh; checks_fakes "$work/bin"
CASES="$CASES
chk-system||FAKE_SYSTEM=1|check --only check.system,check.memory,check.cpu,check.battery
chk-system-json||FAKE_SYSTEM=1 FAKE_BATT=83%|check --only check.system,check.memory,check.cpu,check.battery --json
chk-system-warn||FAKE_SYSTEM=1 FAKE_UP_DAYS=20 FAKE_UPTIME=4:05 FAKE_MEMFREE=9 FAKE_SWAP_USED=7.5G FAKE_LOAD=13.00 FAKE_THERM=CPU_Speed_Limit=80 FAKE_BATT=83% FAKE_CAPACITY=76%|check --only check.system,check.memory,check.cpu,check.battery
chk-system-odd||FAKE_SYSTEM=1 FAKE_MEMFREE= FAKE_SWAP_USED=x FAKE_LOAD=busy FAKE_CORES=x FAKE_MODEL= FAKE_BATT=55% FAKE_CONDITION=Service FAKE_CYCLES= FAKE_CAPACITY=|check --only check.system,check.memory,check.cpu,check.battery
chk-trends|historyfilling|FAKE_SYSTEM=1 FAKE_BATT=83% FAKE_CYCLES=650 FAKE_CAPACITY=76% FAKE_SWAP_USED=3.5G|check --only check.trends,check.memory,check.battery
chk-security||FAKE_SYSTEM=1 FAKE_TM_DEST=Backup FAKE_TM_DAYS=2|check --only check.security
chk-security-off||FAKE_SYSTEM=1 FAKE_FILEVAULT=Off FAKE_SIP=disabled FAKE_GATEKEEPER=disabled FAKE_AUTO_CHECK=0 FAKE_TM_DEST=Backup FAKE_TM_DAYS=30 FAKE_PROCS=ARDAgent|check --only check.security
chk-security-none||FAKE_SYSTEM=1 FAKE_FILEVAULT= FAKE_SIP= FAKE_GATEKEEPER= FAKE_CRITICAL=0|check --only check.security
chk-security-tm-unknown||FAKE_SYSTEM=1 FAKE_TM_DEST=Backup|check --only check.security --json
chk-security-skip-tm||FAKE_SYSTEM=1|check --only check.security --skip check.time_machine
chk-sizes|sizes|FAKE_SYSTEM=1|check --only check.sizes,check.creative
chk-sizes-update|sizes|FAKE_SYSTEM=1|update --only check.sizes
chk-deep|deep|FAKE_SYSTEM=1|check --deep --only check.disk
chk-deep-update|deep|FAKE_SYSTEM=1|update --deep --only check.sizes --json
chk-deep-no-roots|||check --deep --only check.disk
chk-deep-no-artifacts|emptycode||check --deep --only check.disk"
big(){ [ -f "$work/big" ] || dd if=/dev/zero of="$work/big" bs=1048576 count=101 2>/dev/null; mkdir -p "$(dirname "$1")"; cp -c "$work/big" "$1"; }   # a clone takes no space
fix_sizes(){ local dev="$1/Library/Developer" support="$1/Library/Application Support"
  blob "$dev/Xcode/Archives/App.xcarchive" 1024; blob "$dev/CoreSimulator/Devices/ABC" 512; blob "$1/.pub-cache" 64; blob "$1/Library/Caches/Some" 256
  blob "$1/.codex/sessions" 16; big "$1/.codex/state.sqlite"; big "$1/.codex/.hidden.sqlite"; blob "$1/.claude/projects" 32; blob "$1/.Trash" 128
  big "$1/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw"; big "$1/elsewhere/vm"; ln -s "$1/elsewhere" "$1/.lima"
  big "$1/Library/Caches/Adobe Camera Raw 2/cache"; blob "$support/Adobe/Common/Media Cache" 64; }
fix_deep(){ local support="$1/Library/Application Support"
  blob "$1/Code/web/node_modules/left-pad" 256; blob "$1/Code/rs/target/debug" 512; echo '[package]' >"$1/Code/rs/Cargo.toml"; blob "$1/Code/plain/target/data" 64
  blob "$support/Alpha" 64; blob "$support/beta" 64; blob "$1/dev/tool" 64; blob "$1/.hidden" 32; blob "$1/..dots" 32
  blob "$1/Downloads/old" 128; touch -t 202001010000 "$1/Downloads/old"; blob "$1/Downloads/new" 64
  dd if=/dev/zero of="$1/Downloads/disk.img" bs=1 count=0 seek=1100m 2>/dev/null; }   # sparse: over 1 GB, taking nothing
fix_emptycode(){ mkdir -p "$1/Code/notes"; }

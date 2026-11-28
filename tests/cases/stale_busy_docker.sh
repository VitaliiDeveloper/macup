# shellcheck shell=bash
# shellcheck disable=SC2154  # SC2154: work, quick_skip, build_path and the helpers come from tests/run.sh
# Sourced by tests/run.sh: stale build folders, caches in use, Docker.
# --- stale build folders (opt-in): only next to their build file, never tracked by git, never built recently
home="$work/art"; tests/fixture.sh "$home"; code="$home/Code"
blob(){ mkdir -p "$1"; dd if=/dev/zero of="$1/blob" bs=1024 count=6144 2>/dev/null; }; old(){ find "$@" -exec touch -t 202401010000 {} +; }
blob "$code/oldrs/target/debug"; echo '[package]' >"$code/oldrs/Cargo.toml"; mkdir -p "$code/oldrs/src"; echo 'fn main(){}' >"$code/oldrs/src/main.rs"
blob "$code/oldplain/target/data"; echo notes >"$code/oldplain/readme"                      # no Cargo.toml: someone's data
blob "$code/oldpods/Pods/Lib"; echo "pod 'Lib'" >"$code/oldpods/Podfile"                      # committed Pods
blob "$code/oldswift/.build/debug"; echo '// swift' >"$code/oldswift/Package.swift"
blob "$code/built/target/debug"; echo '[package]' >"$code/built/Cargo.toml"                  # old sources, built yesterday
blob "$code/oldvenv/.venv/lib"; echo x >"$code/oldvenv/requirements.txt"                     # a venv may hold packages no file lists
blob "$code/.hidden/proj/target/debug"; echo '[package]' >"$code/.hidden/proj/Cargo.toml"
if command -v git >/dev/null; then (cd "$code/oldpods" && git init -q . && git add -A && git -c user.name=t -c user.email=t@t commit -qm x) >/dev/null 2>&1; fi
for dir in oldrs oldplain oldpods oldswift oldvenv .hidden; do old "$code/$dir"; done; old "$code/built/Cargo.toml"
(cd "$home" && find . -type f | sort) >"$home.b"
env HOME="$home" macup_run check --only clean.stale_artifacts --no-color </dev/null >"$work/art.out" 2>&1
grep -q 'Stale build folders (2, .*(only if you pick it)' "$work/art.out" && [ -d "$code/oldrs/target" ] && pass "stale build folders: listed by a check, only when picked" || { fail "stale build folders: check"; cat "$work/art.out"; }
env HOME="$home" macup_run clean --level standard --only clean.stale_artifacts --enable clean.stale_artifacts --no-color </dev/null >"$work/art.out" 2>&1
got=$( (cd "$home" && find . -type f | sort) | comm -23 "$home.b" - | grep -v 'macup/')
[ "$got" = "$(printf '%s\n' ./Code/oldrs/target/debug/blob ./Code/oldswift/.build/debug/blob)" ] && pass "stale build folders: only the stale ones with a build file; git-tracked, recent, hidden and .venv stay" || { fail "stale build folders"; echo "$got"; cat "$work/art.out"; }
# a project edited recently only deep inside (src/app/components/ui/x.tsx) is not stale; the same project untouched is
home="$work/deep"; code="$home/Code"; mkdir -p "$home/.config/macup"; printf 'language = en\n' >"$home/.config/macup/config"
for project in edited untouched; do blob "$code/$project/node_modules/x"; echo '{}' >"$code/$project/package.json"; mkdir -p "$code/$project/src/app/components/ui"; echo x >"$code/$project/src/app/components/ui/x.tsx"; old "$code/$project"; done
touch "$code/edited/src/app/components/ui/x.tsx"
env HOME="$home" macup_run clean --level standard --only clean.stale_node_modules --enable clean.stale_node_modules --no-color </dev/null >"$work/deep.out" 2>&1
[ -f "$code/edited/node_modules/x/blob" ] && [ ! -e "$code/untouched/node_modules" ] && pass "stale node_modules: a recent file at any depth keeps them" || { fail "stale node_modules: deep recent file"; cat "$work/deep.out"; }
# a folder named build that is source (no build.gradle next to it) is looked into: an edit there keeps the project's target
home="$work/srcb"; code="$home/Code"; mkdir -p "$home/.config/macup"; printf 'language = en\n' >"$home/.config/macup/config"
blob "$code/rs/target/debug"; echo '[package]' >"$code/rs/Cargo.toml"; mkdir -p "$code/rs/build"; echo 'fn x(){}' >"$code/rs/build/gen.rs"; old "$code/rs"; touch "$code/rs/build/gen.rs"
env HOME="$home" macup_run clean --level standard --only clean.stale_artifacts --enable clean.stale_artifacts --no-color </dev/null >"$work/srcb.out" 2>&1
[ -f "$code/rs/target/debug/blob" ] && pass "stale build folders: an edit inside a source folder named build keeps the project" || { fail "stale build folders: source build folder"; cat "$work/srcb.out"; }
# a stale Pods folder under 1 MB: hidden in the list, but in --json with "hidden" and cleaned when picked
home="$work/hid"; code="$home/Code"; mkdir -p "$home/.config/macup" "$code/small/Pods/Lib"; printf 'language = en\n' >"$home/.config/macup/config"
dd if=/dev/zero of="$code/small/Pods/Lib/blob" bs=1024 count=200 2>/dev/null; echo "pod 'Lib'" >"$code/small/Podfile"; old "$code/small"
env HOME="$home" macup_run check --only clean.stale_artifacts --no-color </dev/null >"$work/hid.out" 2>&1
env HOME="$home" macup_run check --json --only clean.stale_artifacts </dev/null >"$work/hid.json" 2>/dev/null
kh=$(jq "$work/hid.json" 'matches=[entry for entry in data["cleanable"] if entry["task"]=="clean.stale_artifacts"]; assert len(matches)==1 and matches[0]["hidden"] is True and matches[0]["busy"] is False and data["could_free_more_kb"]==0; print(matches[0]["key"])')
[ -n "$kh" ] && ! grep -q 'Stale build folders' "$work/hid.out" && pass "--json: a small item hidden from the list is there with \"hidden\": true" || { fail "--json hidden item"; cat "$work/hid.out" "$work/hid.json"; }
env HOME="$home" macup_run clean --pick "$kh" --only clean.stale_artifacts --no-color </dev/null >"$work/hid.out" 2>&1
[ -n "$kh" ] && [ ! -e "$code/small/Pods" ] && [ -f "$code/small/Podfile" ] && pass "--pick cleans a hidden item" || { fail "--pick hidden item"; cat "$work/hid.out"; }

# --- caches are left alone while the tool that uses them runs: cargo, and anything started with npx (MCP servers)
home="$work/busy"; tests/fixture.sh "$home"
FAKE_RUNNING='/Users/me/.cargo/bin/cargo build --release' env HOME="$home" macup_run clean --level standard --only clean.cargo --no-color </dev/null >"$work/busy.out" 2>&1
[ -f "$home/.cargo/registry/src/index.crates.io/blob" ] && [ -f "$home/.cargo/git/db/repo-1/blob" ] && grep -q 'Cargo registry sources.*skipped' "$work/busy.out" && pass "Cargo's downloads are skipped while cargo runs" || { fail "cargo cleaned while it runs"; cat "$work/busy.out"; }
FAKE_RUNNING="node $home/.npm/_npx/abc/node_modules/.bin/some-mcp-server" env HOME="$home" macup_run clean --level standard --only clean.npm --no-color </dev/null >"$work/busy.out" 2>&1
[ -f "$home/.npm/_npx/abc/node_modules/x/blob" ] && grep -q 'npx cache.*skipped' "$work/busy.out" && pass "the npx cache is skipped while something started with npx runs" || { fail "npx cache cleaned under a running server"; cat "$work/busy.out"; }
# a check says so already, and leaves it out of what could be freed
env HOME="$home" macup_run check --json --level standard --only clean.npm </dev/null >"$work/busy0.json" 2>/dev/null
FAKE_RUNNING="node $home/.npm/_npx/abc/node_modules/.bin/some-mcp-server" env HOME="$home" macup_run check --json --level standard --only clean.npm </dev/null >"$work/busy1.json" 2>/dev/null
FAKE_RUNNING="node $home/.npm/_npx/abc/node_modules/.bin/some-mcp-server" env HOME="$home" macup_run check --level standard --only clean.npm --no-color </dev/null >"$work/busy.out" 2>&1
nk=$(jq "$work/busy1.json" 'print([entry["kb"] for entry in data["cleanable"] if entry["text"]=="npx cache" and entry["busy"]][0])')
jq "$work/busy0.json" "assert data['could_free_kb'] - $nk == $(jq "$work/busy1.json" "print(data['could_free_kb'])") and not any(entry['busy'] for entry in data['cleanable'])" 2>/dev/null \
  && grep -q 'npx cache (in use now — skipped until it is closed)' "$work/busy.out" && pass "a check marks the npx cache in use and leaves it out of the total" || { fail "busy npx cache in a check"; cat "$work/busy.out"; }
env HOME="$home" macup_run clean --only clean.npm --no-color </dev/null >"$work/busy.out" 2>&1; [ -d "$home/.npm/_npx/abc" ] && pass "the npx cache stays at the safe level" || fail "npx cache cleaned at safe"
env HOME="$home" macup_run clean --level standard --only clean.npm --no-color </dev/null >"$work/busy.out" 2>&1
[ ! -e "$home/.npm/_npx/abc" ] && pass "the npx cache is cleaned when nothing uses it" || { fail "npx cache"; cat "$work/busy.out"; }

# --- Docker: the build cache at standard; images and stopped containers only when picked; volumes never. A fake docker records what is asked
home="$work/dk"; mkdir -p "$home/.local/bin" "$home/.config/macup"; printf 'language = en\n' >"$home/.config/macup/config"
# an exported function: a real docker in /usr/local/bin would win over a fake file.
# Bash only: the Swift binary cannot see a shell function; the docker program below covers both builds
DK='clean.docker,clean.docker_images,clean.docker_containers,check.docker'
if bash_only "Docker with an exported docker function"; then
docker(){ case "$*" in
  info) ;;
  "system df --format {{.Type}}|{{.Reclaimable}}") printf 'Images|2.5GB (50%%)\nContainers|12MB (100%%)\nLocal Volumes|3GB (100%%)\nBuild Cache|1.5GB\n' ;;
  system\ df*) printf 'Images 5GB, 2.5GB (50%%) reclaimable\nBuild Cache 1.5GB, 1.5GB reclaimable\n' ;;
  ps\ -aq*) printf 'aaa\nbbb\n' ;;
  volume\ ls*) echo vol1 ;;
  *) echo "$*" >>"$HOME/docker.log"; echo "Total reclaimed space: 1.5GB" ;;
esac; }
export -f docker
env HOME="$home" macup_run check --only "$DK" --no-color </dev/null >"$work/dk.out" 2>&1
grep -q 'standard .*1.5 GB  Docker build cache' "$work/dk.out" && grep -q '2.5 GB  Docker images no container uses.*(only if you pick it)' "$work/dk.out" && grep -q 'aggressive .*Stopped Docker containers (2).*(only if you pick it)' "$work/dk.out" \
  && grep -q 'Docker volumes no container uses: 1 — macup never deletes volumes' "$work/dk.out" && [ ! -e "$home/docker.log" ] && pass "Docker: a check lists the cache, the images, the stopped containers and unused volumes; nothing is removed" || { fail "Docker check"; cat "$work/dk.out" "$home/docker.log" 2>/dev/null; }
env HOME="$home" macup_run clean --level aggressive --only "$DK" --no-color </dev/null >"$work/dk.out" 2>&1
[ "$(cat "$home/docker.log")" = "$(printf 'builder prune -f\nimage prune -f')" ] && pass "Docker: clean takes the build cache and dangling images only, even at --level aggressive" || { fail "Docker clean"; cat "$home/docker.log"; }
rm -f "$home/docker.log"; env HOME="$home" macup_run clean --level aggressive --only "$DK" --enable clean.docker_images,clean.docker_containers --no-color </dev/null >"$work/dk.out" 2>&1
grep -qx 'image prune -a -f' "$home/docker.log" && grep -qx 'container prune -f' "$home/docker.log" && ! grep -q volume "$home/docker.log" && grep -q 'Docker images no container uses.*freed 1.5 GB' "$work/dk.out" \
  && pass "Docker: images and stopped containers when enabled; volumes never" || { fail "Docker opt-in"; cat "$home/docker.log" "$work/dk.out"; }
unset -f docker
fi
# the same, with a docker program in PATH, as it prints it: sizes and answers come from FAKE_DK_* so a run can be empty, failing or stuck
home="$work/dk2"; mkdir -p "$home/.local/bin" "$home/.config/macup"; printf 'language = en\n' >"$home/.config/macup/config"
cat >"$home/.local/bin/docker" <<'FAKE'
#!/bin/bash
echo "$*" >>"$HOME/docker.log"
case "$*" in
  info) [ -n "$FAKE_DK_HANG" ] && sleep 300; [ -n "$FAKE_DK_DOWN" ] && { echo "Cannot connect to the Docker daemon" >&2; exit 1; }; echo "Server Version: 27.0" ;;
  "system df --format {{.Type}}|{{.Reclaimable}}") printf 'Images|%s\nContainers|%s\nLocal Volumes|3.2GB (100%%)\nBuild Cache|%s\n' "${FAKE_DK_IMG:-1.2GB (50%)}" "${FAKE_DK_CT:-12.3MB (100%)}" "${FAKE_DK_BC:-1.5GB}" ;;
  "system df --format {{.Type}} {{.Size}}, {{.Reclaimable}} reclaimable") printf 'Images 2.4GB, %s reclaimable\nContainers 12.3MB, %s reclaimable\nLocal Volumes 3.2GB, 3.2GB (100%%) reclaimable\nBuild Cache 1.5GB, %s reclaimable\n' "${FAKE_DK_IMG:-1.2GB (50%)}" "${FAKE_DK_CT:-12.3MB (100%)}" "${FAKE_DK_BC:-1.5GB}" ;;
  ps\ -aq*) printf '%s' "${FAKE_DK_PS-aaa111$'\n'bbb222$'\n'}" ;;
  volume\ ls*) printf '%s' "${FAKE_DK_VOLS-vol1$'\n'vol2$'\n'}" ;;
  "builder prune -f") [ -n "$FAKE_DK_PRUNE_FAIL" ] && { echo "Error response from daemon" >&2; exit 1; }; printf 'Deleted build cache objects:\nabc\n\nTotal reclaimed space: 1.2GB\n' ;;
  "image prune -f") printf 'Total reclaimed space: 300MB\n' ;;
  "image prune -a -f") printf 'Deleted Images:\nuntagged: foo:1\n\nTotal reclaimed space: 1.2GB\n' ;;
  "container prune -f") printf 'Deleted Containers:\naaa111\nbbb222\n\nTotal reclaimed space: 12.3MB\n' ;;
  *) echo "unexpected: $*" >&2; exit 64 ;;
esac
FAKE
chmod +x "$home/.local/bin/docker"
dk(){ rm -f "$home/docker.log"; env HOME="$home" macup_run "$@" --only "$DK" --no-color </dev/null >"$work/dk.out" 2>&1; }
dk check
grep -q 'Docker: Images 2.4GB, 1.2GB (50%) reclaimable; Containers 12.3MB, 12.3MB (100%) reclaimable; Local Volumes 3.2GB, 3.2GB (100%) reclaimable; Build Cache 1.5GB, 1.5GB reclaimable' "$work/dk.out" \
  && grep -q 'Docker volumes no container uses: 2 ' "$work/dk.out" && ! grep -q prune "$home/docker.log" && pass "Docker (real program): the check shows the usage and the unused volumes, and runs no prune" || { fail "Docker check, docker in PATH"; cat "$work/dk.out" "$home/docker.log"; }
env HOME="$home" macup_run check --json --only "$DK" </dev/null >"$work/dk.json" 2>/dev/null
jq "$work/dk.json" 'by_task={entry["task"]:entry for entry in data["cleanable"]}; assert set(by_task)=={"clean.docker","clean.docker_images","clean.docker_containers"}; assert 1400000<by_task["clean.docker"]["kb"]<1500000, by_task; assert 1100000<by_task["clean.docker_images"]["kb"]<1200000; assert 10000<by_task["clean.docker_containers"]["kb"]<14000; assert not by_task["clean.docker"]["opt_in"] and by_task["clean.docker_images"]["opt_in"] and by_task["clean.docker_containers"]["opt_in"] and not any(entry["in_clean"] for entry in by_task.values()) and [by_task[task]["level"] for task in ("clean.docker","clean.docker_images","clean.docker_containers")]==["standard","standard","aggressive"]; assert len({entry["key"] for entry in by_task.values()})==3' \
  && pass "Docker: --json lists the cache, the images and the stopped containers with sizes, keys and opt-in" || { fail "Docker --json"; head -c 900 "$work/dk.json"; }
kd(){ jq "$work/dk.json" "print([entry['key'] for entry in data['cleanable'] if entry['task']=='$1'][0])"; }
for spec in "clean.docker:builder prune -f|image prune -f:Docker build cache.*freed 1.5 GB" "clean.docker_images:image prune -a -f:Docker images no container uses.*freed 1.2 GB" "clean.docker_containers:container prune -f:Stopped Docker containers.*freed 12 MB"; do
  IFS=: read -r id cmds re <<<"$spec"; key=$(kd "$id")
  rm -f "$home/docker.log"; env HOME="$home" macup_run clean --pick "$key" --only "$DK" --no-color </dev/null >"$work/dk.out" 2>&1; rc=$?
  [ $rc = 0 ] && [ "$(grep prune "$home/docker.log")" = "$(printf '%s' "$cmds" | tr '|' '\n')" ] && grep -q "$re" "$work/dk.out" && ! grep -q 'volume prune\|system prune\|--volumes' "$home/docker.log" \
    && pass "Docker: --pick $id runs only: $cmds" || { fail "Docker --pick $id (rc=$rc)"; cat "$home/docker.log" "$work/dk.out"; }
done
for mode in "clean --level aggressive --enable clean.docker_images,clean.docker_containers" "clean --level aggressive" "all --level aggressive"; do
  rm -f "$home/docker.log"; env HOME="$home" macup_run $mode --only "$DK" --no-color </dev/null >"$work/dk.out" 2>&1
  ! grep -q 'volume prune\|system prune\|--volumes' "$home/docker.log" && grep -q prune "$home/docker.log" && pass "Docker: no volume prune with: $mode" || { fail "Docker volumes touched with: $mode"; cat "$home/docker.log"; }
done
rm -f "$home/docker.log"; env FAKE_DK_IMG='0B (0%)' FAKE_DK_CT='0B (0%)' FAKE_DK_BC='0B' FAKE_DK_PS='' FAKE_DK_VOLS='' HOME="$home" macup_run check --only "$DK" --no-color </dev/null >"$work/dk.out" 2>&1
! grep -q 'Docker images\|Stopped Docker\|Docker volumes' "$work/dk.out" && grep -q 'Docker: Images' "$work/dk.out" && pass "Docker: nothing to reclaim offers no images, containers or volumes line" || { fail "Docker with 0 B"; cat "$work/dk.out"; }
rm -f "$home/docker.log"; env FAKE_DK_PRUNE_FAIL=1 HOME="$home" macup_run clean --level standard --only clean.docker --no-color </dev/null >"$work/dk.out" 2>&1; rc=$?
[ $rc = 3 ] && grep -q 'Docker build cache.*failed' "$work/dk.out" && pass "Docker: a failing prune is an error, exit status 3" || { fail "Docker prune failure (rc=$rc)"; cat "$work/dk.out"; }
rm -f "$home/docker.log"; env FAKE_DK_DOWN=1 HOME="$home" macup_run all --only "$DK" --no-color </dev/null >"$work/dk.out" 2>&1; rc=$?
[ $rc = 0 ] && ! grep -qi 'docker\|✗' "$work/dk.out" && ! grep -q 'system df\|ps -aq\|prune' "$home/docker.log" && pass "Docker: a daemon that is not running gives no Docker lines and no error" || { fail "Docker down (rc=$rc)"; cat "$work/dk.out" "$home/docker.log"; }
rm -f "$home/docker.log"; s0=$SECONDS; env FAKE_DK_HANG=1 HOME="$home" macup_run check --only "$DK" --no-color </dev/null >"$work/dk.out" 2>&1; rc=$?
[ $rc = 0 ] && [ $((SECONDS - s0)) -lt 60 ] && ! grep -qi 'docker\|✗' "$work/dk.out" && pass "Docker: a daemon that hangs is given up on after 20 seconds, no Docker lines" || { fail "Docker hangs (rc=$rc, $((SECONDS - s0)) s)"; cat "$work/dk.out"; }


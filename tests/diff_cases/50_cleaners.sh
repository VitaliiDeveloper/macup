# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # SC2034: CASES is read by tests/diff.sh; SC2154: work, build and the helpers come from it
# Sourced by tests/diff.sh, in name order: the cleaners unit's cases, what each clean.* task registers. Each fix_cln_* fills
# the home folder given; the tools the cleaners ask (xcrun, docker, brew, npm, pnpm, go, yarn) are answering fakes in its
# .fake/bin (tests/fakes.sh). bash reads simctl's JSON, the profiles, the workspaces and the Electron layout with python3, so
# these cases need the Command Line Tools (without, an intended difference).
cln_path="PATH=@H/.fake/bin:$work/bin:/usr/bin:/bin"
cln_empty=clean.derived_data,clean.xcode_previews,clean.sim_caches,clean.spm,clean.cocoapods,clean.carthage,clean.yarn,clean.bun,clean.poetry,clean.cargo,clean.android,clean.trash,clean.maven,clean.app_caches
cln_caches=$cln_empty,clean.npm,clean.pnpm,clean.pip,clean.uv,clean.go,clean.go_mod,clean.gradle,clean.deno
cln_xcode=clean.device_support,clean.device_logs,clean.sim_runtimes,clean.sim_erase,clean.sim_unused,clean.sim_unavailable
cln_brew=clean.brew,clean.brew_autoremove,clean.docker,clean.docker_images,clean.docker_containers,clean.logs,clean.quicklook
cln_projects=clean.stale_node_modules,clean.stale_artifacts,clean.old_versions,clean.playwright,clean.profiles
cln_ai=clean.ai_tools,clean.editor_workspaces
cln_electron=clean.editors,clean.browsers,clean.jetbrains
CASES+="
cln-caches|cln_caches|$cln_path|check --only $cln_caches|pipe
cln-caches-json|cln_caches|$cln_path|check --only $cln_caches --json|pipe
cln-caches-standard|cln_caches|$cln_path|check --level standard --only $cln_caches|pipe
cln-caches-aggressive-json|cln_caches|$cln_path|check --level aggressive --only $cln_caches --json|pipe
cln-caches-busy|cln_caches|$cln_path FAKE_RUNNING=/usr/local/bin/cargo|check --only $cln_caches --json|pipe
cln-caches-clean|cln_caches|$cln_path|clean --level aggressive --only $cln_empty
cln-caches-all|cln_caches|$cln_path|all --level standard --only $cln_empty --skip clean.app_caches
cln-caches-small|cln_caches_small|$cln_path|check --only $cln_caches --json|pipe
cln-sizes|cln_caches|$cln_path|check --only check.sizes,clean.app_caches,clean.spm|pipe
cln-sizes-json|cln_xcode|$cln_path|check --only check.sizes,$cln_xcode --json|pipe
cln-xcode|cln_xcode|$cln_path|check --only $cln_xcode|pipe
cln-xcode-json|cln_xcode|$cln_path|check --level aggressive --only $cln_xcode --json|pipe
cln-xcode-busy|cln_xcode|$cln_path FAKE_RUNNING=/Applications/Xcode.app/Contents/MacOS/Xcode|check --only $cln_xcode --json|pipe
cln-brew|cln_brew|$cln_path|check --only $cln_brew|pipe
cln-brew-json|cln_brew|$cln_path|check --level standard --only $cln_brew --json|pipe
cln-brew-none|cln_brew_none|$cln_path|check --only $cln_brew --json|pipe
cln-projects|cln_projects|$cln_path|check --only $cln_projects|pipe
cln-projects-json|cln_projects|$cln_path|check --level aggressive --only $cln_projects --json|pipe
cln-ai|cln_ai|$cln_path|check --only $cln_ai|pipe
cln-ai-json|cln_ai|$cln_path|check --level aggressive --only $cln_ai --json|pipe
cln-ai-busy|cln_ai|$cln_path FAKE_RUNNING=/usr/local/bin/codex|check --only $cln_ai --json|pipe
cln-ai-array|cln_ai_array|$cln_path|check --only $cln_ai|pipe
cln-electron|cln_electron|$cln_path|check --only $cln_electron|pipe
cln-electron-json|cln_electron|$cln_path|check --level aggressive --only $cln_electron --json|pipe
cln-electron-open|cln_electron|$cln_path FAKE_OPEN=@H/Library/Caches/Mozilla/Profiles/abc/cache2/blob|check --only $cln_electron --json|pipe
cln-electron-running|cln_electron|$cln_path FAKE_RUNNING=/Applications/Slack.app/Contents/MacOS/Slack|check --only $cln_electron|pipe
cln-electron-clean|cln_electron|$cln_path FAKE_OPEN=@H/Library/Caches/Code/GPUCache/blob|clean --level aggressive --only $cln_electron
cln-electron-editors|cln_electron|$cln_path|check --only clean.editors --json|pipe
cln-missing||$cln_path|check --only $cln_caches,$cln_xcode,$cln_brew,$cln_projects,$cln_ai,$cln_electron --json|pipe
cln-missing-text||$cln_path|check --level aggressive --only $cln_caches,$cln_xcode,$cln_projects,$cln_ai|pipe"

aged(){ find "$@" -exec touch -t 202001010000 {} +; }   # files and folders older than every limit the cleaners use
uuid(){ printf '%s-%s-%s-%s-%s' "$(printf "$1%.0s" 1 2 3 4 5 6 7 8)" "$1$1$1$1" "$1$1$1$1" "$1$1$1$1" "$(printf "$1%.0s" 1 2 3 4 5 6 7 8 9 10 11 12)"; }

# caches emptied in place (CACHE_DIRS), caches cleaned by their tool (TOOL_CACHES), Deno, the Trash, Gradle, Android, Maven,
# other big folders in ~/Library/Caches
fix_cln_caches(){ local caches="$1/Library/Caches"
  answering "$1/.fake/bin" npm pnpm go yarn; answer "$1" pnpm 'store path' "$1/pnpm-store"; answer "$1" go 'env GOCACHE' "$1/gocache"; answer "$1" go 'env GOMODCACHE' ''
  blob "$caches/org.swift.swiftpm/repos" 6144; blob "$caches/CocoaPods" 1024; blob "$caches/Yarn/v6" 5200; blob "$1/.npm/_npx/abc" 5300
  blob "$1/.cargo/registry/cache/x" 6000; blob "$1/.cargo/git/db/y" 5500; blob "$1/.gradle/caches/modules" 7000; blob "$1/.android/cache" 5120
  blob "$1/elsewhere" 8000; mkdir -p "$caches"; ln -s "$1/elsewhere" "$caches/org.carthage.CarthageKit"
  blob "$1/.npm/_cacache" 2048; blob "$1/pnpm-store/v3" 3000; blob "$1/gocache/aa" 100
  blob "$caches/deno/deps" 6000; blob "$caches/deno/location_data" 64
  blob "$1/.Trash/old" 2048; blob "$1/.gradle/wrapper/dists/gradle-7.0" 2048; blob "$1/.gradle/wrapper/dists/gradle-8.9" 64; aged "$1/.gradle/wrapper/dists/gradle-7.0"
  blob "$caches/Google/AndroidStudio2024.1" 5500; blob "$1/.m2/repository/org/x" 6000; : >"$1/.m2/repository/org/x/maven-metadata-local.xml"
  big "$caches/BigApp/data"; big "$caches/com.apple.Big/data"; big "$caches/Adobe Camera Raw 2/x"; big "$caches/pypoetry/virtualenvs/v/data"
  : >"$caches/pypoetry/virtualenvs/v/pyvenv.cfg"; big "$caches/Yarn/big"; big "$1/elsewhere2/data"; ln -s "$1/elsewhere2" "$caches/LinkedBig"; }
fix_cln_caches_small(){ blob "$1/Library/Caches/org.swift.swiftpm" 64; mkdir -p "$1/.Trash"; }

# Xcode: device support and logs, simulators (runtimes, erase, unused, unavailable), simctl answering from JSON
fix_cln_xcode(){ local dev="$1/Library/Developer" shut booted watch bad gone
  shut=$(uuid A); booted=$(uuid B); watch=$(uuid C); bad=$(uuid D); gone=$(uuid E)
  answering "$1/.fake/bin" xcrun
  answer "$1" xcrun 'simctl list devices -j' "{\"devices\":{\"com.apple.CoreSimulator.SimRuntime.iOS-17-2\":[{\"udid\":\"$shut\",\"state\":\"Shutdown\",\"name\":\"iPhone 15\"},{\"udid\":\"$booted\",\"state\":\"Booted\",\"name\":\"iPhone 14\"},{\"udid\":\"not a uuid\",\"state\":\"Shutdown\",\"name\":\"Odd\"}],\"com.apple.CoreSimulator.SimRuntime.watchOS-10-0\":[{\"udid\":\"$watch\",\"state\":\"Shutdown\",\"name\":\"Watch\\tUltra\"}],\"com.apple.CoreSimulator.SimRuntime.tvOS-17-0\":[{\"udid\":\"$bad\",\"state\":\"Shutdown\",\"name\":\"Apple TV\"}]}}"
  answer "$1" xcrun 'simctl runtime list -j' '{"RT-IOS":{"runtimeIdentifier":"com.apple.CoreSimulator.SimRuntime.iOS-17-2","sizeBytes":7000000000,"lastUsedAt":"2026-01-02T10:00:00Z","version":"17.2"},"RT-WATCH":{"runtimeIdentifier":"com.apple.CoreSimulator.SimRuntime.watchOS-10-0","sizeBytes":3000000000.7,"version":"10.0","deletable":true},"RT-TV":{"runtimeIdentifier":"com.apple.CoreSimulator.SimRuntime.tvOS-17-0","sizeBytes":1,"deletable":false},"RT-NEW":{"runtimeIdentifier":"com.apple.CoreSimulator.SimRuntime.xrOS-2-0","sizeBytes":2048,"lastUsedAt":null}}'
  answer "$1" xcrun 'simctl list devices unavailable' "$(printf -- '-- iOS 15.0 --\n    iPhone 8 (%s) (Shutdown) (unavailable, runtime profile not found)\n    iPad (%s) (Shutdown)' "$gone" "$shut")"
  answer "$1" xcrun "simctl --set ${dev//\//_}_XCTestDevices list devices unavailable" "$(printf 'Clone 1 of iPhone (%s) (Shutdown) (unavailable)' "$gone")"
  big "$dev/CoreSimulator/Devices/$shut/data/big"; blob "$dev/CoreSimulator/Devices/$watch/data" 64; blob "$dev/CoreSimulator/Devices/$bad/data" 64
  blob "$dev/CoreSimulator/Devices/$gone" 2048; blob "$dev/XCTestDevices/$gone" 1500
  aged "$dev/CoreSimulator/Devices/$shut" "$dev/CoreSimulator/Devices/$bad"
  blob "$dev/Xcode/iOS DeviceSupport/16.0 (20A1)" 3000; blob "$dev/Xcode/iOS DeviceSupport/17.0" 3000; blob "$dev/Xcode/watchOS DeviceSupport/9.0" 2000
  aged "$dev/Xcode/iOS DeviceSupport/16.0 (20A1)" "$dev/Xcode/watchOS DeviceSupport/9.0"
  mkdir -p "$dev/Xcode/iOS Device Logs"; dd if=/dev/zero of="$dev/Xcode/iOS Device Logs/old.crash" bs=1024 count=1500 2>/dev/null
  : >"$dev/Xcode/iOS Device Logs/new.crash"; aged "$dev/Xcode/iOS Device Logs/old.crash"; }

# Homebrew's cleanup and autoremove, Docker, old logs
fix_cln_brew(){ answering "$1/.fake/bin" brew docker
  answer "$1" brew 'cleanup -s --prune=7 -n' "$(printf '==> Would remove: x\n==> This operation would free approximately 1.5GB of disk space.')"
  answer "$1" brew --cache "$1/brewcache"; answer "$1" brew 'autoremove --dry-run' "$(printf '==> Would uninstall 2 unneeded formulae:\nlibfoo\nbar,baz')"
  answer "$1" docker 'system df --format {{.Type}}|{{.Reclaimable}}' "$(printf 'Images|2.5GB (60%%)\nContainers|300MB (100%%)\nLocal Volumes|1GB (50%%)\nBuild Cache|1.2GB')"
  answer "$1" docker 'ps -aq -f status=exited -f status=created -f status=dead' "$(printf 'abc\ndef')"
  blob "$1/Library/Logs/App/old" 700; blob "$1/.npm/_logs" 400; mv "$1/.npm/_logs/blob" "$1/.npm/_logs/a.log"; blob "$1/Library/Logs/macup/x" 64
  aged "$1/Library/Logs" "$1/.npm/_logs"; }
fix_cln_brew_none(){ answering "$1/.fake/bin" brew docker; mkdir -p "$1/.fake/docker"; echo 1 >"$1/.fake/docker/info.rc"; answer "$1" brew 'cleanup -s --prune=7 -n' 'Nothing'; }

# projects: stale build folders, older runtime versions and the pins that keep them, old test browsers, provisioning profiles
fix_cln_projects(){ local code="$1/Code" caches="$1/Library/Caches" profiles="$1/Library/MobileDevice/Provisioning Profiles" version
  blob "$code/web/node_modules/left-pad" 2048; echo '{"engines": {"node": "20.5"}}' >"$code/web/package.json"; echo 22.1 >"$code/web/.nvmrc"
  blob "$code/rs/target/debug" 1500; echo '[package]' >"$code/rs/Cargo.toml"; blob "$code/fresh/node_modules/x" 1024; echo '{}' >"$code/fresh/package.json"
  blob "$code/.hidden/proj/node_modules/x" 1024; blob "$code/plain/build/out" 1024; blob "$code/g/build/out" 1024; : >"$code/g/build.gradle"
  aged "$code/web" "$code/rs" "$code/.hidden" "$code/plain" "$code/g"; touch "$code/fresh/package.json"
  for version in v18.0.0 v18.2.0 v20.1.0 v20.5.0 v20.5.3 v22.1.0 v22.1.4 v22.2.0 notes; do blob "$1/.nvm/versions/node/$version" 600; done
  mkdir -p "$1/.nvm/alias"; echo 18.0.0 >"$1/.nvm/alias/default"; ln -s "$1/.nvm/versions/node/v20.1.0" "$1/.nvm/versions/node/v20.0.9"
  for version in 3.1.2 3.1.4 3.10.1 3.2.0; do blob "$1/.rbenv/versions/$version" 600; done; echo 3.2.0 >"$1/.rbenv/version"
  for version in 3.11.1 3.11.9 3.12.0; do blob "$1/.pyenv/versions/$version" 64; done; blob "$1/.pyenv/versions/3.11.1/envs/venv" 16
  for version in 1.21.0 1.22.1; do blob "$1/.local/share/mise/installs/go/$version" 64; done
  for version in 20.0.0 20.3.0; do blob "$1/.asdf/installs/node/$version" 64; done
  for version in chromium-1100 chromium-1200 firefox-1.2 firefox-1.10 ffmpeg; do blob "$caches/ms-playwright/$version" 200; done
  for version in 12.9.0 13.0.0 13.10.0 13.2.0; do blob "$caches/Cypress/$version" 300; done; blob "$1/.cache/puppeteer/chrome/mac-120.0.1" 300
  blob "$1/.cache/puppeteer/chrome/mac-121.0.0" 300
  mkdir -p "$profiles"; for version in old:2020-01-01 new:2099-01-01; do
    printf 'binary\001<?xml version="1.0"?><plist version="1.0"><dict><key>ExpirationDate</key><date>%sT00:00:00Z</date></dict></plist>tail' "${version#*:}" >"$profiles/${version%%:*}.mobileprovision"; done
  echo 'no plist' >"$profiles/broken.mobileprovision"; cp "$profiles/old.mobileprovision" "$profiles/old.txt"; }

# AI tools' leftovers and the editors' data of workspaces whose folder is gone, one case per rule
fix_cln_ai(){ local codex="$1/.codex" support="$1/Library/Application Support" number
  for number in $(seq 1 55); do mkdir -p "$codex/.tmp/git-$number"; done; mkdir -p "$codex/.tmp/git-new" "$codex/.tmp/other-1"
  blob "$1/.cache/codex-runtimes/codex-runtime-install-1" 64; mkdir -p "$codex/.tmp/plugins" "$codex/.tmp/plugins-backup-7"
  : >"$codex/..codex-global-state.json.x.tmp-1"; blob "$codex/cache/remote_plugin_catalog" 32; mv "$codex/cache/remote_plugin_catalog/blob" "$codex/cache/remote_plugin_catalog/acct.json"
  blob "$1/.local/bin" 16; mv "$1/.local/bin/blob" "$1/.local/bin/agy.1.2.old"
  blob "$1/.grok/downloads" 16; mv "$1/.grok/downloads/blob" "$1/.grok/downloads/grok-1.0.70"; : >"$1/.grok/downloads/grok-1.0.77"; mkdir -p "$1/.grok/bin"
  ln -s "$1/.grok/downloads/grok-1.0.77" "$1/.grok/bin/grok"
  mkdir -p "$1/.claude/projects/-Users-me-app" "$1/.claude/file-history/live-1" "$1/.claude/file-history/gone-2"; : >"$1/.claude/projects/-Users-me-app/live-1.jsonl"
  aged "$codex" "$1/.cache" "$1/.grok/downloads" "$1/.claude/file-history"
  local storage="$support/Code/User/workspaceStorage" name uri
  mkdir -p "$1/Projects/here" "$1/Library/Gone" "$1/linked-target"; ln -s "$1/linked-target" "$1/linked"
  for name in gone:"file://$1/Projects/missing" here:"file://$1/Projects/here" lib:"file://$1/Library/Gone/x" link:"file://$1/linked/missing" \
      host:"file://server$1/Projects/missing" local:"file://localhost$1/Projects/percent%20gone" up:"file://$1/Projects/../missing" \
      out:"file:///Volumes/Disk/missing" web:"vscode-remote://ssh/x" query:"file://$1/Projects/q?x=1"; do
    mkdir -p "$storage/${name%%:*}"; uri=${name#*:}; printf '{"folder": "%s"}' "$uri" >"$storage/${name%%:*}/workspace.json"; done
  mkdir -p "$storage/ws-key" "$storage/.hidden" "$storage/broken"; printf '{"folder": "", "workspace": "file://%s/Projects/w.code-workspace"}' "$1" >"$storage/ws-key/workspace.json"
  printf '{"folder": "file://%s/x"}' "$1" >"$storage/.hidden/workspace.json"; printf '{"folder": ' >"$storage/broken/workspace.json"
  mkdir -p "$support/Cursor/User"; ln -s "$storage" "$support/Cursor/User/workspaceStorage"; }
fix_cln_ai_array(){ fix_cln_ai "$1"; printf '[1]' >"$1/Library/Application Support/Code/User/workspaceStorage/here/workspace.json"; }   # Python stops there

# editors and Electron apps (ELECTRON_APPS), browsers (BROWSERS), and other caches found by their Chromium or Firefox layout;
# a cache the layout scan finds for a listed app is added to the table's item
fix_cln_electron(){ local support="$1/Library/Application Support" caches="$1/Library/Caches"
  blob "$support/Code/Cache" 3000; blob "$support/Code/Default/GPUCache" 3000; blob "$support/Code/User/settings" 64; blob "$caches/Code/GPUCache" 5200
  blob "$support/Slack/Partitions/team/Code Cache" 6000; blob "$support/Cursor/Cache" 1024
  blob "$caches/Google/Chrome/Default" 6000; blob "$caches/BraveSoftware/x" 2000; blob "$caches/Firefox/Profiles" 7000
  blob "$support/Vendor/App/Cache" 6000; : >"$support/Vendor/App/Local State"; blob "$support/Vendor/App/Helper.app/Cache" 6000
  blob "$support/Thorium/Default/Cache" 6000; : >"$support/Thorium/Local State"; : >"$support/Thorium/Default/History"; : >"$support/Thorium/Default/Preferences"; : >"$support/Thorium/Default/Cookies"
  blob "$caches/Mozilla/Profiles/abc/cache2" 6000; blob "$support/Plain/Cache" 6000; blob "$support/Tiny/Cache" 100; : >"$support/Tiny/Local State"
  blob "$caches/com.apple.Thing/x/Cache" 6000; blob "$caches/Updater.ShipIt/y/Cache" 6000; }

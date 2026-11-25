#!/bin/bash
# Builds a fake home with things macup may and may never delete. Usage: fixture.sh DIR
H="$1"; rm -rf "$H"; mkdir -p "$H"
blob(){ mkdir -p "$1"; dd if=/dev/zero of="$1/blob" bs=1024 count="${2:-6144}" 2>/dev/null; }
old(){ find "$@" -exec touch -t 202401010000 {} +; }
L="$H/Library"; D="$L/Developer"
# --- safe today
blob "$D/Xcode/DerivedData/App-abc"; blob "$D/Xcode/UserData/Previews/x"
blob "$D/Xcode/iOS DeviceSupport/16.0 (20A1)"; old "$D/Xcode/iOS DeviceSupport/16.0 (20A1)"; blob "$D/Xcode/iOS DeviceSupport/18.0 (22A1)"
mkdir -p "$D/Xcode/iOS Device Logs"; dd if=/dev/zero of="$D/Xcode/iOS Device Logs/old.crash" bs=1024 count=2048 2>/dev/null; old "$D/Xcode/iOS Device Logs/old.crash"; echo new >"$D/Xcode/iOS Device Logs/new.crash"
blob "$D/CoreSimulator/Caches/dyld"; blob "$L/Caches/org.swift.swiftpm/repos"; blob "$L/Caches/CocoaPods/Pods"; blob "$L/Caches/org.carthage.CarthageKit/x"
mkdir -p "$L/Logs/SomeApp"; dd if=/dev/zero of="$L/Logs/SomeApp/old.log" bs=1024 count=2048 2>/dev/null; old "$L/Logs/SomeApp/old.log"; echo new >"$L/Logs/SomeApp/new.log"
# --- opt-in / manual today
blob "$H/.Trash/thing"
blob "$H/Code/old/node_modules/a"; old "$H/Code/old"; blob "$H/Code/new/node_modules/b"; touch "$H/Code/new/package.json"
# --- never: user data and secrets next to caches
blob "$D/Xcode/Archives/App.xcarchive" 1024; blob "$H/Downloads/movie" 1024; blob "$H/Documents/doc" 1024
mkdir -p "$H/.codex/sessions" "$H/.codex/archived_sessions"; echo chat >"$H/.codex/sessions/s.jsonl"; echo db >"$H/.codex/thread_history_1.sqlite"
mkdir -p "$H/.gradle"; echo "signing.password=secret" >"$H/.gradle/gradle.properties"
mkdir -p "$H/.m2"; echo "<settings/>" >"$H/.m2/settings.xml"
mkdir -p "$H/.android/avd/Pixel.avd"; echo key >"$H/.android/debug.keystore"; echo key >"$H/.android/adbkey"
for a in Code Cursor Claude; do mkdir -p "$L/Application Support/$a/User" "$L/Application Support/$a/Backups"; echo '{}' >"$L/Application Support/$a/User/settings.json"; echo unsaved >"$L/Application Support/$a/Backups/file"; done
mkdir -p "$L/Application Support/Google/Chrome/Default"; echo pw >"$L/Application Support/Google/Chrome/Default/Login Data"
mkdir -p "$H/.nvm/alias"; echo keep >"$H/.zshrc"
# a cache folder that is a symlink to data elsewhere: the target must survive
mkdir -p "$H/elsewhere"; echo precious >"$H/elsewhere/precious"; ln -s "$H/elsewhere" "$L/Caches/org.carthage.CarthageKit/linked"
mkdir -p "$H/.config/macup"; printf 'language = en\nproject_dirs = ~/Code\n' >"$H/.config/macup/config"
# --- 3.0 cleaners
blob "$H/.gradle/caches/modules-2"; blob "$H/.gradle/wrapper/dists/gradle-7.0-bin"; old "$H/.gradle/wrapper/dists/gradle-7.0-bin"; blob "$H/.gradle/wrapper/dists/gradle-8.9-bin"
blob "$H/.android/cache/x"; blob "$L/Caches/Google/AndroidStudio2024.1/index"; blob "$H/.m2/repository/org"
for v in v18.1.0 v18.20.0 v20.1.0 v20.5.0 v20.11.0; do blob "$H/.nvm/versions/node/$v" 1024; done
echo "v20.1.0" >"$H/.nvm/alias/default"                      # an exact older default: must stay
mkdir -p "$H/Code/pinned"; echo "18.1.0" >"$H/Code/pinned/.nvmrc"  # pinned by a project: must stay
for v in 3.2.1 3.2.4; do blob "$H/.rbenv/versions/$v" 1024; done
for v in 3.11.1 3.11.9; do blob "$H/.pyenv/versions/$v" 1024; done; blob "$H/.pyenv/versions/3.11.1/envs/myenv" 64   # has a virtualenv: stays
blob "$L/Caches/ms-playwright/chromium-1100"; blob "$L/Caches/ms-playwright/chromium-1234"; blob "$L/Caches/ms-playwright/ffmpeg-1011" 64
blob "$H/.codex/.tmp/git-abc"; old "$H/.codex/.tmp/git-abc"; blob "$H/.codex/.tmp/git-new" 64
mkdir -p "$H/.local/bin"; dd if=/dev/zero of="$H/.local/bin/agy.1790781307826422000.old" bs=1024 count=6144 2>/dev/null; echo keep >"$H/.local/bin/agy.notes"
blob "$H/.cache/codex-runtimes/codex-primary-runtime" 1024; blob "$H/.cache/codex-runtimes/codex-runtime-install-XYZ"; old "$H/.cache/codex-runtimes/codex-runtime-install-XYZ"
for a in Code Cursor Claude discord; do blob "$L/Application Support/$a/Cache/c"; blob "$L/Application Support/$a/Code Cache/js" 64; done
P="$L/Application Support/Codex/Default/Partitions/browser"; blob "$P/Code Cache/js"; mkdir -p "$P/Local Storage"; echo site >"$P/Local Storage/leveldb"   # site data next to a partition cache: stays
mkdir -p "$H/elsewhere3/Cache" "$L/Application Support/Codex/Partitions"; dd if=/dev/zero of="$H/elsewhere3/Cache/big" bs=1024 count=6144 2>/dev/null; ln -s "$H/elsewhere3" "$L/Application Support/Codex/Partitions/linked"
blob "$L/Caches/Arc/data"; blob "$L/Caches/Google/Chrome/Default/Cache"; blob "$L/Caches/Arc/org.sparkle-project.Sparkle/Installation/z"   # a pending update inside a browser cache folder stays
# found by layout, not by name: an unknown Electron app, Chrome's profile caches, a Firefox-based browser.
# A non-Chromium app with a Cache folder, Chrome's data and staged app updates stay.
E="$L/Application Support/SomeApp"; mkdir -p "$E"; echo '{}' >"$E/Preferences"; : >"$E/Cookies"; blob "$E/Cache/c"; blob "$E/Code Cache/js" 64; blob "$L/Caches/SomeApp/Default/Cache"
mkdir -p "$L/Application Support/QtApp"; echo x >"$L/Application Support/QtApp/Preferences"; blob "$L/Application Support/QtApp/Cache/q"
G="$L/Application Support/Google/Chrome"; echo '{}' >"$G/Local State"; echo '{}' >"$G/Default/Preferences"; echo h >"$G/Default/History"; echo c >"$G/Default/Cookies"; blob "$G/Default/Code Cache/js"; blob "$G/GrShaderCache/g"
blob "$L/Caches/zen/Profiles/abc.default/cache2/entries"
blob "$L/Caches/com.foo.ShipIt/update.x/Foo.app/Contents/Resources/Cache/r"; blob "$L/Caches/com.bar/org.sparkle-project.Sparkle/Installation/y/Bar.app/Contents/GPUCache/g"
mkdir -p "$H/elsewhere2"; echo precious >"$H/elsewhere2/precious"; dd if=/dev/zero of="$H/elsewhere2/big" bs=1024 count=6144 2>/dev/null; ln -s "$H/elsewhere2" "$L/Caches/Firefox"
blob "$L/Caches/BigApp" 103424; blob "$L/Caches/com.apple.bigdaemon" 103424
# a project venv built on an exact Python patch, an nvm alias chain, and a local mvn install: all must stay
blob "$H/.pyenv/versions/3.12.1" 1024; blob "$H/.pyenv/versions/3.12.8" 1024
mkdir -p "$H/Code/proj/.venv"; printf 'home = %s\nversion = 3.12.1\n' "$H/.pyenv/versions/3.12.1/bin" >"$H/Code/proj/.venv/pyvenv.cfg"
# venvs outside the project folders, made by pipenv and virtualenvwrapper
blob "$H/.pyenv/versions/3.13.1" 1024; blob "$H/.pyenv/versions/3.13.4" 1024; blob "$H/.pyenv/versions/3.10.2" 1024; blob "$H/.pyenv/versions/3.10.9" 1024
mkdir -p "$H/.local/share/virtualenvs/app-Ab12Cd34" "$H/.virtualenvs/tool"
printf 'home = %s\nversion = 3.13.1\n' "$H/.pyenv/versions/3.13.1/bin" >"$H/.local/share/virtualenvs/app-Ab12Cd34/pyvenv.cfg"
printf 'home = %s\nversion = 3.10.2\n' "$H/.pyenv/versions/3.10.2/bin" >"$H/.virtualenvs/tool/pyvenv.cfg"
for v in v22.1.0 v22.9.0; do blob "$H/.nvm/versions/node/$v" 1024; done
mkdir -p "$H/.nvm/alias/lts"; echo "lts/jod" >"$H/.nvm/alias/default2"; echo "v22.1.0" >"$H/.nvm/alias/lts/jod"
blob "$H/.m2/repository/com/me/lib/1.0-SNAPSHOT" 64; echo '<metadata/>' >"$H/.m2/repository/com/me/lib/maven-metadata-local.xml"
blob "$L/Caches/Microsoft Edge/Cache"
# --- 2.8 cleaners: Bun, Deno, Poetry (its virtualenvs stay), Cargo, JetBrains
blob "$H/.bun/install/cache/x"; blob "$L/Caches/deno/deps"; blob "$L/Caches/pypoetry/cache/x"; blob "$L/Caches/pypoetry/artifacts/y"
blob "$L/Caches/pypoetry/virtualenvs/proj-Ab12-py3.12/lib" 64; printf 'version = 3.12.1\n' >"$L/Caches/pypoetry/virtualenvs/proj-Ab12-py3.12/pyvenv.cfg"
blob "$H/.cargo/registry/cache/index.crates.io"; blob "$H/.cargo/registry/src/index.crates.io"; mkdir -p "$H/.cargo/registry/index"; echo idx >"$H/.cargo/registry/index/keep"
blob "$L/Caches/JetBrains/IntelliJIdea2025.1/index"
# Deno keeps localStorage and Deno.openKv() databases inside its cache folder: they stay
mkdir -p "$L/Caches/deno/location_data/abc"; echo kv >"$L/Caches/deno/location_data/abc/kv.sqlite3"; echo ls >"$L/Caches/deno/location_data/abc/local_storage"
# a pin without the patch (.nvmrc "21.2") keeps the newest 21.2.x; a pin in package.json (volta, engines) counts too
for v in v21.2.0 v21.2.5 v21.7.0 v23.1.0 v23.4.0; do blob "$H/.nvm/versions/node/$v" 1024; done
mkdir -p "$H/Code/partial" "$H/Code/volta"; echo "21.2" >"$H/Code/partial/.nvmrc"
printf '{"dependencies":{"left-pad":"23.4.0"},"volta":{"node":"23.1.0"}}\n' >"$H/Code/volta/package.json"
# --deep: target counts only next to Cargo.toml or pom.xml
blob "$H/Code/rs/target/debug"; echo '[package]' >"$H/Code/rs/Cargo.toml"; blob "$H/Code/plain/target/data" 64
# --- 2.9 cleaners: Cargo git, old Cypress versions, expired provisioning profiles, npm and Gradle daemon logs, npx
blob "$H/.cargo/git/checkouts/repo-1/abc"; blob "$H/.cargo/git/db/repo-1"
blob "$L/Caches/Cypress/13.1.0/Cypress"; blob "$L/Caches/Cypress/13.6.2/Cypress" 64
PP="$L/MobileDevice/Provisioning Profiles"; mkdir -p "$PP"
prof(){ printf 'sig<?xml version="1.0"?><plist version="1.0"><dict><key>ExpirationDate</key><date>%s</date></dict></plist>sig' "$2" >"$PP/$1"; }
prof expired.mobileprovision 2020-01-01T00:00:00Z; prof valid.mobileprovision 2099-01-01T00:00:00Z; echo broken >"$PP/unreadable.mobileprovision"
mkdir -p "$H/.npm/_logs" "$H/.gradle/daemon/8.9"; echo old >"$H/.npm/_logs/old-debug-0.log"; old "$H/.npm/_logs/old-debug-0.log"; echo new >"$H/.npm/_logs/new-debug-0.log"
echo old >"$H/.gradle/daemon/8.9/daemon-1.out.log"; old "$H/.gradle/daemon/8.9/daemon-1.out.log"; echo keep >"$H/.gradle/daemon/8.9/registry.bin"; old "$H/.gradle/daemon/8.9/registry.bin"
blob "$H/.npm/_npx/abc/node_modules/x"
# --- 2.9.2 AI tools. Grok: the version ~/.grok/bin points at and a download in progress stay
mkdir -p "$H/.grok/downloads" "$H/.grok/bin"; for v in 1.0.89 1.0.92 1.0.93; do dd if=/dev/zero of="$H/.grok/downloads/grok-$v-macos-aarch64" bs=1024 count=2048 2>/dev/null; done
old "$H/.grok/downloads/grok-1.0.89-macos-aarch64" "$H/.grok/downloads/grok-1.0.92-macos-aarch64"; ln -s ../downloads/grok-1.0.92-macos-aarch64 "$H/.grok/bin/grok"
# Codex: a stale plugin backup next to the live plugin set, an unfinished state write, the catalog of an account unused for a month
blob "$H/.codex/.tmp/plugins/repo" 64; blob "$H/.codex/.tmp/plugins-backup-Ab12Cd/repo" 2048; old "$H/.codex/.tmp/plugins-backup-Ab12Cd"
echo '{}' >"$H/.codex/.codex-global-state.json"; dd if=/dev/zero of="$H/.codex/..codex-global-state.json.tmp-1784380121760-c8bf" bs=1024 count=1024 2>/dev/null; old "$H/.codex/..codex-global-state.json.tmp-1784380121760-c8bf"
mkdir -p "$H/.codex/cache/remote_plugin_catalog"
dd if=/dev/zero of="$H/.codex/cache/remote_plugin_catalog/old.json" bs=1024 count=2048 2>/dev/null; old "$H/.codex/cache/remote_plugin_catalog/old.json"; echo '{}' >"$H/.codex/cache/remote_plugin_catalog/fresh.json"
# Claude Code prunes its own plugin versions: none of them go
C="$H/.claude/plugins/cache/mkt/plug"; for v in 0.8.0 0.9.0 1.0.0 1.0.1; do blob "$C/$v" 1024; done
for v in 0.8.0 0.9.0 1.0.0; do echo 1700000000000 >"$C/$v/.orphaned_at"; done; old "$C/0.8.0" "$C/1.0.0"
printf '{"plugins":{"plug@mkt":[{"installPath":"%s"}]}}\n' "$C/0.8.0" >"$H/.claude/plugins/installed_plugins.json"
# edit backups: of a session with a transcript (stays), of a deleted one (goes), of a deleted one from today (stays)
mkdir -p "$H/.claude/projects/-Users-me-app"; echo '{}' >"$H/.claude/projects/-Users-me-app/aaaa-1111.jsonl"; echo '{}' >"$H/.claude/history.jsonl"
for s in aaaa-1111 bbbb-2222 cccc-3333; do blob "$H/.claude/file-history/$s" 1024; done; old "$H/.claude/file-history/aaaa-1111" "$H/.claude/file-history/bbbb-2222"
# editors: a workspace whose folder is gone (only on a pick), one whose folder is there, one on a disk that is not mounted
WS="$L/Application Support/Code/User/workspaceStorage"; mkdir -p "$WS/abc123" "$WS/def456" "$WS/ext789"
printf '{"folder":"file://%s/Code/gone%%20app"}\n' "$H" >"$WS/abc123/workspace.json"; dd if=/dev/zero of="$WS/abc123/state.vscdb" bs=1024 count=2048 2>/dev/null
printf '{"folder":"file://%s/Code/new"}\n' "$H" >"$WS/def456/workspace.json"; echo db >"$WS/def456/state.vscdb"
printf '{"folder":"file:///Volumes/Ext/proj"}\n' >"$WS/ext789/workspace.json"; echo db >"$WS/ext789/state.vscdb"
# ...and folders that only look gone: behind a symlink to an unmounted disk, in iCloud Drive while signed out
ln -s /Volumes/macup-no-such-disk/Projects "$H/Linked"; mkdir -p "$WS/lnk111" "$WS/icl222"
printf '{"folder":"file://%s/Linked/app"}\n' "$H" >"$WS/lnk111/workspace.json"; echo db >"$WS/lnk111/state.vscdb"
printf '{"folder":"file://%s/Library/Mobile%%20Documents/com~apple~CloudDocs/notes"}\n' "$H" >"$WS/icl222/workspace.json"; echo db >"$WS/icl222/state.vscdb"

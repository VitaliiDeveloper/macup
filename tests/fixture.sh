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
for v in v22.1.0 v22.9.0; do blob "$H/.nvm/versions/node/$v" 1024; done
mkdir -p "$H/.nvm/alias/lts"; echo "lts/jod" >"$H/.nvm/alias/default2"; echo "v22.1.0" >"$H/.nvm/alias/lts/jod"
blob "$H/.m2/repository/com/me/lib/1.0-SNAPSHOT" 64; echo '<metadata/>' >"$H/.m2/repository/com/me/lib/maven-metadata-local.xml"
blob "$L/Caches/Microsoft Edge/Cache"

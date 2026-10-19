# ---------------------------------------------------------------- what macup cleans
# To support another cache, add a line to one of these tables. Levels: 1 safe, 2 standard, 3 aggressive.

# Folders whose contents can simply be deleted (the folder itself stays).
# task | level | label | folder (~ = home) | skipped while this runs (pgrep -f) | only if this tool exists
CACHE_DIRS='clean.derived_data|1|Xcode DerivedData|~/Library/Developer/Xcode/DerivedData|/Xcode.app/Contents/MacOS/Xcode|
clean.xcode_previews|1|SwiftUI previews|~/Library/Developer/Xcode/UserData/Previews|/Xcode.app/Contents/MacOS/Xcode|
clean.sim_caches|1|Simulator caches|~/Library/Developer/CoreSimulator/Caches||
clean.spm|1|SwiftPM cache|~/Library/Caches/org.swift.swiftpm||
clean.cocoapods|1|CocoaPods cache|~/Library/Caches/CocoaPods||
clean.carthage|1|Carthage cache|~/Library/Caches/org.carthage.CarthageKit||
clean.yarn|1|Yarn cache|~/Library/Caches/Yarn||yarn
clean.pnpm|1|pnpm metadata cache|~/Library/Caches/pnpm||
clean.npm|1|node-gyp headers|~/Library/Caches/node-gyp||
clean.gradle|2|Gradle caches|~/.gradle/caches|GradleDaemon|
clean.android|2|Android cache|~/.android/cache||'

# Caches cleaned by the tool's own command (it knows what is still in use). The folder is measured
# before and after; @tool means "ask the tool where its cache is".
# task | level | label | tool | command key (see run_key) | folder
TOOL_CACHES='clean.npm|1|npm cache|npm|npm|~/.npm/_cacache
clean.pnpm|1|pnpm store|pnpm|pnpm|@pnpm
clean.pip|1|pip cache|pip3|pip|~/Library/Caches/pip
clean.uv|1|uv cache|uv|uv|@uv
clean.go|1|Go build cache|go|go|@go'

# Electron apps: only these cache subfolders (also in Default/ and Partitions/*), never User/ (settings) or Backups/ (unsaved files).
# folder in ~/Library/Application Support | app name (skipped while it runs, as is anything started with that folder as --user-data-dir)
ELECTRON_APPS='Code|Visual Studio Code
Code - Insiders|Visual Studio Code - Insiders
Cursor|Cursor
Windsurf|Windsurf
Antigravity|Antigravity
VSCodium|VSCodium
Claude|Claude
Codex|Codex
Postman|Postman'
ELECTRON_CACHES='Cache|CachedData|Code Cache|GPUCache|CachedExtensionVSIXs|logs|DawnGraphiteCache|DawnWebGPUCache|GraphiteDawnCache|GrShaderCache|ShaderCache'

# Browsers: cache only, in ~/Library/Caches; never profiles, history or passwords.
# name | app name (skipped while it runs) | cache folders in ~/Library/Caches, separated by ;
BROWSERS='Arc|Arc|Arc;company.thebrowser.Browser
Google Chrome|Google Chrome|Google/Chrome
Firefox|Firefox|Firefox
Microsoft Edge|Microsoft Edge|Microsoft Edge
Brave|Brave Browser|BraveSoftware
Opera|Opera|com.operasoftware.Opera
Vivaldi|Vivaldi|Vivaldi'

tool_dir(){ case "$1" in @pnpm) pnpm store path 2>/dev/null ;; @uv) uv cache dir 2>/dev/null ;; @go) go env GOCACHE 2>/dev/null ;; *) expand "$1" ;; esac; }

if WANT_CLN; then
DEV="$HOME/Library/Developer"
while IFS='|' read -r id lv label dir proc tool; do
  [ -n "$tool" ] && ! have "$tool" && continue
  CL_LVL=$lv clean_dir "$id" "$label" "$(expand "$dir")" "$proc"
done <<EOF2
$CACHE_DIRS
EOF2
while IFS='|' read -r id lv label tool key dir; do
  have "$tool" || continue
  dir=$(tool_dir "$dir"); [ -n "$dir" ] || continue
  cover "$dir"; CL_LVL=$lv measure_cmd "$id" "$label" "$dir" "$key"
done <<EOF2
$TOOL_CACHES
EOF2
cover "$HOME/.npm"
for ds in "$DEV/Xcode/"*DeviceSupport; do
  [ -d "$ds" ] && clean_old clean.device_support "$(basename "$ds")" "$ds" "$DS_DAYS"
done
# --- simulators, only when you pick them: runtimes (A), erasing one (B), unused ones (C). Running ones are left alone.
if have xcrun && have python3 && { task_allowed clean.sim_runtimes || task_allowed clean.sim_erase || task_allowed clean.sim_unused; }; then
  SIMS=$( { xcrun simctl list devices -j 2>/dev/null; echo '@@'; xcrun simctl runtime list -j 2>/dev/null; } | python3 -c '
import json, sys
dev_raw, rt_raw = sys.stdin.read().split("@@", 1)
try: devs = json.loads(dev_raw).get("devices", {})
except Exception: devs = {}
try: rts = json.loads(rt_raw)
except Exception: rts = {}
for rid, ds in devs.items():
    for d in ds:
        print("D", d.get("udid", ""), d.get("state", ""), rid, d.get("name", "").replace("\t", " "), sep="\t")
for uid, r in rts.items():
    if not r.get("deletable", True): continue
    ds = devs.get(r.get("runtimeIdentifier", ""), [])
    booted = any(d.get("state") == "Booted" for d in ds)
    plat = r.get("runtimeIdentifier", "").split(".")[-1].split("-")[0]
    print("R", uid, int(r.get("sizeBytes", 0)) // 1024, (r.get("lastUsedAt") or "-")[:10], len(ds), int(booted), plat, r.get("version", "?"), sep="\t")
' 2>/dev/null)
  T=$(printf '\t')
  printf '%s\n' "$SIMS" | while IFS="$T" read -r k uid kb last n booted plat ver; do
    if [ "$k" = R ] && [ "$booted" = 0 ]; then
      [ "$last" = - ] && last=$(_ never)
      echo "$uid|$kb|$last|$n|$plat $ver"
    fi
  done > "$BODY.rt"
  while IFS='|' read -r uid kb last n name; do
    cand clean.sim_runtimes 2 "$(_f 'Simulator runtime %s: last used %s, simulators: %s (Xcode downloads it again: Settings → Components)' "$name" "$last" "$n")" "$kb" cmd "simrt:$uid $kb"
  done < "$BODY.rt"
  UNUSED=""; UNAMES=""
  while IFS="$T" read -r k uid state rid name; do
    [ "$k" = D ] && [ "$state" = Shutdown ] && sim_id "$uid" 2>/dev/null || continue
    d="$DEV/CoreSimulator/Devices/$uid"; [ -d "$d" ] && [ ! -L "$d" ] || continue
    s=$(kb "$d/data")
    [ "$s" -ge 102400 ] && cand clean.sim_erase 3 "$(_f 'Erase simulator %s (%s): its apps and data are removed' "$name" "$(echo "$rid" | sed 's/.*SimRuntime\.//; s/-/ /; s/-/./g')")" "$s" cmd "simerase:$uid" "" "$d"
    [ -n "$(find "$d" -maxdepth 4 -mtime -"$SIM_DAYS" -print 2>/dev/null | head -1)" ] && continue
    UNUSED="$UNUSED $uid"; UNAMES="$UNAMES${UNAMES:+, }$name"
  done <<EOF2
$SIMS
EOF2
  [ -n "$UNUSED" ] && cand clean.sim_unused 2 "$(_f 'Simulators unused for %s+ days (%s): %s — add them again in Xcode → Devices and Simulators' "$SIM_DAYS" "$(echo $UNUSED | wc -w | tr -d ' ')" "$UNAMES")" "$(kbl "$(for u in $UNUSED; do echo "$DEV/CoreSimulator/Devices/$u"; done)")" cmd "simdel:${UNUSED# }" "" "$DEV/CoreSimulator/Devices"
  rm -f "$BODY.rt"
fi
clean_old  clean.device_logs    'iOS device logs'      "$DEV/Xcode/iOS Device Logs" 90 f
if task_allowed clean.sim_unavailable && have xcrun; then
  unav_dirs(){ grep '(unavailable' | grep -oE '[0-9A-Fa-f]{8}-([0-9A-Fa-f]{4}-){3}[0-9A-Fa-f]{12}' | sed "s|^|$1/|"; }   # simctl list → device folders in set $1
  UD=$(xcrun simctl list devices unavailable 2>/dev/null | unav_dirs "$DEV/CoreSimulator/Devices")
  UX=""   # Xcode's parallel-test clones are a device set of their own
  [ -d "$DEV/XCTestDevices" ] && UX=$(xcrun simctl --set "$DEV/XCTestDevices" list devices unavailable 2>/dev/null | unav_dirs "$DEV/XCTestDevices")
  UL=$(printf '%s\n%s\n' "$UD" "$UX" | grep .)
  [ -n "$UL" ] && cand clean.sim_unavailable 1 "$(_f 'Unavailable simulators (%s)' "$(cnt "$UL")")" "$(kbl "$UL")" cmd "sim:${UD:+default}${UX:+ tests}" '/Xcode.app/Contents/MacOS/Xcode|/usr/bin/xcodebuild( |$)' "$UL"
fi
if task_allowed clean.brew && have brew; then
  BC=$(brew --cache 2>/dev/null); cover "$BC"
  FR=$(brew cleanup -s --prune=7 -n 2>/dev/null | grep -o 'free approximately [0-9.]*[KMGT]*B' | tail -1 | awk '{print $3}')
  cand clean.brew 1 "$(_ 'Homebrew old versions & downloads')" "$( [ -n "$FR" ] && tokb "$FR" || echo 0)" cmd brew
fi
if task_allowed clean.logs; then
  OLDLOGS=$(find "$HOME/Library/Logs" -type f -mtime +30 -not -path "$LOGDIR/*" 2>/dev/null)
  if [ -n "$OLDLOGS" ]; then
    s=$(printf '%s\n' "$OLDLOGS" | tr '\n' '\0' | xargs -0 du -sk 2>/dev/null | awk '{s+=$1} END{print s+0}')
    [ "${s:-0}" -ge 1024 ] && cand clean.logs 1 "$(_f 'Old logs & crash reports (%s files)' "$(cnt "$OLDLOGS")")" "$s" rm "$OLDLOGS"
  fi
fi
cand clean.quicklook 1 "$(_ 'Quick Look cache')" 0 cmd quicklook
if task clean.reports && [ "$DRY" = 0 ]; then find "$LOGDIR" -name 'macup_*' -mtime +"$KEEP_DAYS" -delete 2>/dev/null; fi

project_roots(){ # never the home folder itself or anything above it
  echo "$PROJECT_DIRS" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | while IFS= read -r d; do
    d=$(expand "$d"); d=${d%/}
    case "$d" in ""|"$HOME") continue ;; esac
    case "$HOME/" in "$d"/*) continue ;; esac
    [ -d "$d" ] && echo "$d"
  done
}
if task_allowed clean.stale_node_modules; then
  step 'Looking for stale node_modules'
  STALE=""
  while IFS= read -r root; do
    [ -z "$root" ] && continue
    while IFS= read -r nm; do
      [ -z "$nm" ] && continue
      case "${nm#"$root"}" in */.*|*/lib/node_modules) continue ;; esac   # hidden folders, global npm installs
      proj=$(dirname "$nm")
      recent=$(find "$proj" -maxdepth 3 \( -name node_modules -o -name .git \) -prune -o -type f -mtime -"$STALE_DAYS" -print 2>/dev/null | head -1)
      [ -n "$recent" ] && continue
      STALE="$STALE$nm"$'\n'
    done <<EOF2
$(find "$root" -maxdepth 5 -type d -name node_modules -prune 2>/dev/null)
EOF2
  done <<EOF2
$(project_roots)
EOF2
  [ -n "$STALE" ] && cand clean.stale_node_modules 2 "$(_f 'Stale node_modules (%s projects untouched for %s days; npm install brings them back)' "$(cnt "$STALE")" "$STALE_DAYS")" "$(kbl "$STALE")" rm "$STALE"
fi
task_allowed clean.trash && cand clean.trash 3 "$(_ 'Trash')" "$(kb "$HOME/.Trash")" empty "$HOME/.Trash"
# --- Android, Gradle, Maven: downloaded again by the next build. Only these subfolders:
# gradle.properties, settings.xml, keystores and emulators sit next to them and are never touched.
CL_LVL=2
clean_old clean.gradle  'Old Gradle wrappers' "$HOME/.gradle/wrapper/dists" 30
for d in "$HOME/Library/Caches/Google/AndroidStudio"*; do
  [ -d "$d" ] && clean_dir clean.android "$(_f 'Android Studio cache (%s)' "${d##*/}")" "$d" '/Android Studio.app/Contents/'
done
# `mvn install` puts your own builds (often SNAPSHOTs) here; those exist nowhere else
if [ -n "$(find "$HOME/.m2/repository" -name maven-metadata-local.xml -print 2>/dev/null | head -1)" ]; then
  CL_MANUAL=1 clean_dir clean.maven 'Maven repository (has your own mvn install builds)' "$HOME/.m2/repository"
else clean_dir clean.maven 'Maven repository' "$HOME/.m2/repository"; fi
CL_LVL=""
if task_allowed clean.docker && have docker && docker info >/dev/null 2>&1; then
  BCR=$(docker system df 2>/dev/null | awk '/^Build Cache/{print $6}')
  cand clean.docker 2 "$(_ 'Docker build cache and dangling images (never containers or volumes)')" "$(tokb "${BCR:-0B}")" cmd docker
fi

# --- older patch versions of Node, Ruby, Python. The newest of each line stays, and so does
# every version named in a global setting or in a project's pin file (.nvmrc, .tool-versions, …).
if task_allowed clean.old_versions; then
  PINS=" $( { cat "$HOME/.rbenv/version" "$HOME/.pyenv/version" "$HOME/.tool-versions" "$HOME/.config/mise/config.toml" 2>/dev/null; echo
    find "$HOME/.nvm/alias" -type f 2>/dev/null | tr '\n' '\0' | xargs -0 cat 2>/dev/null   # default → lts/iron → x.y.z
    find "$HOME/.local/pipx/venvs" "$HOME/.local/share/uv/tools" "$HOME/Library/Caches/pypoetry/virtualenvs" -maxdepth 2 \
      -name pyvenv.cfg 2>/dev/null | tr '\n' '\0' | xargs -0 cat 2>/dev/null
    project_roots | while IFS= read -r r; do
      find "$r" -maxdepth 4 \( -name node_modules -o -name .git \) -prune -o -type f \( -name .nvmrc -o -name .node-version \
        -o -name .ruby-version -o -name .python-version -o -name .tool-versions -o -name mise.toml -o -name .mise.toml -o -name pyvenv.cfg \) -print 2>/dev/null
    done | head -2000 | tr '\n' '\0' | xargs -0 cat 2>/dev/null
  } | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | sort -u | tr '\n' ' ') "
  old_versions(){ # dir series(1 = major, 2 = major.minor) → older patch versions that nothing pins
    for e in "$1"/*; do [ -d "$e" ] && printf '%s\n' "${e##*/}"; done | grep -E '^v?[0-9]+\.[0-9]+\.[0-9]+$' \
      | awk -v s="$2" '{v=$0; sub(/^v/,"",v); split(v,a,"."); print (s==1 ? a[1] : a[1]"."a[2]), v, $0}' \
      | sort -k1,1 -k2,2V | awk '{if(p==$1) print last; p=$1; last=$3}' | while IFS= read -r n; do
        [ -L "$1/$n" ] && continue
        case "$PINS" in *" ${n#v} "*) continue ;; esac
        [ -n "$(ls -A "$1/$n/envs" 2>/dev/null)" ] && continue   # pyenv virtualenvs live inside
        echo "$1/$n"
      done
  }
  vm(){ # tool manager dir series
    local l; l=$(old_versions "$3" "$4"); [ -z "$l" ] && return 0
    cand clean.old_versions 2 "$(_f 'Older %s versions (%s): %s' "$1" "$2" "$(echo "$l" | sed 's|.*/v*||' | paste -sd ',' - | sed 's/,/, /g')")" "$(kbl "$l")" rm "$l"
  }
  vm Node.js nvm   "$HOME/.nvm/versions/node" 1
  vm Ruby    rbenv "$HOME/.rbenv/versions"    2
  vm Python  pyenv "$HOME/.pyenv/versions"    2
  for m in "$HOME/.local/share/mise/installs" "$HOME/.asdf/installs"; do
    for t in "$m"/*; do [ -d "$t" ] || continue; s=2; [ "${t##*/}" = node ] && s=1
      vm "${t##*/}" "$(basename "$(dirname "$m")" | sed 's/^\.//')" "$t" "$s"; done
  done
fi

# --- old browser builds left by Playwright and Puppeteer; the newest of each stays
if task_allowed clean.playwright; then
  old_builds(){ for e in "$1"/*; do [ -d "$e" ] && printf '%s\n' "${e##*/}"; done | grep -E '^.+-[0-9][0-9.]*$' | sed -E 's/^(.+)-([0-9][0-9.]*)$/\1 \2 &/' \
      | sort -k1,1 -k2,2V | awk '{if(p==$1) print last; p=$1; last=$3}' | sed "s|^|$1/|"; }
  cover "$HOME/Library/Caches/ms-playwright"; cover "$HOME/Library/Caches/ms-playwright-go"   # browsers in use stay
  L=""; for d in "$HOME/Library/Caches/ms-playwright" "$HOME/.cache/puppeteer"/*; do [ -d "$d" ] && L="$L$(old_builds "$d")"$'\n'; done
  L=$(printf '%s' "$L" | grep .)
  [ -n "$L" ] && cand clean.playwright 2 "$(_f 'Old Playwright/Puppeteer browsers (%s)' "$(cnt "$L")")" "$(kbl "$L")" rm "$L"
fi

# --- AI tools: only leftovers. Chat history, sessions and databases are never touched.
L=$(find "$HOME/.codex/.tmp" -mindepth 1 -maxdepth 1 -type d -name 'git-*' -mtime +7 2>/dev/null)
[ -n "$L" ] && [ "$(kbl "$L")" -ge 1024 ] && cand clean.ai_tools 1 "$(_f 'Codex temporary git clones (%s, older than 7 days)' "$(cnt "$L")")" "$(kbl "$L")" rm "$L"
L=$(find "$HOME/.cache/codex-runtimes" -mindepth 1 -maxdepth 1 -type d -name 'codex-runtime-install-*' -mtime +1 2>/dev/null)
[ -n "$L" ] && cand clean.ai_tools 1 "$(_ 'Unfinished Codex runtime downloads')" "$(kbl "$L")" rm "$L"

# --- editors and Electron apps (ELECTRON_APPS), browsers (BROWSERS)
dirs_in(){ # base folder, list separated by | or ; → the ones that exist, one per line
  local d; echo "$2" | tr '|;' '\n\n' | while IFS= read -r d; do
    [ -n "$d" ] && [ -d "$1/$d" ] && [ ! -L "$1/$d" ] && echo "$1/$d"; done; }
while IFS='|' read -r folder name; do
  A="$HOME/Library/Application Support/$folder"
  L=$(for b in "$A" "$A/Default" "$A/Partitions/"* "$A/Default/Partitions/"*; do
    [ -d "$b" ] && [ ! -L "$b" ] && dirs_in "$b" "$ELECTRON_CACHES"; done); [ -n "$L" ] || continue
  s=$(kbl "$L"); [ "$s" -lt 5120 ] && continue
  # Application Support/Codex belongs to ChatGPT.app, so the app name alone misses it
  cand clean.editors 1 "$(_f '%s caches' "$name")" "$s" empty "$L" "/$name.app/Contents/|user-data-dir=$A( --|/|$)"
done <<EOF2
$ELECTRON_APPS
EOF2
while IFS='|' read -r name app dirs; do   # Safari's cache needs Full Disk Access; skipped
  L=$(dirs_in "$HOME/Library/Caches" "$dirs"); [ -n "$L" ] || continue
  s=$(kbl "$L"); [ "$s" -lt 5120 ] && continue
  cand clean.browsers 3 "$(_f '%s cache' "$name")" "$s" empty "$L" "/$app.app/Contents/"
done <<EOF2
$BROWSERS
EOF2

# --- other big folders in ~/Library/Caches (100 MB+), except macOS's own and what is already listed above
if task_allowed clean.app_caches; then
  du -sk "$HOME/Library/Caches/"* 2>/dev/null | sort -rn | while read -r s e; do
    [ "$s" -lt 102400 ] && break
    b=${e##*/}; [ -d "$e" ] && [ ! -L "$e" ] || continue
    case "$b" in com.apple.*|Adobe\ Camera\ Raw*) continue ;; esac
    printf '%s' "$COVERED" | grep -qxF "$e" && continue
    printf '%s' "$COVERED" | grep -qF "$e/" && continue
    printf '%s\t%s\n' "$s" "$e"
  done > "$BODY.caches"
  while IFS="$(printf '\t')" read -r s e; do
    cand clean.app_caches 3 "$(_f 'App cache: %s' "${e##*/}")" "$s" empty "$e"
  done < "$BODY.caches"; rm -f "$BODY.caches"
fi

# what a plain `macup all` would free, and what more is there
for ((i = 0; i < C_N; i++)); do
  visible "$i" || continue
  if [ "${C_AUTO[i]}" = 1 ] && [ "${C_LVL[i]}" -le "$LEVEL" ]; then POT_AUTO=$((POT_AUTO + C_KB[i])); else POT_MORE=$((POT_MORE + C_KB[i])); fi
done
if CLEAN; then
  section "Cleanup"
  for ((i = 0; i < C_N; i++)); do [ "${C_AUTO[i]}" = 1 ] && [ "${C_LVL[i]}" -le "$LEVEL" ] && exec_cand "$i"; done
  [ "$DID_CLEAN" = 0 ] && info 'Nothing to clean at level %s' "$(lvl_word "$LEVEL")"
else
  section "What can be cleaned"
  list_cands
fi
fi # WANT_CLN


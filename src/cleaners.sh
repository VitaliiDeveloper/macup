# ---------------------------------------------------------------- what macup cleans
# To support another cache, add a line to one of these tables. Levels: 1 safe, 2 standard, 3 aggressive.

# Folders whose contents can simply be deleted (the folder itself stays).
# task | level | label | folder (~ = home) | skipped while this runs (pgrep -f, or a name from busy_pat: xcode, cargo, …) | only if this tool exists
CACHE_DIRS='clean.derived_data|1|Xcode DerivedData|~/Library/Developer/Xcode/DerivedData|xcode|
clean.xcode_previews|1|SwiftUI previews|~/Library/Developer/Xcode/UserData/Previews|xcode|
clean.sim_caches|1|Simulator caches|~/Library/Developer/CoreSimulator/Caches||
clean.spm|1|SwiftPM cache|~/Library/Caches/org.swift.swiftpm||
clean.cocoapods|1|CocoaPods cache|~/Library/Caches/CocoaPods||
clean.carthage|1|Carthage cache|~/Library/Caches/org.carthage.CarthageKit||
clean.yarn|1|Yarn cache|~/Library/Caches/Yarn||yarn
clean.pnpm|1|pnpm metadata cache|~/Library/Caches/pnpm||
clean.npm|1|node-gyp headers|~/Library/Caches/node-gyp||
clean.npm|2|npx cache|~/.npm/_npx|npx|
clean.bun|1|Bun install cache|~/.bun/install/cache||
clean.poetry|1|Poetry cache|~/Library/Caches/pypoetry/cache|poetry|
clean.poetry|1|Poetry downloads|~/Library/Caches/pypoetry/artifacts|poetry|
clean.cargo|2|Cargo registry downloads|~/.cargo/registry/cache|cargo|
clean.cargo|2|Cargo registry sources|~/.cargo/registry/src|cargo|
clean.cargo|2|Cargo git checkouts|~/.cargo/git/checkouts|cargo|
clean.cargo|2|Cargo git sources|~/.cargo/git/db|cargo|
clean.gradle|2|Gradle caches|~/.gradle/caches|GradleDaemon|
clean.android|2|Android cache|~/.android/cache||'

# Caches cleaned by the tool's own command (it knows what is still in use). The folder is measured
# before and after; @tool means "ask the tool where its cache is".
# task | level | label | tool | command key (see run_key) | folder
TOOL_CACHES='clean.npm|1|npm cache|npm|npm|~/.npm/_cacache
clean.pnpm|1|pnpm store|pnpm|pnpm|@pnpm
clean.pip|1|pip cache|pip3|pip|~/Library/Caches/pip
clean.uv|1|uv cache|uv|uv|@uv
clean.go|1|Go build cache|go|go|@go
clean.go_mod|2|Go module cache|go|gomod|@gomod'

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
Postman|Postman
Slack|Slack
discord|Discord
Notion|Notion
obsidian|Obsidian
Signal|Signal'
ELECTRON_CACHES='Cache|CachedData|Code Cache|GPUCache|CachedExtensionVSIXs|logs|DawnGraphiteCache|DawnWebGPUCache|GraphiteDawnCache|GrShaderCache|ShaderCache'

# Browsers: cache only, in ~/Library/Caches; never profiles, history or passwords.
# name | app name (skipped while it runs) | cache folders in ~/Library/Caches, separated by ;
BROWSERS='Arc|Arc|Arc
Google Chrome|Google Chrome|Google/Chrome
Firefox|Firefox|Firefox
Microsoft Edge|Microsoft Edge|Microsoft Edge
Brave|Brave Browser|BraveSoftware
Opera|Opera|com.operasoftware.Opera
Vivaldi|Vivaldi|Vivaldi'

tool_dir(){ case "$1" in @pnpm) pnpm store path 2>/dev/null ;; @uv) uv cache dir 2>/dev/null ;; @go) go env GOCACHE 2>/dev/null ;; @gomod) go env GOMODCACHE 2>/dev/null ;; *) expand "$1" ;; esac; }

if WANT_CLN; then
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
# Deno keeps localStorage and the databases of Deno.openKv() in location_data, next to its caches: that folder stays
DN="$HOME/Library/Caches/deno"
if [ -d "$DN" ] && [ ! -L "$DN" ]; then
  L=$(find "$DN" -mindepth 1 -maxdepth 1 ! -name location_data 2>/dev/null); s=$(kbl "$L")
  [ "$s" -ge 5120 ] && CL_KEY=deno cand clean.deno 1 "$(_ 'Deno cache')" "$s" rm "$L" "$(busy_pat deno)"
  cover "$DN/location_data"
fi
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
  [ -n "$UL" ] && cand clean.sim_unavailable 1 "$(_f 'Unavailable simulators (%s)' "$(cnt "$UL")")" "$(kbl "$UL")" cmd "sim:${UD:+default}${UX:+ tests}" "$XCODE_BUSY" "$UL"
fi
if task_allowed clean.brew && have brew; then
  BC=$(brew --cache 2>/dev/null); cover "$BC"
  FR=$(brew cleanup -s --prune=7 -n 2>/dev/null | grep -o 'free approximately [0-9.]*[KMGT]*B' | tail -1 | awk '{print $3}')
  cand clean.brew 1 "$(_ 'Homebrew old versions & downloads')" "$( [ -n "$FR" ] && tokb "$FR" || echo 0)" cmd brew
fi
if task_allowed clean.logs; then
  # npm keeps a log per failed command, a Gradle daemon one per start: nobody reads them a month later
  OLDLOGS=$( { find "$HOME/Library/Logs" -type f -mtime +30 -not -path "$LOGDIR/*" 2>/dev/null
               find "$HOME/.npm/_logs" "$HOME/.gradle/daemon" -type f -name '*.log' -mtime +30 2>/dev/null; } )
  if [ -n "$OLDLOGS" ]; then
    s=$(printf '%s\n' "$OLDLOGS" | tr '\n' '\0' | xargs -0 du -sk 2>/dev/null | awk '{s+=$1} END{print s+0}')
    [ "${s:-0}" -ge 1024 ] && CL_KEY=logs cand clean.logs 1 "$(_f 'Old logs & crash reports (%s files)' "$(cnt "$OLDLOGS")")" "$s" rm "$OLDLOGS"
  fi
fi
cand clean.quicklook 1 "$(_ 'Quick Look cache')" 0 cmd quicklook
# macup's own reports are tidied on every run, before this one starts (tidy_own)

# --- build folders in projects nobody touched for stale_project_days, only when you pick or enable them.
# A folder counts only next to the file that makes it again (artifact_ok), never when git tracks files in it (a committed Pods),
# and never when it was built recently itself: someone still runs that project.
if task_allowed clean.stale_node_modules || task_allowed clean.stale_artifacts; then
  step 'Looking for stale build folders'
  STALE=""; STALE_ART=""
  NAMEX=$(for n in $ARTIFACT_NAMES; do printf -- '-o -name %s ' "$n"; done)
  while IFS= read -r root; do
    [ -z "$root" ] && continue
    # shellcheck disable=SC2086 # NAMEX is a list of find arguments
    ARTS=$(find "$root" -maxdepth 5 -type d \( -name .git $NAMEX \) -prune -print 2>/dev/null | grep -v '/\.git$')
    while IFS= read -r a; do
      [ -z "$a" ] && continue
      rel=${a#"$root"}
      case "${rel%/*}" in */.*) continue ;; esac   # inside a hidden folder
      case "$rel" in */lib/node_modules) continue ;; esac   # global npm installs
      artifact_ok "$a" || continue
      recent=$(find "${a%/*}" -maxdepth 3 \( -name node_modules -o -name .git -o -path "$a" \) -prune -o -type f -mtime -"$STALE_DAYS" -print 2>/dev/null | head -1)
      [ -n "$recent" ] && continue
      [ -n "$(find "$a" -maxdepth 2 -mtime -"$STALE_DAYS" -print 2>/dev/null | head -1)" ] && continue
      if [ "${a##*/}" = node_modules ]; then STALE="$STALE$a"$'\n'
      else
        # anything but "not a git repository" keeps the folder: tracked files, or a repository git refuses to read
        have git || continue
        [ -n "$(git -C "$a" ls-files . 2>&1 | grep -v 'not a git repository' | head -1)" ] && continue
        STALE_ART="$STALE_ART$a"$'\n'
      fi
    done <<EOF2
$ARTS
EOF2
  done <<EOF2
$(project_roots)
EOF2
  [ -n "$STALE" ] && CL_KEY=stale_nm cand clean.stale_node_modules 2 "$(_f 'Stale node_modules (%s projects untouched for %s days; npm install brings them back)' "$(cnt "$STALE")" "$STALE_DAYS")" "$(kbl "$STALE")" rm "$STALE"
  if [ -n "$STALE_ART" ]; then
    AL=$(printf '%s' "$STALE_ART" | head -4 | while IFS= read -r a; do tildify "$a"; done | paste -sd, - | sed 's/,/, /g'); AN=$(cnt "$STALE_ART")
    [ "$AN" -gt 4 ] && AL="$AL +$((AN - 4))"
    CL_KEY=stale_art cand clean.stale_artifacts 2 "$(_f 'Stale build folders (%s, projects untouched for %s days; the next build makes them again): %s' "$AN" "$STALE_DAYS" "$AL")" "$(kbl "$STALE_ART")" rm "$STALE_ART"
  fi
fi
# --- provisioning profiles past their date sign nothing; Xcode downloads the ones it manages again
if task_allowed clean.profiles && have python3; then
  L=$(python3 - "$HOME/Library/MobileDevice/Provisioning Profiles" "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles" <<'PY' 2>/dev/null
import datetime, os, plistlib, sys
now = datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)
for d in sys.argv[1:]:
    if not os.path.isdir(d) or os.path.islink(d): continue
    for n in sorted(os.listdir(d)):
        p = os.path.join(d, n)
        if not n.endswith((".mobileprovision", ".provisionprofile")) or os.path.islink(p) or not os.path.isfile(p): continue
        try:
            raw = open(p, "rb").read(); a = raw.index(b"<?xml"); b = raw.index(b"</plist>", a) + 8
            exp = plistlib.loads(raw[a:b]).get("ExpirationDate")
        except Exception: continue   # unreadable: not ours to judge
        if isinstance(exp, datetime.datetime) and exp.replace(tzinfo=None) < now: print(p)
PY
)
  [ -n "$L" ] && CL_KEY=profiles cand clean.profiles 1 "$(_f 'Expired provisioning profiles (%s)' "$(cnt "$L")")" "$(kbl "$L")" rm "$L"
fi
# without Full Disk Access the terminal cannot even list the Trash: say so instead of a silent 0
if task_allowed clean.trash; then
  if [ -d "$HOME/.Trash" ] && ! ls "$HOME/.Trash" >/dev/null 2>&1; then task clean.trash && warn 'Trash: cannot be read — give your terminal Full Disk Access (System Settings → Privacy & Security)'
  else cand clean.trash 3 "$(_ 'Trash')" "$(kb "$HOME/.Trash")" empty "$HOME/.Trash"; fi
fi
# --- Android, Gradle, Maven: downloaded again by the next build. Only these subfolders:
# gradle.properties, settings.xml, keystores and emulators sit next to them and are never touched.
CL_LVL=2
clean_old clean.gradle  'Old Gradle wrappers' "$HOME/.gradle/wrapper/dists" 30
for d in "$HOME/Library/Caches/Google/AndroidStudio"*; do
  [ -d "$d" ] && clean_dir clean.android "$(_f 'Android Studio cache (%s)' "${d##*/}")" "$d" '/Android Studio.app/Contents/'
done
# JetBrains IDEs keep one cache folder per product and version; the IDE re-indexes after it is emptied.
# The app names differ (IntelliJ IDEA, PyCharm, …), so an open IDE is found by its open files (lsof).
for d in "$HOME/Library/Caches/JetBrains"/*; do
  [ -d "$d" ] && [ ! -L "$d" ] || continue
  s=$(kb "$d"); [ "$s" -lt 5120 ] && continue
  cand clean.jetbrains 2 "$(_f 'JetBrains cache (%s)' "${d##*/}")" "$s" empty "$d" "" "" "$d"
done
# `mvn install` puts your own builds (often SNAPSHOTs) here; those exist nowhere else
if [ -n "$(find "$HOME/.m2/repository" -name maven-metadata-local.xml -print 2>/dev/null | head -1)" ]; then
  CL_MANUAL=1 clean_dir clean.maven 'Maven repository (has your own mvn install builds)' "$HOME/.m2/repository" maven
else clean_dir clean.maven 'Maven repository' "$HOME/.m2/repository" maven; fi
CL_LVL=""
# --- Docker. Volumes hold databases and are never touched. Images and stopped containers only when you pick them.
if have docker && { task_allowed clean.docker || task_allowed clean.docker_images || task_allowed clean.docker_containers; } && tl 20 docker info >/dev/null 2>&1; then
  DDF=$(tl 30 docker system df --format '{{.Type}}|{{.Reclaimable}}' 2>/dev/null)
  ddf(){ tokb10 "$(printf '%s\n' "$DDF" | awk -F'|' -v t="$1" '$1==t{print $2}' | awk '{print $1}')"; }   # "1.2GB (50%)" → KB
  cand clean.docker 2 "$(_ 'Docker build cache and dangling images (never volumes)')" "$(ddf 'Build Cache')" cmd docker
  s=$(ddf Images); [ "${s:-0}" -ge 1024 ] && cand clean.docker_images 2 "$(_ 'Docker images no container uses (docker pulls or builds them again)')" "$s" cmd dockerimg
  n=$(tl 30 docker ps -aq -f status=exited -f status=created -f status=dead 2>/dev/null | grep -c .)
  [ "$n" -gt 0 ] && cand clean.docker_containers 3 "$(_f 'Stopped Docker containers (%s): files saved inside them are lost, volumes stay' "$n")" "$(ddf Containers)" cmd dockerct
fi
# --- Homebrew packages that came only as dependencies of something already removed
if task_allowed clean.brew_autoremove && have brew; then
  AR=$(tl 60 brew autoremove --dry-run 2>/dev/null | grep -v '^==>' | grep . | paste -sd, - | sed 's/,/, /g')
  [ -n "$AR" ] && cand clean.brew_autoremove 2 "$(_f 'Homebrew packages nothing needs any more: %s' "$AR")" 0 cmd brewauto
fi

# --- older patch versions of Node, Ruby, Python. The newest of each line stays, and so does
# every version named in a global setting or in a project's pin file (.nvmrc, .tool-versions, …).
if task_allowed clean.old_versions; then
  PINSRC=$( { cat "$HOME/.rbenv/version" "$HOME/.pyenv/version" "$HOME/.tool-versions" "$HOME/.config/mise/config.toml" 2>/dev/null; echo
    find "$HOME/.nvm/alias" -type f 2>/dev/null | tr '\n' '\0' | xargs -0 cat 2>/dev/null   # default → lts/iron → x.y.z
    # Volta's default Node; fnm's aliases and the version each open shell uses are links to the version folder
    cat "$HOME/.volta/tools/user/platform.json" 2>/dev/null; echo
    for a in "$HOME/.local/share/fnm/aliases"/* "$HOME/.fnm/aliases"/* "$HOME/.local/state/fnm_multishells"/*; do [ -L "$a" ] && readlink "$a"; done
    # pipx, uv tools, poetry, pipenv, virtualenvwrapper, hatch
    find "$HOME/.local/pipx/venvs" "$HOME/.local/share/uv/tools" "$HOME/Library/Caches/pypoetry/virtualenvs" \
      "$HOME/.local/share/virtualenvs" "$HOME/.virtualenvs" "$HOME/Library/Application Support/hatch/env/virtual" -maxdepth 3 \
      -name pyvenv.cfg 2>/dev/null | tr '\n' '\0' | xargs -0 cat 2>/dev/null
    project_roots | while IFS= read -r r; do
      find "$r" -maxdepth 4 \( -name node_modules -o -name .git \) -prune -o -type f \( -name .nvmrc -o -name .node-version \
        -o -name .ruby-version -o -name .python-version -o -name .tool-versions -o -name mise.toml -o -name .mise.toml -o -name pyvenv.cfg \) -print 2>/dev/null
    done | head -2000 | tr '\n' '\0' | xargs -0 cat 2>/dev/null
    # package.json: "volta": {"node": "20.5.0"} and "engines": {"node": "20.5.0"}; never its dependency versions
    project_roots | while IFS= read -r r; do
      find "$r" -maxdepth 4 \( -name node_modules -o -name .git \) -prune -o -type f -name package.json -print 2>/dev/null
    done | head -2000 | tr '\n' '\0' | xargs -0 grep -hE '"node"[[:space:]]*:' 2>/dev/null
  } )
  PINS=" $(printf '%s\n' "$PINSRC" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | sort -u | tr '\n' ' ') "
  # a pin without the patch ("20.5" in an .nvmrc) means the newest installed 20.5.x
  PINS2=" $(printf '%s\n' "$PINSRC" | grep -oE '(^|[^0-9.])[0-9]+\.[0-9]+([^0-9.]|$)' | grep -oE '[0-9]+\.[0-9]+' | sort -u | tr '\n' ' ') "
  old_versions(){ # dir series(1 = major, 2 = major.minor) → older patch versions that nothing pins
    for e in "$1"/*; do [ -d "$e" ] && printf '%s\n' "${e##*/}"; done | grep -E '^v?[0-9]+\.[0-9]+\.[0-9]+$' \
      | awk -v s="$2" '{v=$0; sub(/^v/,"",v); split(v,a,"."); print (s==1 ? a[1] : a[1]"."a[2]), v, $0}' \
      | sort -k1,1 -k2,2V | awk '{if(p==$1) print last; p=$1; last=$3}' | while IFS= read -r n; do
        [ -L "$1/$n" ] && continue
        case "$PINS" in *" ${n#v} "*) continue ;; esac
        mm=${n#v}; mm=${mm%.*}
        case "$PINS2" in *" $mm "*)
          [ "$(for e in "$1"/*; do printf '%s\n' "${e##*/}"; done | sed 's/^v//' | grep -E "^${mm/./\\.}\.[0-9]+$" | sort -V | tail -1)" = "${n#v}" ] && continue ;;
        esac
        [ -n "$(ls -A "$1/$n/envs" 2>/dev/null)" ] && continue   # pyenv virtualenvs live inside
        echo "$1/$n"
      done
  }
  vm(){ # tool manager dir series
    local l; l=$(old_versions "$3" "$4"); [ -z "$l" ] && return 0
    CL_KEY="ver|$3" cand clean.old_versions 2 "$(_f 'Older %s versions (%s): %s' "$1" "$2" "$(echo "$l" | sed 's|.*/v*||' | paste -sd ',' - | sed 's/,/, /g')")" "$(kbl "$l")" rm "$l"
  }
  vm Node.js nvm   "$HOME/.nvm/versions/node" 1
  vm Node.js fnm   "$HOME/.local/share/fnm/node-versions" 1
  vm Node.js fnm   "$HOME/.fnm/node-versions" 1
  vm Node.js Volta "$HOME/.volta/tools/image/node" 1
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
  # Cypress keeps every version it ever ran, about 600 MB each
  CY="$HOME/Library/Caches/Cypress"; cover "$CY"
  [ -d "$CY" ] && [ ! -L "$CY" ] && L="$L$(for e in "$CY"/*; do [ -d "$e" ] && [ ! -L "$e" ] && printf '%s\n' "${e##*/}"; done | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | sed '$d' | sed "s|^|$CY/|")"$'\n'
  L=$(printf '%s' "$L" | grep .)
  [ -n "$L" ] && CL_KEY=browsers cand clean.playwright 2 "$(_f 'Old Playwright, Puppeteer and Cypress builds (%s)' "$(cnt "$L")")" "$(kbl "$L")" rm "$L"
fi

# --- AI tools: only leftovers. Chat history, sessions and databases are never touched.
L=$(find "$HOME/.codex/.tmp" -mindepth 1 -maxdepth 1 -type d -name 'git-*' -mtime +7 2>/dev/null)
[ -n "$L" ] && [ "$(kbl "$L")" -ge 1024 ] && CL_KEY=codex_tmp cand clean.ai_tools 1 "$(_f 'Codex temporary git clones (%s, older than 7 days)' "$(cnt "$L")")" "$(kbl "$L")" rm "$L"
L=$(find "$HOME/.cache/codex-runtimes" -mindepth 1 -maxdepth 1 -type d -name 'codex-runtime-install-*' -mtime +1 2>/dev/null)
[ -n "$L" ] && CL_KEY=codex_rt cand clean.ai_tools 1 "$(_ 'Unfinished Codex runtime downloads')" "$(kbl "$L")" rm "$L"
# agy update keeps the replaced binary next to the new one
L=$(find "$HOME/.local/bin" -maxdepth 1 -type f -name 'agy.*.old' 2>/dev/null)
[ -n "$L" ] && CL_KEY=agy_old cand clean.ai_tools 1 "$(_ 'Old Antigravity CLI versions left by its updates')" "$(kbl "$L")" rm "$L"

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

# --- any other Chromium, Electron or Firefox cache, found by its layout instead of a name in the tables:
# in Application Support a cache folder (ELECTRON_CACHES) next to Chromium's own files; in ~/Library/Caches the
# name is enough (cache2 is Firefox's). A browser (History next to it) is aggressive, an app safe. Never inside an
# .app or an updater's folder: ShipIt and Sparkle keep downloaded updates there until they are installed.
# Skipped while any process has a file open in the app's folders (lsof); the tables still give the known names.
if have python3; then
  GEN=$(NAMES=$ELECTRON_CACHES APPS=$ELECTRON_APPS BRS=$BROWSERS COVERED=$COVERED python3 - "$HOME/Library/Application Support" "$HOME/Library/Caches" <<'PY' 2>/dev/null
import os, sys
A, K = sys.argv[1], sys.argv[2]
names = set(os.environ["NAMES"].split("|"))
covered = [c for c in os.environ["COVERED"].split("\n") if c]
apps = dict(l.split("|", 1) for l in os.environ["APPS"].split("\n") if "|" in l)
browsers = {d: f[0] for f in (l.split("|") for l in os.environ["BRS"].split("\n")) if len(f) > 2 for d in f[2].split(";")}
has = lambda p, n: os.path.exists(os.path.join(p, n))
def chromium(p):
    return has(p, "Local State") or (has(p, "Preferences") and any(has(p, n) for n in ("Cookies", "TransportSecurity", "Network Persistent State", "DIPS")))
groups = {}
def record(root, path):
    if any(path == c or path.startswith(c + "/") for c in covered): return
    top = os.path.relpath(path, root).split(os.sep)[0]
    prof = os.path.dirname(path)
    aprof = prof if root == A else os.path.join(A, os.path.relpath(prof, K))
    udr = aprof
    while udr.startswith(A + os.sep) and not has(udr, "Local State"): udr = os.path.dirname(udr)
    key = os.path.relpath(udr, A) if udr.startswith(A + os.sep) else top
    if key.endswith("/User Data"): key = key[: -len("/User Data")]
    if top in apps: kind, name = "app", apps[top]
    else:
        name = browsers.get(key) or browsers.get(top) or (key.replace("/", " ") if key.count("/") < 2 else top)
        browser = path.endswith("/cache2") or has(aprof, "History") or has(aprof, "Default/History") or has(udr, "Default/History")
        kind = "browser" if browser else "app"
    g = groups.setdefault((kind, name), (set(), {os.path.join(A, top), os.path.join(K, top)}))
    g[0].add(path)
for root in (A, K):
    for dp, dns, _ in os.walk(root):
        depth = 0 if dp == root else os.path.relpath(dp, root).count(os.sep) + 1
        keep = []
        for d in dns:
            p = os.path.join(dp, d)
            if os.path.islink(p) or d.endswith((".app", ".ShipIt")) or d == "org.sparkle-project.Sparkle": continue
            if depth == 0 and (d.startswith("com.apple.") or d == "macup"): continue
            if d in names or (d == "cache2" and root == K):
                if depth > 0 and (root == K or (d != "cache2" and chromium(dp))): record(root, p)
                continue
            if depth < 5: keep.append(d)
        dns[:] = keep
for (kind, name), (paths, opened) in sorted(groups.items()):
    print("3" if kind == "browser" else "1", kind, name, "\x1f".join(sorted(opened)), "\x1f".join(sorted(paths)), sep="\t")
PY
)
  while IFS=$'\t' read -r lv kind name opened paths; do
    [ -n "$paths" ] || continue
    L=$(printf '%s' "$paths" | tr '\037' '\n'); O=$(printf '%s' "$opened" | tr '\037' '\n')
    s=$(kbl "$L"); [ "$s" -lt 5120 ] && continue
    if [ "$kind" = browser ]; then id=clean.browsers; lbl=$(_f '%s cache' "$name"); else id=clean.editors; lbl=$(_f '%s caches' "$name"); fi
    cand_more "$lbl" "$lv" "$s" "$L" "$O" || cand "$id" "$lv" "$lbl" "$s" empty "$L" "" "" "$O"
  done <<EOF2
$GEN
EOF2
fi

# --- other big folders in ~/Library/Caches (100 MB+), except macOS's own and what is already listed above
if task_allowed clean.app_caches; then
  du -sk "$HOME/Library/Caches/"* 2>/dev/null | sort -rn | while read -r s e; do
    [ "$s" -lt 102400 ] && break
    b=${e##*/}; [ -d "$e" ] && [ ! -L "$e" ] || continue
    case "$b" in com.apple.*|Adobe\ Camera\ Raw*|*.ShipIt) continue ;; esac
    printf '%s' "$COVERED" | grep -qxF "$e" && continue
    printf '%s' "$COVERED" | grep -qF "$e/" && continue
    # not a cache whatever the folder is called: Poetry keeps its virtualenvs in ~/Library/Caches/pypoetry
    [ -n "$(find "$e" -maxdepth 3 -name pyvenv.cfg -print 2>/dev/null | head -1)" ] && continue
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
if CLEAN && [ -n "$PICK" ]; then
  # --pick: the keys a check gave, chosen by a person in another program; that choice is the confirmation
  section "Cleanup"
  for ((i = 0; i < C_N; i++)); do case "$PICK" in *",${C_KEY[i]},"*) exec_cand "$i"; PICK=${PICK/,${C_KEY[i]},/,} ;; esac; done
  GONE=$(printf '%s' "$PICK" | tr ',' '\n' | grep . | paste -sd, - | sed 's/,/, /g')
  [ -n "$GONE" ] && err 'Not cleaned, no longer there: %s — run macup check again' "$GONE"
elif CLEAN; then
  section "Cleanup"
  for ((i = 0; i < C_N; i++)); do [ "${C_AUTO[i]}" = 1 ] && [ "${C_LVL[i]}" -le "$LEVEL" ] && exec_cand "$i"; done
  [ "$DID_CLEAN" = 0 ] && info 'Nothing to clean at level %s' "$(lvl_word "$LEVEL")"
else
  section "What can be cleaned"
  list_cands
fi
fi # WANT_CLN


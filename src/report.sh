# ================================================================ SIZES (never deleted)
if task check.sizes; then
  section "Not touched by macup"
  kb_get "$DEV/Xcode/Archives"; s=$KB
  if [ "$s" -gt 5242880 ]; then warn 'Xcode Archives: %s — delete old builds in Xcode → Organizer (keep ones you need to symbolicate crashes)' "$(hum "$s")"
  elif [ "$s" -gt 0 ]; then info 'Xcode Archives: %s' "$(hum "$s")"; fi
  kb_get "$DEV/CoreSimulator/Devices"; s=$KB; [ "$s" -gt 0 ] && info 'Simulator devices: %s (Xcode → Window → Devices and Simulators)' "$(hum "$s")"
  s=$(kb "$HOME/.pub-cache");          [ "$s" -gt 0 ] && info 'Flutter pub-cache: %s (full reset: dart pub cache clean)' "$(hum "$s")"
  s=$(kbl "$HOME/.codex/sessions"$'\n'"$HOME/.codex/archived_sessions"$'\n'"$(ls -d "$HOME/.codex/"*.sqlite 2>/dev/null)"$'\n'"$HOME/.codex/sqlite")
  [ "$s" -ge 102400 ] && info 'Codex chat history: %s (not a cache; delete old chats in Codex itself)' "$(hum "$s")"
  s=$(kb "$HOME/.claude/projects"); [ "$s" -ge 102400 ] && info 'Claude Code chat history: %s (not a cache; Claude Code deletes transcripts older than cleanupPeriodDays, 30 days by default)' "$(hum "$s")"
  # the virtual machine Cowork runs in: a whole disk that Claude.app downloads again when it is gone
  s=$(kb "$HOME/Library/Application Support/Claude/vm_bundles"); [ "$s" -ge 1048576 ] && info 'Claude Cowork virtual machine: %s (not a cache; Claude.app downloads it again if it is removed)' "$(hum "$s")"
  s=$(kbl "$HOME/.cache/huggingface"$'\n'"$HOME/.ollama/models"$'\n'"$HOME/.lmstudio/models")
  [ "$s" -ge 102400 ] && info 'AI models (Hugging Face, Ollama, LM Studio): %s' "$(hum "$s")"
  s=$(kbl "$HOME/Library/Android/sdk"$'\n'"$HOME/.android/avd")
  [ "$s" -ge 102400 ] && info 'Android SDK and emulators: %s (Android Studio → SDK Manager, Device Manager)' "$(hum "$s")"
  kb_get "$HOME/Library/Caches"; s=$KB; [ "$s" -gt 0 ] && info 'App caches (~/Library/Caches): %s — macOS trims these itself when space is low' "$(hum "$s")"
  # backups of iPhones and iPads made in Finder; Docker Desktop's disk image only grows (du counts what it really takes)
  s=$(kb "$HOME/Library/Application Support/MobileSync/Backup")
  [ "$s" -ge 102400 ] && info 'iPhone and iPad backups: %s (Finder → your device → Manage Backups)' "$(hum "$s")"
  s=$(kbl "$(ls -d "$HOME/Library/Containers/com.docker.docker/Data/vms"/*/data/Docker.raw 2>/dev/null)")
  [ "$s" -ge 102400 ] && info 'Docker disk image: %s (Docker Desktop → Settings → Resources; it shrinks after: docker system prune)' "$(hum "$s")"
  # virtual machines are whole disks: only their app knows which one is still needed
  s=$(kbl "$HOME/.colima"$'\n'"$HOME/.lima"$'\n'"$HOME/.local/share/containers/podman/machine"$'\n'"$HOME/.minikube"$'\n'"$HOME/Parallels"$'\n'"$HOME/Virtual Machines.localized")
  [ "$s" -ge 102400 ] && info 'Virtual machines (Colima, Lima, Podman, minikube, Parallels, VMware): %s — delete the ones you no longer use in their own app' "$(hum "$s")"
  # a crashed program can leave a copy of its memory in /cores, gigabytes each, and nothing ever removes them
  s=$(kb /cores); [ "$s" -ge 102400 ] && warn 'Core dumps in /cores: %s — leftovers of crashed programs; remove them with: sudo rm /cores/core.*' "$(hum "$s")"
  if [ -d "$HOME/.Trash" ] && ! ls "$HOME/.Trash" >/dev/null 2>&1; then
    task clean.trash || info 'Trash: cannot be read — give your terminal Full Disk Access (System Settings → Privacy & Security)'
  elif ! task clean.trash; then
    s=$(kb "$HOME/.Trash")
    if [ "$s" -gt 2097152 ]; then warn 'Trash: %s — empty it' "$(hum "$s")"; elif [ "$s" -gt 0 ]; then info 'Trash: %s' "$(hum "$s")"; fi
  fi
fi

# ================================================================ VIDEO & PHOTO (measured only)
# Their caches are rebuilt only by re-rendering, which can take hours, so macup only shows
# where the space is and the app's own button to clear it. Folders are read only if the app is installed.
if task check.creative; then
  section "Video & photo"
  if [ -d "/Applications/Final Cut Pro.app" ] && [ -d "$HOME/Movies" ]; then
    s=$(kbl "$(find "$HOME/Movies" -maxdepth 4 -type d -name 'Render Files' -path '*.fcpbundle/*' -prune 2>/dev/null)")
    [ "$s" -ge 102400 ] && info 'Final Cut Pro render files: %s — Final Cut: File → Delete Generated Library Files' "$(hum "$s")"
  fi
  s=$(kbl "$HOME/Library/Application Support/Adobe/Common/Media Cache Files"$'\n'"$HOME/Library/Application Support/Adobe/Common/Media Cache")
  [ "$s" -ge 102400 ] && info 'Adobe media cache (Premiere, After Effects): %s — Premiere: Settings → Media Cache → Delete' "$(hum "$s")"
  if [ -d "/Applications/DaVinci Resolve" ]; then
    s=$(kb "$HOME/Movies/CacheClip")
    [ "$s" -ge 102400 ] && info 'DaVinci Resolve render cache: %s — Resolve: Playback → Delete Render Cache' "$(hum "$s")"
  fi
  if ls -d /Applications/Adobe\ Lightroom\ Classic* >/dev/null 2>&1 && [ -d "$HOME/Pictures" ]; then
    s=$(kbl "$(find "$HOME/Pictures" -maxdepth 4 -type d -name '*Previews.lrdata' -prune 2>/dev/null)")
    [ "$s" -ge 102400 ] && info 'Lightroom Classic previews: %s — Lightroom: Library → Previews → Discard 1:1 Previews' "$(hum "$s")"
  fi
  s=$(kbl "$(ls -d "$HOME/Library/Caches/Adobe Camera Raw"* 2>/dev/null)")
  [ "$s" -ge 102400 ] && info 'Camera Raw cache: %s — Photoshop: Settings → Camera Raw → Performance → Purge Cache' "$(hum "$s")"
fi

# ================================================================ STARTUP
if task check.startup; then
  section "Startup items"
  leftovers_scan
  AG=""
  for f in "$HOME"/Library/LaunchAgents/*.plist "$LO_SYS"/LaunchAgents/*.plist "$LO_SYS"/LaunchDaemons/*.plist; do
    [ -f "$f" ] || continue
    b=$(basename "$f" .plist); case "$b" in com.apple.*) continue ;; esac
    AG="$AG$b"$'\n'
  done
  info 'Third-party background services: %s (full list in the report)' "$(cnt "$AG")"
  printf '%s' "$AG" | while IFS= read -r l; do [ -n "$l" ] && mdonly "$l"; done
  LO=""
  for ((i = 0; i < O_N; i++)); do
    case "${O_REASON[i]}" in
      broken)  info '%s cannot be read (not a valid plist)' "$(tildify "${O_PLIST[i]}")"; continue ;;
      gone)    r=$(_ 'app is not installed') ;;
      missing) r=$(_ 'its program is gone') ;;
      empty)   r=$(_ 'empty file') ;;
    esac
    LO="$LO${O_NAME[i]} · ${O_LABEL[i]:-$(basename "${O_PLIST[i]}" .plist)} — $r"$'\n'
    [ "${O_SYS[i]}" = 1 ] && { ! lo_interactive || ! lo_sys_ok "$i"; } && LO="$LO$(sudo_cmds "$i" | sed 's/^/    /')"$'\n'
  done
  if [ -n "$LO" ]; then
    warn 'Leftovers of deleted apps: %s (macup check lets you pick them)' "$(cnt "$LO")"
    lines "$LO"
  fi
  info 'Login items: System Settings → General → Login Items & Extensions'
fi

# ================================================================ DEEP
if [ "$DEEP" = 1 ]; then
  section "Deep scan"
  step 'Measuring your home folder (can take a few minutes)'
  info 'Largest folders in your home:'
  du -sk "$HOME"/* "$HOME"/.[!.]* 2>/dev/null | sort -rn | head -12 | while read -r s p; do sub "$(hum "$s")  $(tildify "$p")"; done
  info 'Largest folders in Application Support (mostly app data, not caches):'
  du -sk "$HOME/Library/Application Support"/* 2>/dev/null | sort -rn | head -10 | while read -r s p; do sub "$(hum "$s")  ${p##*/}"; done
  if [ -d "$HOME/Downloads" ]; then
    DL=$(find "$HOME/Downloads" -mindepth 1 -maxdepth 1 -mtime +90 2>/dev/null)
    if [ -n "$DL" ]; then
      s=$(printf '%s\n' "$DL" | tr '\n' '\0' | xargs -0 du -sk 2>/dev/null | awk '{s+=$1} END{print s+0}')
      info "Downloads older than 90 days: %s items, %s — review and delete what you don't need" "$(cnt "$DL")" "$(hum "$s")"
    fi
    BIG=$(find "$HOME/Downloads" -type f -size +1G 2>/dev/null | head -10)
    [ -n "$BIG" ] && { info 'Files over 1 GB in Downloads:'; printf '%s\n' "$BIG" | while IFS= read -r f; do sub "$(hum "$(kb "$f")")  $(tildify "$f")"; done; }
  fi
  step 'Scanning projects for build artifacts'
  ART=""
  while IFS= read -r root; do
    [ -z "$root" ] && continue
    # target and build are common names: only next to the build file that makes them (Cargo, Maven, Gradle)
    ART="$ART$(find "$root" -maxdepth 6 -type d \( -name node_modules -o -name Pods -o -name .build -o -name .dart_tool -o -name DerivedData -o -name .next -o -name .venv \
      -o \( -name target -exec test -e {}/../Cargo.toml -o -e {}/../pom.xml \; \) \
      -o \( -name build -exec test -e {}/../build.gradle -o -e {}/../build.gradle.kts \; \) \) -prune -print 2>/dev/null)"$'\n'
  done <<EOF
$(project_roots)
EOF
  if [ -n "$(printf '%s' "$ART" | grep .)" ]; then
    TOP=$(printf '%s' "$ART" | grep . | while IFS= read -r a; do echo "$(kb "$a") $a"; done | sort -rn)
    TS=$(printf '%s\n' "$TOP" | awk '{s+=$1} END{print s+0}')
    info 'Project build artifacts (node_modules, Pods, .build, .dart_tool, .next, .venv, Rust and Maven target, Gradle build): %s total; largest:' "$(hum "$TS")"
    printf '%s\n' "$TOP" | head -8 | while read -r s p; do sub "$(hum "$s")  $(tildify "$p")"; done
    task clean.stale_node_modules || info "Tip: enable clean.stale_node_modules in the config to remove node_modules from projects you haven't touched in %s days" "$STALE_DAYS"
  elif [ -z "$(project_roots)" ]; then
    info 'No project folders found. Set project_dirs in %s' "$(tildify "$CONF")"
  else
    info 'No build artifacts in: %s' "$(project_roots | while IFS= read -r d; do tildify "$d"; done | paste -sd ',' - | sed 's/,/, /g')"
  fi
fi


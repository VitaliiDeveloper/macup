# ================================================================ SIZES (never deleted)
if task check.sizes; then
  section "Not touched by macup"
  s=$(kb "$DEV/Xcode/Archives")
  if [ "$s" -gt 5242880 ]; then warn 'Xcode Archives: %s — delete old builds in Xcode → Organizer (keep ones you need to symbolicate crashes)' "$(hum "$s")"
  elif [ "$s" -gt 0 ]; then info 'Xcode Archives: %s' "$(hum "$s")"; fi
  s=$(kb "$DEV/CoreSimulator/Devices"); [ "$s" -gt 0 ] && info 'Simulator devices: %s (Xcode → Window → Devices and Simulators)' "$(hum "$s")"
  s=$(kb "$HOME/.pub-cache");          [ "$s" -gt 0 ] && info 'Flutter pub-cache: %s (full reset: dart pub cache clean)' "$(hum "$s")"
  s=$(kbl "$HOME/.codex/sessions"$'\n'"$HOME/.codex/archived_sessions"$'\n'"$(ls -d "$HOME/.codex/"*.sqlite 2>/dev/null)")
  [ "$s" -ge 102400 ] && info 'Codex chat history: %s (not a cache; delete old chats in Codex itself)' "$(hum "$s")"
  s=$(kbl "$HOME/.cache/huggingface"$'\n'"$HOME/.ollama/models"$'\n'"$HOME/.lmstudio/models")
  [ "$s" -ge 102400 ] && info 'AI models (Hugging Face, Ollama, LM Studio): %s' "$(hum "$s")"
  s=$(kbl "$HOME/Library/Android/sdk"$'\n'"$HOME/.android/avd")
  [ "$s" -ge 102400 ] && info 'Android SDK and emulators: %s (Android Studio → SDK Manager, Device Manager)' "$(hum "$s")"
  s=$(kb "$HOME/Library/Caches");      [ "$s" -gt 0 ] && info 'App caches (~/Library/Caches): %s — macOS trims these itself when space is low' "$(hum "$s")"
  if ! task clean.trash; then
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
  AG=""; ORPH=""
  for f in "$HOME"/Library/LaunchAgents/*.plist /Library/LaunchAgents/*.plist /Library/LaunchDaemons/*.plist; do
    [ -f "$f" ] || continue
    b=$(basename "$f" .plist); case "$b" in com.apple.*) continue ;; esac
    AG="$AG$b"$'\n'
    prog=$(plutil -extract Program raw -o - "$f" 2>/dev/null || plutil -extract ProgramArguments.0 raw -o - "$f" 2>/dev/null)
    case "$prog" in /*) [ -e "$prog" ] || ORPH="$ORPH$(tildify "$f") → $(tildify "$prog")"$'\n' ;; esac
  done
  info 'Third-party background services: %s (full list in the report)' "$(cnt "$AG")"
  printf '%s' "$AG" | while IFS= read -r l; do [ -n "$l" ] && mdonly "$l"; done
  if [ -n "$ORPH" ]; then
    warn 'Orphaned launch items: %s point to programs that no longer exist (likely leftovers of deleted apps)' "$(cnt "$ORPH")"
    lines "$ORPH"
  fi
  info 'Login items: System Settings → General → Login Items & Extensions'
fi

# ================================================================ DEEP
if [ "$DEEP" = 1 ]; then
  section "Deep scan"
  step 'Measuring your home folder (can take a few minutes)'
  info 'Largest folders in your home:'
  du -sk "$HOME"/* "$HOME"/.[!.]* 2>/dev/null | sort -rn | head -12 | while read -r s p; do sub "$(hum "$s")  $(tildify "$p")"; done
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
    ART="$ART$(find "$root" -maxdepth 6 -type d \( -name node_modules -o -name Pods -o -name .build -o -name .dart_tool -o -name DerivedData \) -prune -print 2>/dev/null)"$'\n'
  done <<EOF
$(project_roots)
EOF
  if [ -n "$(printf '%s' "$ART" | grep .)" ]; then
    TOP=$(printf '%s' "$ART" | grep . | while IFS= read -r a; do echo "$(kb "$a") $a"; done | sort -rn)
    TS=$(printf '%s\n' "$TOP" | awk '{s+=$1} END{print s+0}')
    info 'Project build artifacts (node_modules, Pods, .build, .dart_tool): %s total; largest:' "$(hum "$TS")"
    printf '%s\n' "$TOP" | head -8 | while read -r s p; do sub "$(hum "$s")  $(tildify "$p")"; done
    task clean.stale_node_modules || info "Tip: enable clean.stale_node_modules in the config to remove node_modules from projects you haven't touched in %s days" "$STALE_DAYS"
  elif [ -z "$(project_roots)" ]; then
    info 'No project folders found. Set project_dirs in %s' "$(tildify "$CONF")"
  else
    info 'No build artifacts in: %s' "$(project_roots | while IFS= read -r d; do tildify "$d"; done | paste -sd ',' - | sed 's/,/, /g')"
  fi
fi


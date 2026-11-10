# ================================================================ UPDATES
if WANT_UPD; then
if UPD; then section "Updates"; else section "Update status (check only, nothing installed)"; fi

if task update.claude && have claude; then
  v1=$(claude --version 2>/dev/null | awk '{print $1}')
  if UPD; then step 'Claude Code'; run claude update; fi
  v2=$(claude --version 2>/dev/null | awk '{print $1}')
  upd "Claude Code" "$v1" "$v2"
  if ! UPD && have npm; then
    latest=$(npm view @anthropic-ai/claude-code version 2>/dev/null)
    ver_gt "$latest" "$v2" && info "%s: %s is on npm (fine if you're on the stable channel)" "Claude Code" "$latest"
  fi
  PJSON="$HOME/.claude/plugins/installed_plugins.json"
  plugins(){ [ -f "$PJSON" ] && have python3 && python3 - "$PJSON" <<'PY' 2>/dev/null
import json, sys
d = json.load(open(sys.argv[1])); pl = d.get("plugins", d)
for k, v in sorted(pl.items()):
    es = v if isinstance(v, list) else [v]
    e = next((x for x in es if isinstance(x, dict) and x.get("scope", "user") == "user"), None)
    if e is None: continue   # project/local plugins belong to their project
    print(k, e.get("version") or (e.get("gitCommitSha") or "")[:7] or "?")
PY
  }
  P1=$(plugins)
  if UPD; then
    step 'Plugin marketplaces'
    if run claude plugin marketplace update; then ok 'Plugin marketplaces refreshed'; else warn 'Plugin marketplaces: refresh failed (see log)'; fi
    # no -y: a plugin whose marketplace asks to run a command is left for you to confirm (see log)
    printf '%s\n' "$P1" | while read -r name ver; do [ -n "$name" ] && { step 'Plugin %s' "$name"; (cd "$HOME" && run claude plugin update --scope user "$name"); }; done
  fi
  P2=$(plugins)
  if [ -n "$P2" ]; then
    while read -r name ver; do
      [ -z "$name" ] && continue
      old=$(printf '%s\n' "$P1" | awk -v n="$name" '$1==n{print $2}')
      if [ -n "$old" ] && [ "$old" != "$ver" ]; then ok 'Plugin %s: %s → %s' "$name" "$old" "$ver"; done_upd 'plugin %s %s → %s' "$name" "$old" "$ver"; else mdonly "$name $ver"; fi
    done <<EOF
$P2
EOF
    ok 'Claude Code plugins: %s installed' "$(cnt "$P2")"
  fi
fi

# npm and npx are node scripts: with node unlinked (keg-only node@24) they stay on PATH but cannot run
node_ok(){
  have node && return 0
  local fix; fix=$(link_fix node)
  if [ -n "$fix" ]; then warn '%s: skipped, node is not on PATH — run: %s' "$1" "$fix"; else warn '%s: skipped, node is not on PATH' "$1"; fi
  return 1
}

if task update.npm && have npm && have python3 && node_ok "$(_ 'npm globals')"; then
  step 'npm globals'
  # skips npm-link'ed packages and anything whose versions don't look like registry versions
  NO=$(npm outdated -g --json 2>/dev/null | python3 -c '
import json, os, sys, re
try: d = json.load(sys.stdin)
except Exception: d = {}
root = sys.argv[1]
ver = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+")
for k, v in d.items():
    c, l = str(v.get("current", "")), str(v.get("latest", ""))
    if os.path.islink(os.path.join(root, k)) or not ver.match(c) or not ver.match(l) or c == l: continue
    print(k, c, l)' "$(npm root -g 2>/dev/null)" 2>/dev/null)
  if [ -z "$NO" ]; then ok 'npm globals: up to date'
  else
    UPD || warn 'npm globals: %s outdated' "$(cnt "$NO")"
    while read -r p c l; do
      [ -z "$p" ] && continue
      if UPD; then
        step 'npm %s' "$p"
        if run npm install -g "$p@$l"; then ok '%s: %s → %s' "$p" "$c" "$l"; UPDATED+=("$p $c → $l"); else fail '%s: update failed (see log)' "$p"; fi
      else sub "$p: $c → $l"; fi
    done <<EOF
$NO
EOF
  fi
fi

LOCK="$HOME/.agents/.skill-lock.json"; LATER_SKILLS=""
if task update.skills && [ -f "$LOCK" ] && have npx && have python3 && node_ok "$(_ 'Agent skills')"; then
  skills(){ python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
for k, v in sorted(d.get("skills", {}).items()): print(k, v.get("skillFolderHash", "")[:7])' "$LOCK" 2>/dev/null; }
  S1=$(skills)
  if UPD; then
    step 'Agent skills'
    # -g: the global skills in ~/.agents, wherever macup is started from
    if (cd "$HOME" && run env CI=1 npx -y skills update -g); then
      S2=$(skills); n=0
      while read -r name h; do
        [ -z "$name" ] && continue
        old=$(printf '%s\n' "$S1" | awk -v n="$name" '$1==n{print $2}')
        [ "$old" != "$h" ] && { n=$((n+1)); done_upd 'skill %s' "$name"; }
      done <<EOF
$S2
EOF
      ok 'Agent skills: %s installed, %s updated' "$(cnt "$S2")" "$n"
    else fail 'Agent skills: update failed (see log)'; fi
  else
    # the skills CLI has no read-only check (`skills check` now updates), so a check only counts them
    LATER_SKILLS="$(_ 'Agent skills')"
  fi
fi

if task update.brew && have brew; then
  step 'brew update'; run brew update   # refreshes the package list only
  OF=$(brew outdated --formula --verbose 2>/dev/null); NF=$(cnt "$OF")
  OC=$(brew outdated --cask --verbose 2>/dev/null);    NC=$(cnt "$OC")
  if [ $((NF + NC)) -eq 0 ]; then ok 'Homebrew: up to date'
  else
    if UPD; then
      step 'brew upgrade (formulae: %s, casks: %s)' "$NF" "$NC"
      if run brew upgrade; then ok 'Homebrew: upgraded — formulae: %s, casks: %s' "$NF" "$NC"; else warn 'Homebrew: upgraded with errors (see log)'; fi
      done_upd 'Homebrew: formulae: %s, casks: %s' "$NF" "$NC"
    else warn 'Homebrew: outdated — formulae: %s, casks: %s' "$NF" "$NC"; fi
    lines "$(printf '%s\n%s\n' "$OF" "$OC")"
  fi
  # in a check the casks brew upgrades anyway are already listed above
  # not --greedy: a version :latest cask is always "outdated" and does not update itself
  GR=$(brew outdated --cask --greedy-auto-updates --quiet 2>/dev/null)
  UPD || GR=$(printf '%s\n' "$GR" | grep -vxF -f <(printf '%s\n' "$OC" | awk 'NF{print $1}'))
  if [ -n "$GR" ]; then
    GL=$(printf '%s\n' "$GR" | head -10 | paste -sd, - | sed 's/,/, /g'); GN=$(cnt "$GR")
    [ "$GN" -gt 10 ] && GL="$GL +$((GN - 10))"
    info 'Casks that update themselves: %s. Force with: brew upgrade --cask --greedy-auto-updates' "$GL"
  fi
fi

if task update.mas; then
  if have mas; then
    step 'App Store'
    # "497799835 Xcode (27.1 → 27.2)": the id for mas, the rest for people
    OM=$(mas outdated 2>/dev/null | sed -E 's/^ +//; s/ +/ /g; s/ -> / → /'); NM=$(cnt "$OM")
    if [ "$NM" -eq 0 ]; then ok 'App Store: up to date'
    elif UPD; then
      info 'App Store: updates: %s' "$NM"; lines "$(printf '%s\n' "$OM" | cut -d' ' -f2-)"
      i=0
      while read -r id app; do
        [ -z "$id" ] && continue; i=$((i + 1))
        # mas runs itself through sudo, which would ask a bare "Password:" in the middle of the step line
        if ! sudo -n true 2>/dev/null && ! { { : </dev/tty; } 2>/dev/null && printf '%s' "$CL" && sudo -v -p "  $(_ 'Mac password to install App Store updates:') "; }; then
          warn 'App Store: updates not installed: %s — they need your Mac password' "$((NM - i + 1))"; break
        fi
        # sudo forgets the password after 5 minutes and one install (Xcode) takes longer, so it would ask again for the next app
        [ -z "${SUDO_KEEP:-}" ] && { while kill -0 $$ 2>/dev/null; do sleep 50; sudo -n -v || break; done </dev/null >/dev/null 2>&1 & SUDO_KEEP=$!; }
        if tick "App Store $i/$NM: $app" mas upgrade "$id"; then ok '%s: %s' 'App Store' "$app"; done_upd '%s: %s' 'App Store' "$app"
        else warn 'App Store: updates not installed: %s — open the App Store' "$app"; fi
      done <<EOF
$OM
EOF
      stop_sudo_keep
    else warn 'App Store: updates: %s' "$NM"; lines "$(printf '%s\n' "$OM" | cut -d' ' -f2-)"; fi
  else info "App Store apps aren't checked: brew install mas"; fi
fi

# apps installed from a download update themselves; macup only says which are behind the Homebrew catalog
if task update.apps && have curl && have python3; then
  step 'Apps outside Homebrew and the App Store'
  CJ="$CACHE_DIR/cask.json"; mkdir -p "${CJ%/*}"
  # -z: downloads the catalog (about 20 MB) only when it changed; a failed download keeps the last copy
  if [ -s "$CJ" ]; then ZF=(-z "$CJ"); else ZF=(); fi
  curl -fsSL --compressed --max-time 60 "${ZF[@]}" -o "$CJ.new" https://formulae.brew.sh/api/cask.json 2>/dev/null && [ -s "$CJ.new" ] && mv "$CJ.new" "$CJ"; rm -f "$CJ.new"
  if ! OA=$([ -s "$CJ" ] && python3 - "$CJ" "$HOME/Applications" <<'PY' 2>/dev/null
import json, os, plistlib, re, subprocess, sys
def key(v): return [int(x) for x in re.findall(r"\d+", v)]
try: brewed = set(subprocess.run(["brew", "list", "--cask"], capture_output=True, text=True).stdout.split())
except OSError: brewed = set()
casks = {}
for c in json.load(open(sys.argv[1])):
    if "@" in c["token"]: continue   # beta and other channels of the same app
    for art in c.get("artifacts", []):
        for a in (art.get("app") or [])[:1]:
            if isinstance(a, str): casks.setdefault(a, []).append((c["token"], str(c.get("version", "")).split(",")[0]))
# brew upgrade covers casks brew installed; two casks with one app name and different versions are different apps (Telegram)
latest = {a: v[0][1] for a, v in casks.items() if not brewed & {t for t, _ in v} and len({n for _, n in v}) == 1}
checked, behind = 0, []
for d in ("/Applications", sys.argv[2]):
    if not os.path.isdir(d): continue
    for a in sorted(os.listdir(d)):
        p = os.path.join(d, a)
        if a not in latest or os.path.isdir(p + "/Contents/_MASReceipt"): continue
        try: i = plistlib.load(open(p + "/Contents/Info.plist", "rb"))
        except Exception: continue
        have = str(i.get("CFBundleShortVersionString") or i.get("CFBundleVersion") or "").split(" ")[0]
        new = latest[a]
        if not have or new == "latest": continue
        checked += 1
        if key(new) > key(have): behind.append("%s %s → %s" % (a[:-4], have, new))
print(checked); print("\n".join(behind))
PY
); then warn '%s: could not check for updates' "$(_ 'Apps outside Homebrew and the App Store')"
  else
    AN=$(printf '%s\n' "$OA" | head -1); OA=$(printf '%s\n' "$OA" | tail -n +2)
    if [ -n "$OA" ]; then warn 'Apps with a newer version: %s — open or restart them to update' "$(cnt "$OA")"; lines "$OA"
    elif [ "$AN" -gt 0 ]; then ok 'Apps outside Homebrew and the App Store: up to date (%s checked)' "$AN"; fi
  fi
fi

LATER="${LATER_SKILLS:-}"
simple_update(){ # task-id label cmd...
  local id=$1 label; label=$(_ "$2"); shift 2
  task "$id" || return 0
  if UPD; then step '%s' "$label"; if run "$@"; then ok '%s: updated' "$label"; else warn '%s: update failed (see log)' "$label"; fi
  else LATER="$LATER${LATER:+, }$label"; fi
}
have pipx   && simple_update update.pipx   'pipx tools'      pipx upgrade-all
have uv     && simple_update update.uv     'uv tools'        uv tool upgrade --all
have rustup && simple_update update.rustup 'Rust toolchains' rustup update
[ -f "${ZSH:-$HOME/.oh-my-zsh}/tools/upgrade.sh" ] && have zsh && simple_update update.omz 'Oh My Zsh' env ZSH="${ZSH:-$HOME/.oh-my-zsh}" zsh "${ZSH:-$HOME/.oh-my-zsh}/tools/upgrade.sh"
have gh && [ -n "$(gh extension list 2>/dev/null)" ] && simple_update update.gh_ext 'gh extensions' gh extension upgrade --all

if task update.grok && have grok; then
  GJ=$(grok update --check --json 2>/dev/null)
  gj(){ printf '%s' "$GJ" | sed -n "s/.*\"$1\":\"\([^\"]*\)\".*/\1/p"; }
  v1=$(gj currentVersion); latest=$(gj latestVersion)
  if [ -z "$latest" ]; then warn '%s: could not check for updates' 'Grok CLI'
  elif [ "$(gj installer)" = internal ]; then   # a brew or npm install is updated by that step
    if UPD; then
      if ver_gt "$latest" "$v1"; then step '%s' 'Grok CLI'; run grok update || warn '%s: update failed (see log)' 'Grok CLI'; fi
      upd 'Grok CLI' "$v1" "$(grok --version 2>/dev/null | awk '{print $2}')"
    elif ver_gt "$latest" "$v1"; then warn '%s: %s → %s available' 'Grok CLI' "$v1" "$latest"
    else ok '%s %s' 'Grok CLI' "$v1"; fi
  fi
fi

# agy updates itself in ~/.local/bin and has no read-only check
if task update.agy && have agy && [[ "$(command -v agy)" == "$HOME"/* ]]; then
  if UPD; then
    v1=$(agy --version 2>/dev/null); step '%s' 'Antigravity CLI'
    run agy update || warn '%s: update failed (see log)' 'Antigravity CLI'
    upd 'Antigravity CLI' "$v1" "$(agy --version 2>/dev/null)"
  else LATER="$LATER${LATER:+, }Antigravity CLI"; fi
fi
[ -n "$LATER" ] && info 'Not checked in this mode, updated by macup update: %s' "$LATER"

if task check.macos_updates; then
  step 'Looking for macOS updates (up to a minute)'
  SL=$(softwareupdate -l 2>&1)
  SU=$(printf '%s\n' "$SL" | sed -n 's/^[[:space:]]*\* Label: //p')
  # a Label is an id ("Command Line Tools for Xcode 27.2-27.2"); some Titles carry no version ("Safari")
  ST=$(printf '%s\n' "$SL" | sed -n 's/^[[:space:]]*Title: //p' | awk -F', Version: ' '{v=$2; sub(/,.*/, "", v); print (v == "" || index($1, v)) ? $1 : $1 " " v}')
  if [ -z "$SU" ]; then ok 'macOS: up to date'; else warn 'macOS: updates available — System Settings → General → Software Update'; lines "${ST:-$SU}"; fi
fi
fi # WANT_UPD


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
  GR=$(brew outdated --cask --greedy --quiet 2>/dev/null)
  UPD || GR=$(printf '%s\n' "$GR" | grep -vxF -f <(printf '%s\n' "$OC" | awk 'NF{print $1}'))
  if [ -n "$GR" ]; then
    GL=$(printf '%s\n' "$GR" | head -10 | paste -sd, - | sed 's/,/, /g'); GN=$(cnt "$GR")
    [ "$GN" -gt 10 ] && GL="$GL +$((GN - 10))"
    info 'Casks that update themselves: %s. Force with: brew upgrade --cask --greedy' "$GL"
  fi
fi

if task update.mas; then
  if have mas; then
    step 'App Store'
    OM=$(mas outdated 2>/dev/null); NM=$(cnt "$OM")
    if [ "$NM" -eq 0 ]; then ok 'App Store: up to date'
    elif UPD; then
      if run mas upgrade; then ok 'App Store: apps updated: %s' "$NM"; done_upd 'App Store: apps: %s' "$NM"; else warn 'App Store: updates not installed: %s — open the App Store' "$NM"; fi
    else warn 'App Store: updates: %s' "$NM"; lines "$OM"; fi
  else info "App Store apps aren't checked: brew install mas"; fi
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


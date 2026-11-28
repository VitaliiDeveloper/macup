# shellcheck shell=bash
# shellcheck disable=SC2154  # SC2154: work, quick_skip, build_path and the helpers come from tests/run.sh
# Sourced by tests/run.sh: commands that cannot start, Time Machine, uninstall, sizes, grok, apps, stale node_modules, big caches, DerivedData.
# --- commands that cannot start: missing interpreter, pipx venv whose Python is gone, broken link; working ones stay quiet
home="$work/cmds"; local_bin="$home/.local/bin"; venv_bin="$home/.local/pipx/venvs/tool/bin"; mkdir -p "$local_bin" "$home/.npm-global/bin" "$venv_bin" "$home/.config/macup"; printf 'language = en\n' >"$home/.config/macup/config"
printf '#!/usr/bin/env macup_no_such_interp\n' >"$local_bin/nodecli"; printf '#!/usr/bin/env -S macup_no_such_interp --flag\n' >"$home/.npm-global/bin/flagcli"
printf '#!/bin/sh\necho ok\n' >"$local_bin/okscript"; cp /usr/bin/true "$local_bin/okbinary"
ln -s "$home/gone/python3.12" "$venv_bin/python"; printf '#!%s\n' "$venv_bin/python" >"$venv_bin/tool"; ln -s "$venv_bin/tool" "$local_bin/pipxtool"
for index in 01 02 03 04 05 06 07 08 09 10 11; do ln -s "$home/gone/thing" "$local_bin/gone$index"; done; ln -s "$home/gone/thing" "$local_bin/gonelink"; ln -s "$home/gone/Old.app/Contents/MacOS/old" "$local_bin/oldapp"
mkdir -p "$home/Cellar/x/1/bin"; printf '#!/usr/bin/env macup_no_such_interp\n' >"$home/Cellar/x/1/bin/brewcli"; ln -s "$home/Cellar/x/1/bin/brewcli" "$local_bin/brewcli"; ln -s "$home/Cellar/y/1/bin/gone" "$local_bin/brewgone"   # Homebrew's own files are brew doctor's job
# interpreters a formula has but brew has not linked: the newest versioned keg, or the unversioned formula
printf '#!/usr/bin/env macup_keg_interp\n' >"$local_bin/kegcli"; printf '#!/usr/bin/env macup_plain_interp\n' >"$local_bin/plaincli"
for keg in macup_keg_interp@9/bin/macup_keg_interp macup_keg_interp@10/bin/macup_keg_interp macup_plain_interp/bin/macup_plain_interp sh/bin/sh; do mkdir -p "$home/brew/opt/${keg%/*}"; cp /usr/bin/true "$home/brew/opt/$keg"; done
# a dead absolute interpreter whose name is on PATH (a venv's python3): brew link would not fix it
printf '#!%s\n' "$home/gone/bin/sh" >"$local_bin/deadsh"
chmod +x "$local_bin"/* "$venv_bin/tool" "$home/.npm-global/bin/flagcli" "$home/Cellar/x/1/bin/brewcli"
env HOME="$home" HOMEBREW_PREFIX="$home/brew" macup_run check --only check.commands --no-color </dev/null >"$work/cmds.out" 2>&1
grep -q 'cannot start, macup_no_such_interp is missing: flagcli, nodecli$' "$work/cmds.out" \
  && grep -q 'cannot start, python is missing: .*pipxtool.* — run: pipx reinstall-all' "$work/cmds.out" \
  && grep -qF 'macup_keg_interp is missing: kegcli — run: brew link --force --overwrite macup_keg_interp@10' "$work/cmds.out" \
  && grep -qF 'macup_plain_interp is missing: plaincli — run: brew link --overwrite macup_plain_interp' "$work/cmds.out" \
  && grep -q 'cannot start, sh is missing: deadsh$' "$work/cmds.out" \
  && grep -qF 'Dead links in ~/.local/bin, leftovers of removed Old.app, ~/gone: gone01, gone02,' "$work/cmds.out" \
  && grep -qF 'gone10 +3 — safe to remove, run in Terminal: find ~/.local/bin -maxdepth 1 -type l ! -exec test -e {} \; -print -delete' "$work/cmds.out" \
  && ! grep -E 'cannot start|Dead links' "$work/cmds.out" | grep -qE 'okscript|okbinary|brewcli|brewgone' \
  && pass "commands that cannot start are listed with a fix; working ones are not" || { fail "commands that cannot start"; cat "$work/cmds.out"; }
# a uv tool whose Python was removed: uv puts it back, a brew link does not
uv_bin="$home/.local/share/uv/tools/sometool/bin"; mkdir -p "$uv_bin"; ln -s "$home/gone/python3.11" "$uv_bin/python"; printf '#!%s\n' "$uv_bin/python" >"$uv_bin/sometool"; chmod +x "$uv_bin/sometool"; ln -s "$uv_bin/sometool" "$local_bin/sometool"
env HOME="$home" HOMEBREW_PREFIX="$home/brew" macup_run check --only check.commands --no-color </dev/null >"$work/cmds2.out" 2>&1
grep -qF 'cannot start, python is missing: sometool — run: uv tool install --reinstall sometool' "$work/cmds2.out" && grep -q 'python is missing: pipxtool — run: pipx reinstall-all' "$work/cmds2.out" \
  && pass "a uv tool that cannot start: the fix is uv tool install --reinstall" || { fail "uv tool fix"; grep 'cannot start' "$work/cmds2.out"; }
rm -f "$local_bin/sometool"
# only the fake home's line: the real /opt/homebrew/bin and /usr/local/bin are scanned too, and their fix may need sudo
fix=$(sed -n 's|.*Dead links in ~/\.local/bin, .* run in Terminal: \(find ~/\.local/bin .*\)$|\1|p' "$work/cmds.out" | head -1)
[ -n "$fix" ] && (HOME="$home"; eval "$fix") >/dev/null 2>&1 </dev/null
[ -n "$fix" ] && [ ! -L "$local_bin/gone01" ] && [ ! -L "$local_bin/gonelink" ] && [ ! -L "$local_bin/oldapp" ] && [ -e "$local_bin/okscript" ] && [ -e "$local_bin/okbinary" ] && [ -L "$local_bin/pipxtool" ] && [ -L "$local_bin/brewcli" ] \
  && pass "the dead-link fix removes only dead links" || { fail "dead-link fix: $fix"; ls -la "$local_bin"; }

# --- Time Machine can be skipped on its own, and --only check.security still includes it
home="$work/tm"; mkdir -p "$home/.config/macup"; printf 'language = en\n' >"$home/.config/macup/config"
tm(){ env HOME="$home" macup_run check --no-color "$@" </dev/null 2>&1; }
tm --only check.security | grep -q 'Time Machine:' && ! tm --only check.security --skip check.time_machine | grep -q 'Time Machine:' \
  && tm --only check.security --skip check.time_machine | grep -q 'FileVault' \
  && pass "check.time_machine hides only Time Machine" || fail "check.time_machine"

# --- uninstall removes every file macup made, keeps a PATH line other programs need, and leaves a Homebrew install to brew
# it also looks for older copies in /usr/local/bin and /opt/homebrew/bin: never run it where a real one is there
if [ -e /usr/local/bin/macup ] || [ -e /opt/homebrew/bin/macup ]; then echo "SKIP uninstall: a real macup is in /usr/local/bin or /opt/homebrew/bin"
else
  home="$work/un"; tmp_dir="$home/tmp"; mkdir -p "$tmp_dir" "$home/.local/bin" "$home/.npm-global/bin" "$home/.config/macup" "$home/Library/Logs/macup" "$home/Library/Application Support/macup"
  cp "$build_path" "$home/.local/bin/macup"; cp "$build_path" "$home/.npm-global/bin/macup"; printf 'language = en\n' >"$home/.config/macup/config"
  echo r >"$home/Library/Logs/macup/macup_x.md"; echo h >"$home/Library/Application Support/macup/history.csv"
  printf 'alias ll=ls\n\n# macup\nexport PATH="$HOME/.local/bin:$PATH"\nexport EDITOR=vim\n' >"$home/.zshrc"
  touch "$tmp_dir/macup.Ab12Cd" "$tmp_dir/macup.Ab12Cd.rt" "$tmp_dir/macup-lang.Zz99Yy" "$tmp_dir/other.txt"
  SP="$home/Library/LaunchAgents/com.vitaliideveloper.macup.plist"; mkdir -p "${SP%/*}"; echo '<plist/>' >"$SP"
  env HOME="$home" TMPDIR="$tmp_dir/" MACUP_AT="$home/.local/bin/macup" macup_run uninstall --no-color </dev/null >"$work/un0.out" 2>&1
  [ -e "$home/.local/bin/macup" ] && [ -d "$home/.config/macup" ] && grep -q 'Nothing removed' "$work/un0.out" && pass "uninstall without a terminal or --yes removes nothing" || { fail "uninstall: no answer"; cat "$work/un0.out"; }
  env HOME="$home" TMPDIR="$tmp_dir/" MACUP_AT="$home/.local/bin/macup" macup_run uninstall --yes --no-color </dev/null >"$work/un.out" 2>&1
  [ ! -e "$home/.local/bin/macup" ] && [ ! -e "$home/.npm-global/bin/macup" ] && [ ! -e "$home/.config/macup" ] && [ ! -e "$home/Library/Logs/macup" ] && [ ! -e "$SP" ] \
    && [ ! -e "$home/Library/Application Support/macup" ] && [ "$(cat "$home/.zshrc")" = "$(printf 'alias ll=ls\nexport EDITOR=vim')" ] \
    && [ "$(ls "$tmp_dir")" = other.txt ] && pass "uninstall --yes removes macup, older copies, settings, history, reports, the schedule, the PATH line, temp files" \
    || { fail "uninstall --yes"; cat "$work/un.out"; cat "$home/.zshrc"; ls -la "$tmp_dir"; }
  # a bootstrap 2.9 installed, and the schedule in either form: 2.9's runs it through /bin/bash, 3.0's runs the binary
  for first in "<string>/bin/bash</string>" ""; do
    home="$work/unb"; rm -rf "$home"; mkdir -p "$home/.local/bin" "$home/Library/LaunchAgents"; cp tools/bootstrap.sh "$home/.local/bin/macup"
    SP="$home/Library/LaunchAgents/com.vitaliideveloper.macup.plist"
    printf '<plist version="1.0">\n<dict>\n  <key>ProgramArguments</key>\n  <array>%s<string>%s</string><string>check</string></array>\n</dict>\n</plist>\n' "$first" "$home/.local/bin/macup" >"$SP"
    env HOME="$home" TMPDIR="$home/" macup_run uninstall --yes --no-color </dev/null >"$work/unb.out" 2>&1
    [ ! -e "$home/.local/bin/macup" ] && [ ! -e "$SP" ] && grep -q "^bootout gui/.*/com.vitaliideveloper.macup" "$home/launchctl.log" \
      && pass "uninstall removes a bootstrap and the schedule${first:+ of 2.9}" || { fail "uninstall: bootstrap, schedule ${first:-3.0}"; cat "$work/unb.out"; }
  done
  home="$work/un2"; mkdir -p "$home/.local/bin" "$home/brew/Cellar/macup/9.9.9/bin" "$home/brew/bin"; cp "$build_path" "$home/.local/bin/macup"; cp /usr/bin/true "$home/.local/bin/claude"
  printf '\n# macup\nexport PATH="$HOME/.local/bin:$PATH"\n' >"$home/.zshrc"
  env HOME="$home" TMPDIR="$home/" MACUP_AT="$home/.local/bin/macup" macup_run uninstall --yes --no-color </dev/null >"$work/un2.out" 2>&1
  [ ! -e "$home/.local/bin/macup" ] && [ -e "$home/.local/bin/claude" ] && grep -q '^# macup' "$home/.zshrc" && grep -q 'Kept: the PATH line in ~/.zshrc, because ~/.local/bin also has claude' "$work/un2.out" \
    && pass "uninstall keeps the PATH line when other programs live in that folder" || { fail "uninstall: PATH line kept"; cat "$work/un2.out"; }
  cp "$build_path" "$home/brew/Cellar/macup/9.9.9/bin/macup"; ln -s ../Cellar/macup/9.9.9/bin/macup "$home/brew/bin/macup"
  printf '#!/bin/bash\necho "brew $*" >>"%s/brew.log"\n' "$home" >"$home/brew/bin/brew"; chmod +x "$home/brew/bin/brew"
  env HOME="$home" MACUP_AT="$home/brew/bin/macup" macup_run self-update --no-color </dev/null >"$work/un3.out" 2>&1
  env HOME="$home" TMPDIR="$home/" MACUP_AT="$home/brew/bin/macup" macup_run uninstall --yes --no-color </dev/null >>"$work/un3.out" 2>&1
  grep -q 'installed with Homebrew. Update it with: brew upgrade macup' "$work/un3.out" && grep -qx 'brew uninstall macup' "$home/brew.log" \
    && pass "a Homebrew install: self-update points to brew upgrade, uninstall runs brew uninstall" || { fail "uninstall: Homebrew"; cat "$work/un3.out" "$home/brew.log"; }
fi

# --- sizes of what macup never deletes are shown by update too, not only by check and clean
home="$work/sizes"; mkdir -p "$home/Library/Developer/Xcode/Archives/a.xcarchive" "$home/.config/macup"; printf 'language = en\n' >"$home/.config/macup/config"
echo build >"$home/Library/Developer/Xcode/Archives/a.xcarchive/Info.plist"
env HOME="$home" macup_run update --only check.sizes --no-color </dev/null >"$work/sizes.out" 2>&1
grep -q 'Xcode Archives: ' "$work/sizes.out" && pass "update shows Xcode Archives size" || { fail "update: sizes"; cat "$work/sizes.out"; }

# --- grok: a check reads `grok update --check --json`; an install that brew or npm owns is left alone
mkdir -p "$work/gbin"; printf '#!/bin/bash\nprintf "%%s" "$FAKE_GROK"\n' >"$work/gbin/grok"; chmod +x "$work/gbin/grok"
grok_check(){ env MACUP_PATH=keep HOME="$home" PATH="$work/gbin:$PATH" FAKE_GROK="$1" macup_run check --only update.grok --no-color </dev/null 2>&1; }
grok_check '{"currentVersion":"1.0.70","latestVersion":"1.0.77","installer":"internal","error":null}' | grep -q 'Grok CLI: 1.0.70 → 1.0.77 available' && pass "grok: newer version shown" || fail "grok: newer version"
grok_check '{"currentVersion":"1.0.70","latestVersion":"1.0.77","installer":"brew","error":null}' | grep -q 'Grok' && fail "grok: brew install is not ours" || pass "grok: brew install left to brew"
grok_check '{"currentVersion":"1.0.70","latestVersion":null,"installer":"internal","error":"offline"}' | grep -q 'Grok CLI: could not check' && pass "grok: failed check said" || fail "grok: failed check"

# --- apps outside Homebrew: compared with the cached cask catalog (the download fails here, so the cache is used)
printf '#!/bin/bash\nexit 1\n' >"$work/gbin/curl"; chmod +x "$work/gbin/curl"; fakes "$work/gbin" brew   # brew list --cask: never the real one
home="$work/apps"; mkdir -p "$home/.config/macup" "$home/Library/Caches/macup"; printf 'language = en\n' >"$home/.config/macup/config"
apps_check(){ env MACUP_PATH=keep HOME="$home" PATH="$work/gbin:$PATH" macup_run check --only update.apps --no-color </dev/null 2>&1; }
apps_check | grep -q 'Apps outside Homebrew and the App Store: could not check' && pass "apps: no catalog is said" || fail "apps: no catalog"
for app in MacupOld:1.0 MacupNew:2.0 MacupMas:1.0 MacupTwin:1.0; do
  mkdir -p "$home/Applications/${app%:*}.app/Contents"
  printf '<?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleShortVersionString</key><string>%s</string></dict></plist>' "${app#*:}" >"$home/Applications/${app%:*}.app/Contents/Info.plist"
done
mkdir -p "$home/Applications/MacupMas.app/Contents/_MASReceipt"
cask(){ printf '{"token":"%s","version":"%s","artifacts":[{"app":["%s.app"]}]}' "$@"; }
printf '[%s,%s,%s,%s,%s,%s]' "$(cask macup-old 2.0,abc MacupOld)" "$(cask macup-old@beta 3.0 MacupOld)" "$(cask macup-new 2.0 MacupNew)" \
  "$(cask macup-mas 2.0 MacupMas)" "$(cask macup-twin 2.0 MacupTwin)" "$(cask macup-twin-desktop 7.0 MacupTwin)" >"$home/Library/Caches/macup/cask.json"
out=$(apps_check)
echo "$out" | grep -q 'Apps with a newer version: 1 (MacupOld) ' && echo "$out" | grep -q 'MacupOld 1.0 → 2.0$' && ! echo "$out" | grep -qE 'MacupNew|MacupMas|MacupTwin' \
  && pass "apps: only the app behind its catalog version is listed" || { fail "apps: list"; echo "$out" | head; }

# --- stale node_modules (opt-in): the project untouched for 90 days loses it, the fresh one keeps it; it used to say "cleaned" and delete nothing
home="$work/nm"; got=$(tests/fixture.sh "$home"; printf 'enable = clean.stale_node_modules\n' >>"$home/.config/macup/config"; (cd "$home" && find . -type f | sort) >"$home.b"
  env HOME="$home" macup_run clean --level standard --only clean.stale_node_modules --no-color </dev/null >"$home.out" 2>&1; (cd "$home" && find . -type f | sort) | comm -23 "$home.b" - | grep -v 'macup/')
[ "$got" = "./Code/old/node_modules/a/blob" ] && grep -q 'Stale node_modules.*freed' "$home.out" && pass "stale node_modules: only the stale project's folder is deleted" || { fail "stale node_modules"; echo "$got"; cat "$home.out"; }

# --- other big caches: a folder with virtualenvs inside (Poetry) is never offered
home="$work/ac"; tests/fixture.sh "$home"; dd if=/dev/zero of="$home/Library/Caches/pypoetry/virtualenvs/proj-Ab12-py3.12/lib/big" bs=1024 count=103424 2>/dev/null
env HOME="$home" macup_run check --only clean.app_caches --no-color </dev/null >"$work/ac.out" 2>&1
grep -q 'App cache: BigApp' "$work/ac.out" && ! grep -q pypoetry "$work/ac.out" && pass "big caches: Poetry's virtualenvs are not offered" || { fail "big caches"; grep 'App cache' "$work/ac.out"; }

# --- DerivedData is left alone while an xcodebuild started from a terminal runs
home="$work/xb"; tests/fixture.sh "$home"
FAKE_RUNNING='/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -scheme App build' env HOME="$home" macup_run clean --only clean.derived_data --no-color </dev/null >"$work/xb.out" 2>&1
[ -f "$home/Library/Developer/Xcode/DerivedData/App-abc/blob" ] && grep -q 'DerivedData.*skipped' "$work/xb.out" && pass "DerivedData skipped while xcodebuild runs" || { fail "DerivedData cleaned during xcodebuild"; cat "$work/xb.out"; }


# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # SC2034: CASES is read by tests/diff.sh; SC2154: work, build and the helpers come from it
# Sourced by tests/diff.sh, in name order: the updates unit.
# updates unit
# The updaters are answering fakes in the fake home (tests/fakes.sh): its .fake/bin, the shared fakes and /usr/bin and
# /bin are all PATH holds, so no real npm, mas or download is ever reached. calls.log in the home lists what was run.
# The bash build reads npm's, the plugins' and the catalog's JSON only with the Command Line Tools' python3: these cases
# need them (without, bash skips those sections, an intended difference).
upd_path="PATH=@H/.fake/bin:$work/bin:/usr/bin:/bin"
upd_simple=update.pipx,update.uv,update.rustup,update.omz,update.gh_ext,update.pnpm,update.bun,update.deno,update.cargo,update.mise,update.asdf,update.editor_ext,update.gcloud,update.dotnet,update.composer,update.gem
CASES+="
upd-claude-check|claude|$upd_path|check --only update.claude
upd-claude-check-json|claude|$upd_path|check --only update.claude --json
upd-claude-update|claude|$upd_path|update --only update.claude
upd-claude-fails|claudefail|$upd_path|update --only update.claude
upd-claude-timeout|claudeslow|$upd_path MACUP_STEP_SECS=2|update --only update.claude
upd-claude-current|claudecurrent|$upd_path|update --only update.claude
upd-npm-check|npm|$upd_path|check --only update.npm
upd-npm-update|npm|$upd_path|update --only update.npm
upd-npm-current|npmcurrent|$upd_path|update --only update.npm
upd-npm-bad-json|npmbad|$upd_path|check --only update.npm
upd-no-node|nonode|$upd_path HOMEBREW_PREFIX=@H/brew|check --only update.npm,update.skills
upd-skills-check|skills|$upd_path|check --only update.skills
upd-skills-update|skills|$upd_path|update --only update.skills
upd-skills-fails|skillsfail|$upd_path|update --only update.skills
upd-mas-check|mas|$upd_path|check --only update.mas
upd-mas-update|mas|$upd_path FAKE_SUDO_RC=0|update --only update.mas
upd-mas-asks|mas|$upd_path|update --only update.mas
upd-mas-sudo-refused|mas|$upd_path FAKE_SUDO_ASK_RC=1|update --only update.mas
upd-mas-timeout|masslow|$upd_path FAKE_SUDO_RC=0 MACUP_STEP_SECS=1|update --only update.mas
upd-mas-longer-limit|maslong|$upd_path FAKE_SUDO_RC=0 MACUP_STEP_SECS=1|update --only update.mas
upd-mas-current|mascurrent|$upd_path|update --only update.mas
upd-mas-missing||$upd_path|update --only update.mas
upd-apps-cached|apps|$upd_path|check --only update.apps
upd-apps-download|appsdownload|$upd_path|update --only update.apps
upd-apps-current|appscurrent|$upd_path|check --only update.apps
upd-apps-no-catalog|appsnone|$upd_path|check --only update.apps
upd-simple-check|simple|$upd_path|check --only $upd_simple --enable update.gem
upd-simple-update|simple|$upd_path|update --only $upd_simple --enable update.gem
upd-simple-fails|simplefail|$upd_path|update --only $upd_simple --enable update.gem
upd-simple-timeout|simpleslow|$upd_path MACUP_STEP_SECS=1|update --only update.rustup,update.mise
upd-simple-none|simplenone|$upd_path|update --only $upd_simple --enable update.gem
upd-grok-check|grok|$upd_path|check --only update.grok
upd-grok-update|grok|$upd_path|update --only update.grok
upd-grok-fails|grokfail|$upd_path|update --only update.grok
upd-grok-offline|grokoffline|$upd_path|check --only update.grok
upd-grok-brew|grokbrew|$upd_path|update --only update.grok
upd-grok-current|grokcurrent|$upd_path|check --only update.grok
upd-agy-check|agy|$upd_path|check --only update.agy
upd-agy-update|agy|$upd_path|update --only update.agy
upd-agy-fails|agyfail|$upd_path|update --only update.agy
upd-all-check|everything|$upd_path|check --only update.* --enable update.gem
upd-all-update|everything|$upd_path FAKE_SUDO_RC=0|update --only update.* --enable update.gem
upd-all-json|everything|$upd_path FAKE_SUDO_RC=0|update --only update.* --json
upd-macos-check|macos|$upd_path|check --only check.macos_updates
upd-macos-json|macos|$upd_path|check --only check.macos_updates --json
upd-macos-labels|macoslabels|$upd_path|update --only check.macos_updates
upd-macos-after-later|macosagy|$upd_path|check --only update.agy,check.macos_updates
upd-macos-clean|macos|$upd_path|clean --only check.macos_updates
upd-macos-none|macosnone|$upd_path|check --only check.macos_updates
upd-macos-timeout|macosslow|$upd_path|check --only check.macos_updates
upd-macos-offline|macosoffline|$upd_path|check --only check.macos_updates
upd-macos-offline-rc0|macosnonet|$upd_path|check --only check.macos_updates
upd-macos-missing||$upd_path|check --only check.macos_updates"

upd_tools(){ local home=$1; shift; answering "$home/.fake/bin" "$@"; }
fix_claude(){ upd_tools "$1" claude npm node; mkdir -p "$1/.claude/plugins"
  answer "$1" claude --version '2.0.1 (Claude Code)'; answer "$1" npm view 2.1.0
  printf '%s' '{"version":2,"plugins":{"zeta@market":[{"scope":"project","version":"1.0.0"},{"scope":"user","version":"1.2.0"}],"alpha@market":[{"scope":"user","gitCommitSha":"abcdef1234567"}],"Beta@m":{"version":"0.9"},"local@m":[{"scope":"local","version":"3"}]}}' >"$1/.claude/plugins/installed_plugins.json"
  printf '%s' '{"version":2,"plugins":{"zeta@market":[{"scope":"user","version":"1.3.0"}],"alpha@market":[{"scope":"user","gitCommitSha":"9876543210"}],"Beta@m":{"version":"0.9"}}}' >"$1/.fake/plugins-new.json"
  echo 'echo "2.0.5 (Claude Code)" >"$HOME/.fake/claude/--version"' >"$1/.fake/claude/update.then"
  echo 'cp "$HOME/.fake/plugins-new.json" "$HOME/.claude/plugins/installed_plugins.json"' >"$1/.fake/claude/plugin.then"; }
fix_claudefail(){ fix_claude "$1"; echo 1 >"$1/.fake/claude/update.rc"; rm "$1/.fake/claude/update.then" "$1/.fake/claude/plugin.then"; echo 1 >"$1/.fake/claude/plugin marketplace update.rc"; }
fix_claudeslow(){ fix_claude "$1"; echo 30 >"$1/.fake/claude/update.sleep"; }
fix_claudecurrent(){ upd_tools "$1" claude; answer "$1" claude --version '2.0.1 (Claude Code)'; }
fix_npm(){ upd_tools "$1" npm node; mkdir -p "$1/npmroot" "$1/elsewhere"; ln -s "$1/elsewhere" "$1/npmroot/linked"; answer "$1" npm root "$1/npmroot"
  answer "$1" npm outdated '{"zlib-x":{"current":"1.0.0","wanted":"1.1.0","latest":"1.1.0"},"aaa":{"current":"2.0.0","latest":"3.0.0-beta.1"},"linked":{"current":"1.0.0","latest":"2.0.0"},"git-dep":{"current":"git","latest":"1.0.0"},"same":{"current":"1.0.0","latest":"1.0.0"},"num":{"current":1.5,"latest":"2.0.0"}}'
  echo 1 >"$1/.fake/npm/install -g aaa@3.0.0-beta.1.rc"; }
fix_npmcurrent(){ upd_tools "$1" npm node; answer "$1" npm outdated '{}'; }
fix_npmbad(){ upd_tools "$1" npm node; answer "$1" npm outdated 'npm ERR! offline'; }
fix_nonode(){ upd_tools "$1" npm npx; mkdir -p "$1/.agents" "$1/brew/opt/node@22/bin" "$1/brew/opt/node@24/bin"; echo '{"skills":{}}' >"$1/.agents/.skill-lock.json"
  : >"$1/brew/opt/node@22/bin/node"; : >"$1/brew/opt/node@24/bin/node"; }
fix_skills(){ upd_tools "$1" npx node; mkdir -p "$1/.agents"
  printf '%s' '{"version":3,"skills":{"web":{"skillFolderHash":"aaaaaaa111"},"pdf":{"skillFolderHash":"bbbbbbb222"},"Zed":{}}}' >"$1/.agents/.skill-lock.json"
  printf '%s' '{"version":3,"skills":{"web":{"skillFolderHash":"ccccccc333"},"pdf":{"skillFolderHash":"bbbbbbb222"},"xlsx":{"skillFolderHash":"ddddddd444"},"Zed":{}}}' >"$1/.fake/skills-new.json"
  mkdir -p "$1/.fake/npx"; echo 'cp "$HOME/.fake/skills-new.json" "$HOME/.agents/.skill-lock.json"' >"$1/.fake/npx/-y.then"; }
fix_skillsfail(){ fix_skills "$1"; echo 1 >"$1/.fake/npx/-y.rc"; }
fix_mas(){ upd_tools "$1" mas; answer "$1" mas outdated "$(printf '        1  Foo          (1.0    -> 1.1)\n123456789  Bar Baz Pro  (2.10.3 -> 3.0)')"; echo 1 >"$1/.fake/mas/upgrade 123456789.rc"; }
fix_masslow(){ fix_mas "$1"; echo 30 >"$1/.fake/mas/upgrade 1.sleep"; }
fix_maslong(){ fix_mas "$1"; echo 2 >"$1/.fake/mas/upgrade 1.sleep"; }   # longer than the step limit, within the App Store's four times that
fix_mascurrent(){ upd_tools "$1" mas; : >"$1/.fake/mas/outdated"; }
upd_app(){ mkdir -p "$1/Applications/$2.app/Contents"
  printf '<?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleShortVersionString</key><string>%s</string></dict></plist>' "$3" >"$1/Applications/$2.app/Contents/Info.plist"; }
upd_cask(){ printf '{"token":"%s","version":"%s","artifacts":[{"zap":["x"]},{"app":["%s.app"]}]}' "$@"; }
upd_catalog(){ printf '[%s,%s,%s,%s,%s,%s,%s,%s,%s]' "$(upd_cask macup-old 2.0,abc MacupOld)" "$(upd_cask macup-old@beta 3.0 MacupOld)" "$(upd_cask macup-new 2.0 MacupNew)" \
  "$(upd_cask macup-mas 2.0 MacupMas)" "$(upd_cask macup-twin 2.0 MacupTwin)" "$(upd_cask macup-twin-desktop 7.0 MacupTwin)" "$(upd_cask macup-cafe 1.10 'Macup Café')" \
  "$(upd_cask macup-bin 5.0.1 MacupBin)" "$(upd_cask macup-brewed 9.0 MacupBrewed)"; }
fix_apps(){ upd_tools "$1" curl; mkdir -p "$1/Library/Caches/macup"; upd_catalog >"$1/Library/Caches/macup/cask.json"
  upd_app "$1" MacupOld 1.0; upd_app "$1" MacupNew 2.0; upd_app "$1" MacupMas 1.0; upd_app "$1" MacupTwin 1.0; upd_app "$1" 'Macup Café' '1.9 (build 7)'
  upd_app "$1" MacupBin 5.0; plutil -convert binary1 "$1/Applications/MacupBin.app/Contents/Info.plist"; upd_app "$1" MacupBrewed 1.0
  mkdir -p "$1/Applications/MacupMas.app/Contents/_MASReceipt"; printf 'macup-brewed\n' >"$1/.fake/brew-list"; }
fix_appsdownload(){ fix_apps "$1"; mv "$1/Library/Caches/macup/cask.json" "$1/.fake/cask.json"; }
fix_appscurrent(){ upd_tools "$1" curl; mkdir -p "$1/Library/Caches/macup"; upd_catalog >"$1/Library/Caches/macup/cask.json"; upd_app "$1" MacupNew 2.0; }
fix_appsnone(){ upd_tools "$1" curl; }
fix_simple(){ upd_tools "$1" pipx uv rustup zsh gh pnpm node bun deno cargo cargo-install-update mise asdf code cursor windsurf codium gcloud dotnet composer gem
  mkdir -p "$1/.oh-my-zsh/tools" "$1/.dotnet/tools/x" "$1/.composer"; : >"$1/.oh-my-zsh/tools/upgrade.sh"; : >"$1/.composer/composer.json"
  answer "$1" gh 'extension list' 'dlvhdr/gh-dash  v4.0.0'; answer "$1" pnpm 'ls -g --json' '[{"dependencies":{"x":{"version":"1.0.0"}}}]'; answer "$1" dotnet --version 9.0.100; }
fix_simplefail(){ fix_simple "$1"; local tool first
  for tool in pipx:upgrade-all uv:tool rustup:update gh:extension pnpm:update bun:upgrade deno:upgrade cargo:install-update mise:upgrade asdf:plugin code:--update-extensions cursor:--update-extensions gcloud:components dotnet:tool composer:global gem:update; do
    first=${tool#*:}; mkdir -p "$1/.fake/${tool%%:*}"; echo 1 >"$1/.fake/${tool%%:*}/$first.rc"; done; }
fix_simpleslow(){ fix_simple "$1"; mkdir -p "$1/.fake/rustup"; echo 30 >"$1/.fake/rustup/update.sleep"; }
fix_simplenone(){ upd_tools "$1" gh pnpm dotnet; answer "$1" pnpm 'ls -g --json' '[]'; answer "$1" dotnet --version 8.0.400; mkdir -p "$1/.dotnet/tools/x"; : >"$1/.fake/gh/extension list"; }
fix_grok(){ upd_tools "$1" grok; answer "$1" grok 'update --check --json' '{"currentVersion":"1.0.70","latestVersion":"1.0.77","installer":"internal","error":null}'
  answer "$1" grok --version 'grok 1.0.70'; echo "echo 'grok 1.0.77' >\"\$HOME/.fake/grok/--version\"" >"$1/.fake/grok/update.then"; }
fix_grokfail(){ fix_grok "$1"; rm "$1/.fake/grok/update.then"; echo 1 >"$1/.fake/grok/update.rc"; }
fix_grokoffline(){ upd_tools "$1" grok; answer "$1" grok 'update --check --json' '{"currentVersion":"1.0.70","latestVersion":null,"installer":"internal","error":"offline"}'; }
fix_grokbrew(){ fix_grok "$1"; answer "$1" grok 'update --check --json' '{"currentVersion":"1.0.70","latestVersion":"1.0.77","installer":"brew","error":null}'; }
fix_grokcurrent(){ fix_grok "$1"; answer "$1" grok 'update --check --json' '{"currentVersion":"1.0.77","latestVersion":"1.0.77","installer":"internal"}'; }
fix_agy(){ upd_tools "$1" agy; answer "$1" agy --version 1.2.0; echo 'echo 1.3.0 >"$HOME/.fake/agy/--version"' >"$1/.fake/agy/update.then"; }
fix_agyfail(){ fix_agy "$1"; rm "$1/.fake/agy/update.then"; echo 1 >"$1/.fake/agy/update.rc"; }
su_head=$'Software Update Tool\n\nFinding available software'
fix_macos(){ upd_tools "$1" softwareupdate; answer "$1" softwareupdate -l "$su_head"$'\nSoftware Update found the following new or updated software:
* Label: Command Line Tools for Xcode-16.0\n\tTitle: Command Line Tools for Xcode, Version: 16.0, Size: 746159KiB, Recommended: YES, 
* Label: macOS Sequoia 15.1-24B83\n\tTitle: macOS Sequoia 15.1, Version: 15.1, Size: 6283533KiB, Recommended: YES, Action: restart, 
* Label: Safari18.1VenturaAuto-18.1\n\tTitle: Safari, Version: 18.1, Size: 160000KiB, Recommended: YES, 
* Label: BridgeOSUpdateCustomer\n  Title: BridgeOS\n* Label: Blank-1\n\tTitle: Blank, Version: , Size: 1KiB, '; }
fix_macoslabels(){ upd_tools "$1" softwareupdate
  answer "$1" softwareupdate -l "$su_head"$'\nAn error occurred reading one catalog\n * Label: Command Line Tools for Xcode-16.0\n\t* Label: macOS Sequoia 15.1-24B83\n\xc2\xa0* Label: No-break-1\n\xe3\x80\x80* Label: Wide-1\n\r* Label: Return-1'; echo 1 >"$1/.fake/softwareupdate/-l.rc"; }
# softwareupdate writes its answer to stderr: the check reads both
su_says(){ echo "echo '$2' >&2" >"$1/.fake/softwareupdate/-l.then"; }
fix_macosnone(){ upd_tools "$1" softwareupdate; answer "$1" softwareupdate -l "$su_head"; su_says "$1" 'No new software available.'; }
fix_macosslow(){ fix_macos "$1"; echo 124 >"$1/.fake/softwareupdate/-l.rc"; }
fix_macosoffline(){ upd_tools "$1" softwareupdate; answer "$1" softwareupdate -l "$su_head"; echo 1 >"$1/.fake/softwareupdate/-l.rc"
  su_says "$1" 'Software Update Tool: could not reach the server'; }
fix_macosnonet(){ upd_tools "$1" softwareupdate; answer "$1" softwareupdate -l "$su_head"; su_says "$1" 'NO INTERNET connection'; }
fix_macosagy(){ fix_agy "$1"; fix_macos "$1"; }
fix_everything(){ fix_brew "$1"; fix_claude "$1"; fix_npm "$1"; fix_skills "$1"; fix_mas "$1"; fix_apps "$1"; fix_simple "$1"; fix_grok "$1"; fix_agy "$1"; }

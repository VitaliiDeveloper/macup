# shellcheck shell=bash
# shellcheck disable=SC2154  # work, CASES and the fake helpers come from tests/diff.sh and tests/fakes.sh
# Sourced by tests/diff.sh: the tools unit's cases (tools.sh: MCP servers, brew doctor, Xcode, versions, commands, Docker,
# GitHub CLI, signing certificates, crashes). The tools are answering fakes in the fake home (tests/fakes.sh); what is not
# faked is the Mac's own (python3, openssl, /usr/bin, the real /opt/homebrew/bin and /usr/local/bin the commands check scans).
# A tool that hangs costs its whole limit in every run: only docker info and gh auth status (20 seconds) really hang; for
# claude mcp list (120) and brew doctor (240) a fake exits 124, which both builds read as stopped.
tools_path="PATH=@H/.fake/bin:$work/bin:/usr/bin:/bin"
tools_ids=check.mcp,check.brew_doctor,check.xcode,check.devtools,check.commands,check.docker,check.gh,check.certs,check.crashes
CASES="$CASES
tool-mac||$tools_path|check --only $tools_ids
tool-mac-json||$tools_path|check --only $tools_ids --json
tool-mcp|mcp|$tools_path|check --only check.mcp
tool-mcp-json|mcp|$tools_path|check --only check.mcp --json
tool-mcp-ok|mcpok|$tools_path|check --only check.mcp
tool-mcp-none|mcpnone|$tools_path|check --only check.mcp
tool-mcp-fails|mcpfails|$tools_path|check --only check.mcp
tool-mcp-timeout|mcptimeout|$tools_path|check --only check.mcp
tool-mcp-from-home|mcpquiet|$tools_path|check --only check.mcp
tool-mcp-bytes|mcpbytes|$tools_path|check --only check.mcp
tool-mcp-bytes-c|mcpbytes|$tools_path LC_ALL=C|check --only check.mcp
tool-doctor|doctor|$tools_path|check --only check.brew_doctor
tool-doctor-ok|doctorok|$tools_path|update --only check.brew_doctor
tool-doctor-timeout|doctorslow|$tools_path|check --only check.brew_doctor
tool-doctor-bytes|doctorbytes|$tools_path|check --only check.brew_doctor
tool-doctor-bytes-c|doctorbytes|$tools_path LC_ALL=C|check --only check.brew_doctor
tool-xcode|xcode|$tools_path|check --only check.xcode
tool-xcode-json|xcode|$tools_path|check --only check.xcode --json
tool-xcode-clt|xcodeclt|$tools_path|check --only check.xcode
tool-xcode-broken|xcodebroken|$tools_path|check --only check.xcode,check.devtools
tool-devtools|devtools|$tools_path|check --only check.devtools
tool-devtools-broken|devtoolsbroken|$tools_path|check --only check.devtools
tool-commands|commands|$tools_path:@H/no/such:/macup/no/such:@H/no/such:@H/a,b:@H/.local/bin:@H HOMEBREW_PREFIX=@H/brew|check --only check.commands
tool-commands-json|commands|$tools_path:@H/no/such HOMEBREW_PREFIX=@H/brew|check --only check.commands --json
tool-commands-uv|commandsuv|$tools_path HOMEBREW_PREFIX=@H/brew|check --only check.commands
tool-commands-ok|commandsok|$tools_path|check --only check.commands
tool-docker|docker|$tools_path|check --only check.docker
tool-docker-none|dockernone|$tools_path|check --only check.docker
tool-docker-down|dockerdown|$tools_path|check --only check.docker
tool-docker-hangs|dockerslow|$tools_path|check --only check.docker|pipe
tool-gh|gh|$tools_path|check --only check.gh
tool-gh-ok|ghok|$tools_path|check --only check.gh
tool-gh-config-dir|ghdir|$tools_path GH_CONFIG_DIR=@H/ghdir|check --only check.gh
tool-gh-xdg|ghxdg|$tools_path XDG_CONFIG_HOME=@H/xdg|check --only check.gh
tool-gh-empty|ghempty|$tools_path|check --only check.gh
tool-gh-hangs|ghslow|$tools_path|check --only check.gh|pipe
tool-certs|certs|$tools_path|check --only check.certs
tool-certs-none|certsnone|$tools_path|check --only check.certs
tool-crashes|crashes|$tools_path|check --only check.crashes
tool-crashes-json|crashes|$tools_path|check --only check.crashes --json
tool-crashes-few|crashesfew|$tools_path|check --only check.crashes
tool-all|toolsall|$tools_path FAKE_SUDO_RC=0|all --only $tools_ids"

tools_fakes(){ local home=$1 tool; shift; answering "$home/.fake/bin" "$@"; for tool; do mkdir -p "$home/.fake/$tool"; done; }

fix_mcp(){ tools_fakes "$1" claude
  answer "$1" claude 'mcp list' "$(printf 'Checking MCP server health...\n\nfigma: https://mcp.figma.com/mcp (HTTP) - \033[32m✓ Connected\033[0m\nlinear: npx -y linear-mcp - \033[31m✗ Failed to connect\033[0m\nnotion: https://mcp.notion.com/mcp (HTTP) - ⚠️ Needs authentication\nsentry: https://mcp.sentry.dev/mcp (SSE) - ✔ connected\nlocal: ./server.js - ✘ failed\n')"; }
fix_mcpok(){ tools_fakes "$1" claude; answer "$1" claude 'mcp list' "$(printf 'figma: https://mcp.figma.com/mcp (HTTP) - ✓ Connected\ngithub: npx gh-mcp - ✓ Connected')"; }
fix_mcpnone(){ tools_fakes "$1" claude; answer "$1" claude 'mcp list' 'No MCP servers configured. Use `claude mcp add` to add a server.'; }
fix_mcpfails(){ fix_mcp "$1"; echo 1 >"$1/.fake/claude/mcp list.rc"; answer "$1" claude 'mcp list' 'Error: config is not valid JSON'; }
fix_mcptimeout(){ fix_mcp "$1"; echo 124 >"$1/.fake/claude/mcp list.rc"; }
# bytes that are not UTF-8: in a UTF-8 locale nocolor's sed stops at that line; the report keeps brew's bytes; NULs go
fix_mcpbytes(){ tools_fakes "$1" claude
  printf 'figma: https://mcp.figma.com/mcp - \033[32m✓ Connected\033[0m\ncaf\351: npx caf\351 - ✓ Connected\nlinear: npx linear - ✗ Failed to connect\n' >"$1/.fake/claude/mcp list"; }
fix_doctorbytes(){ tools_fakes "$1" brew; printf 'Warning: caf\351 is not UTF-8\n  a\000b\nWarning: second\n\n' >"$1/.fake/brew/doctor"; }
fix_mcpquiet(){ tools_fakes "$1" claude; }   # no answer: calls.log says the list was asked from the home folder

fix_doctor(){ tools_fakes "$1" brew
  answer "$1" brew doctor "$(printf 'Please note that these warnings are just used to help the Homebrew maintainers.\n\nWarning: Some installed formulae are deprecated or disabled.\n  python@3.9\n\nWarning: Unbrewed dylibs were found in /usr/local/lib.')"
  echo 'echo "Warning: You have uncommitted modifications to Homebrew/homebrew-core" >&2' >"$1/.fake/brew/doctor.then"; }
fix_doctorok(){ tools_fakes "$1" brew; answer "$1" brew doctor 'Your system is ready to brew.'; }
fix_doctorslow(){ fix_doctor "$1"; echo 124 >"$1/.fake/brew/doctor.rc"; }

tools_runtimes='{"B2":{"platformIdentifier":"com.apple.platform.iphonesimulator","version":"18.2","sizeBytes":7516192768,"deletable":true},
"A1":{"platformIdentifier":"com.apple.platform.iphonesimulator","version":"17.5","sizeBytes":6979321856},
"C3":{"platformIdentifier":"com.apple.platform.watchsimulator","version":"11.2","sizeBytes":3221225472},
"D4":{"platformIdentifier":"com.apple.platform.appletvsimulator","version":"18.2","sizeBytes":123456789}}'
fix_xcode(){ tools_fakes "$1" xcode-select xcodebuild xcrun; mkdir -p "$1/Xcode.app/Contents/Developer"
  answer "$1" xcode-select -p "$1/Xcode.app/Contents/Developer"; answer "$1" xcodebuild -version "$(printf 'Xcode 16.1\nBuild version 16B40')"
  answer "$1" xcrun 'simctl runtime list -j' "$tools_runtimes"; }
fix_xcodeclt(){ fix_xcode "$1"; : >"$1/.fake/xcodebuild/-version"; echo 1 >"$1/.fake/xcodebuild/-version.rc"; answer "$1" xcrun 'simctl runtime list -j' '{}'; }
fix_xcodebroken(){ fix_xcode "$1"; answer "$1" xcode-select -p "$1/no/such/Developer"; echo 2 >"$1/.fake/xcode-select/-p.rc"; answer "$1" xcrun 'simctl runtime list -j' '{"x": '; }

fix_devtools(){ tools_fakes "$1" swift pod flutter node ruby codex
  answer "$1" swift --version "$(printf 'Apple Swift version 6.0.3 (swiftlang-6.0.3.1.10 clang-1600.0.30.1)\nTarget: arm64-apple-macosx15.0')"
  echo 'echo "swift-driver version: 1.115.1 " >&2' >"$1/.fake/swift/--version.then"
  answer "$1" pod --version 1.16.2
  answer "$1" flutter --version "$(printf 'Flutter 3.24.5 • channel stable • https://github.com/flutter/flutter.git\nFramework • revision dec2ee5c1f')"
  answer "$1" node --version v22.11.0; answer "$1" ruby '-e print RUBY_VERSION' 3.3.6; answer "$1" codex --version 'codex-cli 0.58.0'; }
fix_devtoolsbroken(){ fix_devtools "$1"; answer "$1" swift --version 'error: unable to find a toolchain'; answer "$1" flutter --version ''
  answer "$1" node --version v; answer "$1" codex --version ''; answer "$1" pod --version ''; echo 1 >"$1/.fake/pod/--version.rc"; answer "$1" ruby '-e print RUBY_VERSION' ''; }

# scripts whose interpreter is gone, a pipx venv whose Python went, dead links, Homebrew's own files, kegs brew has not linked
fix_commands(){ local bin="$1/.local/bin" venv="$1/.local/pipx/venvs/tool/bin" index keg
  mkdir -p "$bin" "$1/.npm-global/bin" "$venv" "$1/Cellar/x/1/bin"
  printf '#!/usr/bin/env macup_no_such_interp\n' >"$bin/nodecli"; printf '#!/usr/bin/env -S macup_no_such_interp --flag\n' >"$1/.npm-global/bin/flagcli"
  printf '#!/bin/sh\necho ok\n' >"$bin/okscript"; cp /usr/bin/true "$bin/okbinary"; printf '#!/usr/bin/env\n' >"$bin/bareenv"; printf '#!\n' >"$bin/empty"
  printf '#!/usr/bin/env VAR=1 sh\n' >"$bin/withvar"; printf '#! /bin/sh -e\n' >"$bin/spaced"; printf '#!/usr/bin/env\tmacup_tab_interp\r\n' >"$bin/crlf"
  ln -s "$1/gone/python3.12" "$venv/python"; printf '#!%s\n' "$venv/python" >"$venv/tool"; ln -s "$venv/tool" "$bin/pipxtool"
  for index in 01 02 03 04 05 06 07 08 09 10 11; do ln -s "$1/gone/thing" "$bin/gone$index"; done
  ln -s "$1/gone/Old.app/Contents/MacOS/old" "$bin/oldapp"; ln -s ../lib/node_modules/@scope/pkg/cli.js "$1/.npm-global/bin/scoped"
  ln -s "/Library/Frameworks/Python.framework/Versions/3.8/bin/python3.8" "$bin/framework"; ln -s loop "$bin/loop"
  printf '#!/usr/bin/env macup_no_such_interp\n' >"$1/Cellar/x/1/bin/brewcli"; ln -s "$1/Cellar/x/1/bin/brewcli" "$bin/brewcli"; ln -s "$1/Cellar/y/1/bin/gone" "$bin/brewgone"
  printf '#!/usr/bin/env macup_keg_interp\n' >"$bin/kegcli"; printf '#!/usr/bin/env macup_plain_interp\n' >"$bin/plaincli"
  for keg in macup_keg_interp@9/bin/macup_keg_interp macup_keg_interp@10/bin/macup_keg_interp macup_plain_interp/bin/macup_plain_interp; do mkdir -p "$1/brew/opt/${keg%/*}"; cp /usr/bin/true "$1/brew/opt/$keg"; done
  printf '#!%s\n' "$1/gone/bin/sh" >"$bin/deadsh"; printf '#!/usr/bin/env macup_no_such_interp\n' >"$bin/notexec"
  chmod +x "$bin"/* "$venv/tool" "$1/.npm-global/bin/flagcli" "$1/Cellar/x/1/bin/brewcli" 2>/dev/null; chmod -x "$bin/notexec"
}
fix_commandsuv(){ local uv="$1/.local/share/uv/tools/sometool/bin"; mkdir -p "$uv" "$1/.local/bin"; ln -s "$1/gone/python3.11" "$uv/python"
  printf '#!%s\n' "$uv/python" >"$uv/sometool"; chmod +x "$uv/sometool"; ln -s "$uv/sometool" "$1/.local/bin/sometool"
  mkdir -p "$1/.npm-global"; ln -s ../.local/bin "$1/.npm-global/bin"; }   # the same folder twice: scanned once
fix_commandsok(){ mkdir -p "$1/.local/bin"; printf '#!/bin/sh\n' >"$1/.local/bin/fine"; chmod +x "$1/.local/bin/fine"; }

tools_df='system df --format {{.Type}} {{.Size}}, {{.Reclaimable}} reclaimable' tools_volumes='volume ls -qf dangling=true'
fix_docker(){ tools_fakes "$1" docker; answer "$1" docker info ''
  answer "$1" docker "$tools_df" "$(printf 'Images 2.4GB, 1.2GB (50%%) reclaimable\nContainers 12.3MB, 12.3MB (100%%) reclaimable\nLocal Volumes 3.2GB, 3.2GB (100%%) reclaimable\nBuild Cache 1.5GB, 1.5GB reclaimable')"
  answer "$1" docker "$tools_volumes" "$(printf 'vol1\nvol2\n')"; }
fix_dockernone(){ fix_docker "$1"; : >"$1/.fake/docker/$tools_df"; : >"$1/.fake/docker/$tools_volumes"; }
fix_dockerdown(){ fix_docker "$1"; echo 1 >"$1/.fake/docker/info.rc"; }
fix_dockerslow(){ fix_docker "$1"; echo 30 >"$1/.fake/docker/info.sleep"; }

fix_gh(){ tools_fakes "$1" gh; mkdir -p "$1/.config/gh"; echo 'github.com:' >"$1/.config/gh/hosts.yml"; : >"$1/.fake/gh/auth status"
  printf 'echo "github.com" >&2; echo "  X Failed to log in to github.com account someone (default)" >&2; echo "  - The token in default is invalid." >&2; exit 1\n' >"$1/.fake/gh/auth status.then"; }
fix_ghok(){ fix_gh "$1"; answer "$1" gh 'auth status' "$(printf 'github.com\n  ✓ Logged in to github.com account someone (keyring)')"; rm "$1/.fake/gh/auth status.then"; }
fix_ghdir(){ fix_gh "$1"; mkdir -p "$1/ghdir"; mv "$1/.config/gh/hosts.yml" "$1/ghdir/"; }
fix_ghxdg(){ fix_gh "$1"; mkdir -p "$1/xdg"; mv "$1/.config/gh" "$1/xdg/"; }
fix_ghslow(){ fix_gh "$1"; rm "$1/.fake/gh/auth status.then"; echo 30 >"$1/.fake/gh/auth status.sleep"; }
fix_ghempty(){ fix_gh "$1"; : >"$1/.config/gh/hosts.yml"; }

# signing certificates made once per run of this script: a fake security lists identities and hands out the certificates
tools_certs(){ [ -f "$work/certs.pem" ] && return
  tools_cert(){ openssl req -x509 -newkey rsa:2048 -nodes -keyout /dev/null -days "$2" -subj "/CN=$1/O=Test" 2>/dev/null; }
  { tools_cert 'Apple Development: Soon Gone (AAAA111111)' 10; tools_cert 'Apple Distribution: Long Lived (BBBB222222)' 300; tools_cert 'Some Web Server' 5
    tools_cert 'Apple Development: Renewed (CCCC333333)' 10; tools_cert 'Apple Development: Renewed (CCCC333333)' 300; tools_cert 'Apple Development: No Key (DDDD444444)' 5
    tools_cert 'Developer ID Application: Acme, Inc. (EEEE555555)' 10; tools_cert 'Apple Development: Älter (FFFF666666)' 1
    tools_cert 'Apple Development: Expired (GGGG777777)' 5; } >"$work/certs.pem"; }
# the stock openssl cannot make a certificate that has already expired: this one says so of the one named Expired
tools_openssl='#!/bin/bash
pem=$(cat)
[ "$*" = "x509 -noout -checkend 0" ] && printf "%s\n" "$pem" | /usr/bin/openssl x509 -noout -subject | grep -q Expired && exit 1
printf "%s\n" "$pem" | /usr/bin/openssl "$@"'
fix_certs(){ tools_certs; tools_fakes "$1" security; cp "$work/certs.pem" "$1/.fake/security/find-certificate -a -p"
  printf '%s\n' "$tools_openssl" >"$1/.fake/bin/openssl"; chmod +x "$1/.fake/bin/openssl"
  printf '  1) 0000000000000000000000000000000000000001 "Apple Development: Soon Gone (AAAA111111)"\n  2) 0000000000000000000000000000000000000002 "Apple Distribution: Long Lived (BBBB222222)"\n  3) 0000000000000000000000000000000000000003 "Apple Development: Renewed (CCCC333333)"\n  4) 0000000000000000000000000000000000000004 "Developer ID Application: Acme, Inc. (EEEE555555)"\n  5) 0000000000000000000000000000000000000005 "Apple Development: Älter (FFFF666666)"\n  6) 0000000000000000000000000000000000000006 "Apple Development: Expired (GGGG777777)"\n     6 valid identities found\n' >"$1/.fake/security/find-identity -v -p codesigning"; }
fix_certsnone(){ fix_certs "$1"; printf '     0 valid identities found\n' >"$1/.fake/security/find-identity -v -p codesigning"; }

# crash reports: .ips (a JSON line, then the report) and the older .crash, in DiagnosticReports and Retired
# one time for the whole script: the bash and the Swift run of a case must find the same files
tools_now=$(date +%s)
tools_ago(){ date -u -r $((tools_now - $1 * 86400)) "+%Y-%m-%d %H:%M:%S${2:-.00 +0000}"; }
tools_ips(){ # file app bug_type days-ago procPath
  printf '{"app_name":"%s","timestamp":"%s","bug_type":"%s","name":"%s"}\n{"procPath":"%s","procName":"%s"}\n' "$2" "$(tools_ago "$4")" "$3" "$2" "$5" "$2" >"$1"; }
fix_crashes(){ local reports="$1/Library/Logs/DiagnosticReports" index app
  mkdir -p "$reports/Retired"
  for index in 1 2; do
    tools_ips "$reports/Crashy App-2026-11-2$index-10000$index.ips" 'Crashy App' 309 1 '\/Applications\/Crashy App.app\/Contents\/MacOS\/Crashy App'
    tools_ips "$reports/Retired/Crashy App-2026-11-1$index-10000$index.ips" 'Crashy App' 309 2 '/Applications/Crashy App.app/Contents/MacOS/Crashy App'
  done
  for index in 1 2 3; do
    tools_ips "$reports/ExcUserFault_Crashy App-2026-11-2$index-1.ips" 'Crashy App' 309 1 '/Applications/Crashy App.app/x'
    tools_ips "$reports/Retired/Old App-2026-10-0$index-1.ips" 'Old App' 309 20 '/Applications/Old App.app/x'
    tools_ips "$reports/Hang App-2026-11-2$index-1.ips" 'Hang App' 385 1 '/Applications/Hang App.app/x'
    tools_ips "$reports/Home App_2026-11-2$index-1.ips" 'Home App' 309 3 "$1/Applications/Home App.app/x"
    tools_ips "$reports/Comma App-$index.ips" 'Comma, Inc App' 309 1 '/Applications/Comma.app/x'
    tools_ips "$reports/Two App-$index.ips" 'Two  Spaces' 309 1 '/Applications/Two.app/x'
    tools_ips "$reports/Zed App-$index.ips" 'Zed' 309 1 '/Applications/Zed.app/x'
    printf 'Process: Legacy App [1]\r\nPath:            /Applications/Legacy App.app/Contents/MacOS/Legacy App  \r\n' >"$reports/Legacy App_2026-11-1$index-100000_Mac.crash"
  done
  for index in 1 2 3 4 5; do tools_ips "$reports/Retired/sysd-$index.ips" sysd 309 1 '/System/Library/CoreServices/sysd'; done
  tools_ips "$reports/Retired/Crashy App-2026-11-21-100001.ips" 'Crashy App' 309 1 '/Applications/Crashy App.app/x'   # the same name again: counted once
  printf '{"bug_type":309,"timestamp":"%s"}\n{"procPath":"/Applications/Number Bug.app/x"}\n' "$(tools_ago 1)" >"$reports/Number Bug-2026-11-25.ips"
  printf '{"app_name":"Bad Stamp","bug_type":"309","timestamp":"yesterday"}\n{"procPath":"/Applications/Bad.app/x"}\n' >"$reports/Bad Stamp-1.ips"
  cp "$reports/Bad Stamp-1.ips" "$reports/Bad Stamp-2.ips"; touch -t 202001010000 "$reports/Bad Stamp-2.ips"
  printf '{"app_name":"Zone App","bug_type":"309","timestamp":"%s"}\n{"procPath":"/Applications/Zone.app/x"}\n' "$(tools_ago 1 '.123456 +01:00')" >"$reports/Zone App-1.ips"
  printf 'not json\n{"procPath":"/Applications/Crashy App.app/x"}\n' >"$reports/Crashy App-broken.ips"
  printf '{"app_name":"Escape","bug_type":"309"}\n{"procPath":"/Applications/\\q.app"}\n' >"$reports/Escape-1.ips"
  tools_ips "$reports/.Crashy App-hidden.ips" 'Crashy App' 309 1 '/Applications/Crashy App.app/x'; mkdir -p "$reports/Folder.ips"; ln -s "$1/gone" "$reports/Dead-1.ips"; }
fix_crashesfew(){ local reports="$1/Library/Logs/DiagnosticReports"; mkdir -p "$reports"
  tools_ips "$reports/Crashy App-1.ips" 'Crashy App' 309 1 '/Applications/Crashy App.app/x'; tools_ips "$reports/sysd-1.ips" sysd 309 1 /usr/libexec/sysd; }
fix_toolsall(){ fix_mcp "$1"; fix_doctor "$1"; fix_xcode "$1"; fix_devtools "$1"; fix_commands "$1"; fix_docker "$1"; fix_gh "$1"; fix_certs "$1"; fix_crashes "$1"; }

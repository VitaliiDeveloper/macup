#!/bin/bash
# macup — the bootstrap that moves a 2.9 install onto the 3.0 binary. https://github.com/VitaliiDeveloper/macup · MIT License
#
# A 2.9 copy updates itself from main/macup: it reads MACUP_VERSION below, installs this file over itself and checks it with
# bash -n, nothing more. The next run lands here: this downloads the release binary, checks it, replaces itself with it by
# rename, points the schedule at it and runs the command that was asked for. A Mac older than macOS 13, where the binary
# cannot start, gets the last 2.9 script instead. Becomes the root macup at the end of phase 5 (docs/swift-port-plan.md).
MACUP_VERSION="3.0.0"
LEGACY_VERSION="2.9.2"   # the last 2.9.x, for Macs older than macOS 13

REPO="${MACUP_REPO:-VitaliiDeveloper/macup}"
LABEL="com.vitaliideveloper.macup"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

conf_language(){
  sed -n 's/^[[:space:]]*language[[:space:]]*=[[:space:]]*//p' "${XDG_CONFIG_HOME:-$HOME/.config}/macup/config" 2>/dev/null \
    | sed 's/[[:space:]]*#.*$//; s/[[:space:]]*$//' | tail -1
}
LANGUAGE="${MACUP_LANG:-$(conf_language)}"
[ "$LANGUAGE" = ua ] && LANGUAGE=uk

# shellcheck disable=SC2059  # the format is one of the texts below
say(){ # message id, its values → stderr, so a command's own output stays clean
  local text
  case "$LANGUAGE:$1" in
    uk:brew)      text='macup встановлено через Homebrew. Онови його так: brew upgrade macup' ;;
    ru:brew)      text='macup установлен через Homebrew. Обновите его так: brew upgrade macup' ;;
    *:brew)       text='macup was installed with Homebrew. Update it with: brew upgrade macup' ;;
    uk:legacy)    text='macup %s потребує macOS 13 або новішої; на цьому Маку лишається macup %s.' ;;
    ru:legacy)    text='macup %s требует macOS 13 или новее; на этом Маке остаётся macup %s.' ;;
    *:legacy)     text='macup %s needs macOS 13 or later; this Mac keeps macup %s.' ;;
    uk:finish)    text='Завершую оновлення до macup %s…' ;;
    ru:finish)    text='Завершаю обновление до macup %s…' ;;
    *:finish)     text='Finishing the update to macup %s…' ;;
    uk:missing)   text='macup %s ще не опубліковано, або завантаження не вдалося: %s. Нічого не змінено; запусти macup ще раз за кілька хвилин.' ;;
    ru:missing)   text='macup %s ещё не опубликован, или скачать не удалось: %s. Ничего не изменено; запустите macup ещё раз через несколько минут.' ;;
    *:missing)    text='macup %s is not published yet, or the download failed: %s. Nothing changed; run macup again in a few minutes.' ;;
    uk:dlfail)    text='Не вдалося завантажити: %s' ;;
    ru:dlfail)    text='Не удалось скачать: %s' ;;
    *:dlfail)     text='Download failed: %s' ;;
    uk:sum)       text='Завантажений файл не збігається з опублікованою контрольною сумою; нічого не змінено.' ;;
    ru:sum)       text='Скачанный файл не совпадает с опубликованной контрольной суммой; ничего не изменено.' ;;
    *:sum)        text='The downloaded file does not match its published checksum; nothing changed.' ;;
    uk:broken)    text='Завантажений файл пошкоджений; нічого не змінено.' ;;
    ru:broken)    text='Скачанный файл повреждён; ничего не изменено.' ;;
    *:broken)     text='The downloaded file looks broken; nothing changed.' ;;
    uk:write)     text='Не вдалося записати %s' ;;
    ru:write)     text='Не удалось записать %s' ;;
    *:write)      text="Couldn't write %s" ;;
    uk:scheduled) text='Ця запланована перевірка запускає macup %s з тимчасової копії; запусти macup один раз у Терміналі, щоб завершити оновлення.' ;;
    ru:scheduled) text='Эта плановая проверка запускает macup %s из временной копии; запустите macup один раз в Терминале, чтобы завершить обновление.' ;;
    *:scheduled)  text='This scheduled check runs macup %s from a temporary copy; run macup once in Terminal to finish the update.' ;;
    uk:schedule)  text='launchd не прийняв оновлений розклад; він запрацює після наступного входу в систему.' ;;
    ru:schedule)  text='launchd не принял обновлённое расписание; оно заработает после следующего входа в систему.' ;;
    *:schedule)   text='launchd did not take the updated schedule; it applies after the next login.' ;;
    uk:installed) text='macup %s встановлено: %s' ;;
    ru:installed) text='macup %s установлен: %s' ;;
    *:installed)  text='macup %s is installed: %s' ;;
  esac
  shift; printf "$text\n" "$@" >&2
}

fetch(){ curl -fsSL --max-time 600 "$1" -o "$2" 2>/dev/null; }
sum_ok(){ local want; want=$(awk '{print $1; exit}' "$2"); [ -n "$want" ] && [ "$(shasum -a 256 "$1" | awk '{print $1}')" = "$want" ]; }
is_bootstrap(){ grep -q '^LEGACY_VERSION=' "$1" 2>/dev/null; }   # a line only this file has: never run or install it twice

binary(){ # → $WORK/macup: the release binary, checked; exits with the reason when there is none
  local asset="macup-$MACUP_VERSION-macos-universal.tar.gz" url
  url="https://github.com/$REPO/releases/download/v$MACUP_VERSION/$asset"
  if ! fetch "$url.sha256" "$WORK/sum" || ! fetch "$url" "$WORK/$asset"; then say missing "$MACUP_VERSION" "$url"; exit 1; fi
  sum_ok "$WORK/$asset" "$WORK/sum" || { say sum; exit 1; }
  tar -xzf "$WORK/$asset" -C "$WORK" macup 2>/dev/null && [ -f "$WORK/macup" ] && ! is_bootstrap "$WORK/macup" && chmod 755 "$WORK/macup" \
    && [ "$("$WORK/macup" version </dev/null 2>/dev/null)" = "macup $MACUP_VERSION" ] || { say broken; exit 1; }
}

legacy(){ # → $WORK/macup: the last 2.9 script, checked as 2.9 checks its own updates
  local url="https://raw.githubusercontent.com/$REPO/v$LEGACY_VERSION/macup"
  fetch "$url.sha256" "$WORK/sum" && fetch "$url" "$WORK/macup" || { say dlfail "$url"; exit 1; }
  sum_ok "$WORK/macup" "$WORK/sum" || { say sum; exit 1; }
  /bin/bash -n "$WORK/macup" 2>/dev/null && grep -qx "MACUP_VERSION=\"$LEGACY_VERSION\"" "$WORK/macup" && chmod 755 "$WORK/macup" || { say broken; exit 1; }
}

# 2.9 wrote ProgramArguments as /bin/bash <macup> check --quiet --notify; with a binary there launchd fails with 126 forever.
# Before the swap (this script runs through its #! line as well), and never from the scheduled run itself: launchctl
# bootout would stop this very job before bootstrap could load it again. Right after a bootout, bootstrap can fail once.
reschedule(){
  local domain; domain="gui/$(id -u)"
  grep -q '<array><string>/bin/bash</string>' "$PLIST" 2>/dev/null || return 0
  sed 's|<array><string>/bin/bash</string>|<array>|' "$PLIST" >"$PLIST.new" && mv -f "$PLIST.new" "$PLIST" || { rm -f "$PLIST.new"; say write "$PLIST"; return 1; }
  launchctl bootout "$domain/$LABEL" 2>/dev/null || launchctl unload "$PLIST" 2>/dev/null
  launchctl bootstrap "$domain" "$PLIST" 2>/dev/null || { sleep 1; launchctl bootstrap "$domain" "$PLIST" 2>/dev/null; } \
    || launchctl load -w "$PLIST" 2>/dev/null || say schedule
}

main(){
  local self=$0 link major
  # bash runs `bash macup` from the current folder, else from PATH
  case "$self" in /*) ;; */*) self="$PWD/$self" ;; *) if [ -f "$self" ]; then self="$PWD/$self"; else self=$(command -v "$self"); fi ;; esac
  while [ -L "$self" ]; do link=$(readlink "$self"); case "$link" in /*) self=$link ;; *) self="$(dirname "$self")/$link" ;; esac; done
  # Homebrew owns that file, and the next brew upgrade would put its own version back
  case "$self" in */Cellar/macup/*) say brew; exit 1 ;; esac
  [ -f "$self" ] || { say write "$0"; exit 1; }
  # a version it cannot read is taken as new enough: a binary that cannot start fails its check, and nothing changes
  major=$(sw_vers -productVersion 2>/dev/null | cut -d. -f1)
  case "$major" in ''|*[!0-9]*) major=99 ;; esac

  trap 'rm -rf "$WORK"' EXIT; trap 'exit 1' INT TERM HUP
  if [ "$major" -ge 13 ] && { [ "$PPID" = 1 ] || [ "${XPC_SERVICE_NAME:-}" = "$LABEL" ]; }; then
    # started by launchd: this check runs from a temporary copy and changes nothing, so the schedule keeps working
    WORK=$(mktemp -d "${TMPDIR:-/tmp}/macup-update.XXXXXX") || exit 1
    binary; say scheduled "$MACUP_VERSION"
    "$WORK/macup" "$@"; exit
  fi
  # next to the file it replaces, so the swap is a rename: a running macup keeps its old file
  WORK=$(mktemp -d "$(dirname "$self")/.macup-update.XXXXXX" 2>/dev/null) || { say write "$self"; exit 1; }
  if [ "$major" -lt 13 ]; then
    legacy; mv -f "$WORK/macup" "$self" || { say write "$self"; exit 1; }
    say legacy "$MACUP_VERSION" "$LEGACY_VERSION"; rm -rf "$WORK"
    # 2.9's self-update would install this bootstrap again, which would put 2.9 back again
    case "${1:-}" in self-update|selfupdate|upgrade) exit 0 ;; esac
    exec /bin/bash "$self" "$@"
  fi
  say finish "$MACUP_VERSION"; binary
  reschedule || exit 1
  mv -f "$WORK/macup" "$self" || { say write "$self"; exit 1; }
  say installed "$MACUP_VERSION" "$self"; rm -rf "$WORK"
  exec "$self" "$@"
}
main "$@"; exit

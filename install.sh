#!/bin/bash
# macup installer — one command, a few questions, done.
#
#   curl -fsSL https://raw.githubusercontent.com/VitaliiDeveloper/macup/main/install.sh | bash
#   ./install.sh                      (from a cloned repo)
#
# Options:  --lang en|uk|ru   --projects "~/Code, ~/Work"   --yes (no questions)   --prefix DIR
# Installs to ~/.local/bin/macup. No sudo.
set -o pipefail

REPO="${MACUP_REPO:-VitaliiDeveloper/macup}"
RAW="https://raw.githubusercontent.com/$REPO"   # + /<branch or tag>/<file>
BIN_DIR="${MACUP_PREFIX:-$HOME/.local/bin}"
lang="${MACUP_LANG:-}"; PROJECTS=""; YES=0

while [ $# -gt 0 ]; do case "$1" in
  --lang) lang="$2"; shift ;; --lang=*) lang="${1#*=}" ;;
  --projects) PROJECTS="$2"; shift ;; --projects=*) PROJECTS="${1#*=}" ;;
  --prefix) BIN_DIR="$2"; shift ;; --prefix=*) BIN_DIR="${1#*=}" ;;
  -y|--yes) YES=1 ;;
  -h|--help) cat <<'EOF'
macup installer. Installs to ~/.local/bin/macup, no sudo.
  --lang en|uk|ru          interface language
  --projects "~/Code, …"   where your code lives
  --prefix DIR             install somewhere else
  --yes                    no questions
EOF
    exit 0 ;;
  *) echo "Unknown option: $1 (see --help)" >&2; exit 2 ;;
esac; shift; done
TARGET="$BIN_DIR/macup"

if [ -t 1 ]; then bold=$'\033[1m'; red=$'\033[31m'; dim=$'\033[2m'; reset=$'\033[0m'; else bold=; red=; dim=; reset=; fi
# questions work even under `curl | bash`, where stdin is the script itself
INTERACTIVE=0; [ "$YES" = 0 ] && [ -r /dev/tty ] && { : </dev/tty; } 2>/dev/null && INTERACTIVE=1
ask(){ local answer; printf '%s' "$1" >/dev/tty; read -r answer </dev/tty; echo "$answer"; }

[ "$(uname -s)" = Darwin ] || { echo "macup is for macOS only."; exit 1; }

CONF="${XDG_CONFIG_HOME:-$HOME/.config}/macup/config"
HAD_CONF=0; [ -f "$CONF" ] && HAD_CONF=1   # reinstall: keep the user's settings
conf_get(){ sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*//p" "$CONF" 2>/dev/null | sed 's/[[:space:]]*#.*$//; s/[[:space:]]*$//' | tail -1; }

# ---------------------------------------------------------------- language
sys_lang(){ case "$(defaults read -g AppleLanguages 2>/dev/null | sed -n '2p' | tr -d ' ",')" in uk*) echo uk ;; ru*) echo ru ;; *) echo en ;; esac; }
if [ -z "$lang" ]; then
  [ "$HAD_CONF" = 1 ] && lang=$(conf_get language)
  case "$lang" in en|uk|ru) ;; *) lang=$(sys_lang) ;; esac
  if [ "$INTERACTIVE" = 1 ]; then
    printf '\n%smacup%s\n\n  1  English\n  2  Українська\n  3  Русский\n\n' "$bold" "$reset" >/dev/tty
    choice=1; [ "$lang" = uk ] && choice=2; [ "$lang" = ru ] && choice=3
    case "$(ask "Language / Мова / Язык [$choice]: ")" in 1) lang=en ;; 2) lang=uk ;; 3) lang=ru ;; "") ;; *) ;; esac
  fi
fi
case "$lang" in en|uk|ru) ;; ua) lang=uk ;; *) lang=en ;; esac

text(){ # message id
  case "$lang:$1" in
  uk:dl)      echo "Завантажую macup з github.com/$REPO" ;;
  ru:dl)      echo "Скачиваю macup с github.com/$REPO" ;;
  *:dl)       echo "Downloading macup from github.com/$REPO" ;;
  uk:local)   echo "Встановлюю з локальної копії" ;;
  ru:local)   echo "Устанавливаю из локальной копии" ;;
  *:local)    echo "Installing from the local copy" ;;
  uk:dlfail)  echo "Не вдалося завантажити" ;;
  ru:dlfail)  echo "Не удалось скачать" ;;
  *:dlfail)   echo "Download failed" ;;
  uk:sum)     echo "Завантажений файл не збігається з опублікованою контрольною сумою, нічого не встановлено." ;;
  ru:sum)     echo "Скачанный файл не совпадает с опубликованной контрольной суммой, ничего не установлено." ;;
  *:sum)      echo "The download does not match its published checksum; nothing was installed." ;;
  uk:broken)  echo "Скрипт пошкоджений, нічого не встановлено." ;;
  ru:broken)  echo "Скрипт повреждён, ничего не установлено." ;;
  *:broken)   echo "The script is broken; nothing was installed." ;;
  uk:nobuild) echo "У цій копії ще немає зібраного macup: спершу запусти ./build.sh" ;;
  ru:nobuild) echo "В этой копии ещё нет собранного macup: сначала запустите ./build.sh" ;;
  *:nobuild)  echo "This checkout has no built macup yet: run ./build.sh first" ;;
  uk:write)   echo "Не вдалося записати" ;;
  ru:write)   echo "Не удалось записать" ;;
  *:write)    echo "Couldn't write" ;;
  uk:unfinished) echo "macup не запустився (причина вище); запусти встановлення ще раз за кілька хвилин." ;;
  ru:unfinished) echo "macup не запустился (причина выше); запустите установку ещё раз через несколько минут." ;;
  *:unfinished)  echo "macup did not start (the reason is above); run the installer again in a few minutes." ;;
  uk:inst)    echo "Встановлено" ;;
  ru:inst)    echo "Установлено" ;;
  *:inst)     echo "Installed" ;;
  uk:old)     echo "Прибрав стару копію" ;;
  ru:old)     echo "Удалил старую копию" ;;
  *:old)      echo "Removed old copy" ;;
  uk:path)    echo "Додав у PATH" ;;
  ru:path)    echo "Добавил в PATH" ;;
  *:path)     echo "Added to PATH" ;;
  uk:proj)    echo "У яких папках лежать твої проєкти з кодом?" ;;
  ru:proj)    echo "В каких папках лежат ваши проекты с кодом?" ;;
  *:proj)     echo "Which folders hold your code projects?" ;;
  uk:projwhy) printf '%s\n' "  macup шукає там залишки збірки (node_modules, Pods, .build) і показує, скільки вони займають." \
                             "  Сам нічого там не видаляє, хіба що ти окремо ввімкнеш clean.stale_node_modules." \
                             "  Вкажи батьківські папки, а не кожен проєкт. Кілька — через кому. ~ — твоя домашня тека." \
                             "  Приклад (дві папки):  ~/Developer, ~/Documents/Projects" ;;
  ru:projwhy) printf '%s\n' "  macup ищет там остатки сборки (node_modules, Pods, .build) и показывает, сколько они занимают." \
                             "  Сам ничего там не удаляет, разве что вы отдельно включите clean.stale_node_modules." \
                             "  Укажите родительские папки, а не каждый проект. Несколько — через запятую. ~ — ваша домашняя папка." \
                             "  Пример (две папки):  ~/Developer, ~/Documents/Projects" ;;
  *:projwhy)  printf '%s\n' "  macup looks there for build leftovers (node_modules, Pods, .build) and shows how much space they take." \
                             "  It deletes nothing there unless you separately turn on clean.stale_node_modules." \
                             "  Give the parent folders, not each project. Several: separate with commas. ~ is your home folder." \
                             "  Example (two folders):  ~/Developer, ~/Documents/Projects" ;;
  uk:keep)    echo "Enter — залишити" ;;
  ru:keep)    echo "Enter — оставить" ;;
  *:keep)     echo "Enter keeps" ;;
  uk:nodir)   echo "такої папки немає (збережу все одно, можна створити пізніше)" ;;
  ru:nodir)   echo "такой папки нет (сохраню всё равно, можно создать позже)" ;;
  *:nodir)    echo "no such folder (saved anyway; you can create it later)" ;;
  uk:home)    echo "сама домашня тека не підходить, macup її пропустить" ;;
  ru:home)    echo "сама домашняя папка не подходит, macup её пропустит" ;;
  *:home)     echo "your whole home folder is not allowed; macup will skip it" ;;
  uk:mas)     echo "Поставити mas, щоб оновлювати програми з App Store? [y/N]: " ;;
  ru:mas)     echo "Установить mas, чтобы обновлять приложения из App Store? [y/N]: " ;;
  *:mas)      echo "Install mas so App Store apps get updated too? [y/N]: " ;;
  uk:run)     echo "Запустити першу перевірку зараз? Вона нічого не змінює, а наприкінці дасть вибрати, що почистити. [Y/n]: " ;;
  ru:run)     echo "Запустить первую проверку сейчас? Она ничего не меняет, а в конце даст выбрать, что почистить. [Y/n]: " ;;
  *:run)      echo "Run a first check now? It changes nothing, then lets you pick what to clean. [Y/n]: " ;;
  uk:finish)  echo "Готово. Далі:" ;;
  ru:finish)  echo "Готово. Дальше:" ;;
  *:finish)   echo "Done. Next:" ;;
  uk:reload)  echo "відкрий нове вікно Terminal (або: source ~/.zshrc)" ;;
  ru:reload)  echo "откройте новое окно Terminal (или: source ~/.zshrc)" ;;
  *:reload)   echo "open a new Terminal window (or: source ~/.zshrc)" ;;
  uk:menu)    echo "меню" ;;
  ru:menu)    echo "меню" ;;
  *:menu)     echo "menu" ;;
  uk:check)   echo "перевірка, потім вибір, що почистити" ;;
  ru:check)   echo "проверка, потом выбор, что почистить" ;;
  *:check)    echo "check, then pick what to clean" ;;
  uk:help)    echo "усі команди" ;;
  ru:help)    echo "все команды" ;;
  *:help)     echo "all commands" ;;
  esac
}
tld(){ echo "$1" | sed "s|^$HOME|~|"; }
say(){ printf '%s==>%s %s\n' "$bold" "$reset" "$*"; }
die(){ printf '%s✗%s %s\n' "$red" "$reset" "$*" >&2; exit 1; }

# ---------------------------------------------------------------- install
mkdir -p "$BIN_DIR" || die "mkdir $BIN_DIR"
BIN_DIR=$(cd "$BIN_DIR" && pwd) || die "$BIN_DIR"; TARGET="$BIN_DIR/macup"
# next to the target, so installing is a rename: a macup that is running keeps its old file
TMP=$(mktemp "$BIN_DIR/.macup-install.XXXXXX") || die "$(text write) $BIN_DIR"; trap 'rm -f "$TMP" "$TMP.tag"' EXIT
HERE=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "$HERE/install.sh" ] && [ -f "$HERE/Package.swift" ]; then
  BUILT="$HERE/.build/release/macup"; [ "$HERE/.build/debug/macup" -nt "$BUILT" ] && BUILT="$HERE/.build/debug/macup"   # the last one built
  [ -f "$BUILT" ] || die "$(text nobuild)"
  say "$(text local): $(tld "$BUILT")"; cp "$BUILT" "$TMP" || die "$(text write) $TMP"
else
  # main names the latest version; the bootstrap comes from that version's tag (main before it is tagged) and must match its
  # SHA-256. Its first run, below, downloads the release binary (the last 2.9 script on a Mac older than macOS 13) over itself.
  say "$(text dl)"; curl -fsSL "$RAW/main/macup" -o "$TMP" || die "$(text dlfail): $RAW/main/macup"
  VER=$(sed -n 's/^MACUP_VERSION="\(.*\)"/\1/p' "$TMP" | head -1); REF="v$VER"
  WANT=$(curl -fsSL "$RAW/$REF/macup.sha256" 2>/dev/null | awk '{print $1; exit}')
  if [ -n "$VER" ] && [ -n "$WANT" ] && curl -fsSL "$RAW/$REF/macup" -o "$TMP.tag" 2>/dev/null; then mv "$TMP.tag" "$TMP"
  else rm -f "$TMP.tag"; WANT=$(curl -fsSL "$RAW/main/macup.sha256" 2>/dev/null | awk '{print $1; exit}'); fi
  [ -n "$WANT" ] && [ "$(shasum -a 256 "$TMP" 2>/dev/null | awk '{print $1}')" = "$WANT" ] || die "$(text sum)"
  /bin/bash -n "$TMP" || die "$(text broken)"
fi
chmod 755 "$TMP" && mv -f "$TMP" "$TARGET" || die "$(text write) $TARGET"
VER=$(MACUP_LANG="$lang" "$TARGET" version </dev/null | sed -n 's/^macup //p')
[ -n "$VER" ] || die "$(text unfinished)"
say "$(text inst): macup $VER → $(tld "$TARGET")"

for old in "$HOME/.npm-global/bin/macup" /usr/local/bin/macup /opt/homebrew/bin/macup; do
  case "$(readlink "$old" 2>/dev/null)" in */Cellar/macup/*) continue ;; esac   # Homebrew's own link: brew uninstall macup
  if [ "$old" != "$TARGET" ] && [ -f "$old" ] && grep -q '^# macup' "$old" 2>/dev/null && grep -q '^MACUP_VERSION=' "$old" 2>/dev/null; then
    rm -f "$old" && say "$(text old): $(tld "$old")"
  fi
done

NEED_RELOAD=""
case ":$PATH:" in *":$BIN_DIR:"*) ;; *)
  case "$BIN_DIR" in "$HOME"/*) PDIR="\$HOME${BIN_DIR#"$HOME"}" ;; *) PDIR="$BIN_DIR" ;; esac
  LINE="export PATH=\"$PDIR:\$PATH\""
  for rc in "$HOME/.zshrc" "$HOME/.bash_profile"; do
    if [ "$rc" = "$HOME/.zshrc" ] || [ -f "$rc" ]; then
      grep -qF "$LINE" "$rc" 2>/dev/null || { printf '\n# macup\n%s\n' "$LINE" >>"$rc"; say "$(text path): $(tld "$rc")"; }
    fi
  done
  NEED_RELOAD=1 ;;
esac

# ---------------------------------------------------------------- settings
MACUP_LANG="$lang" "$TARGET" config </dev/null >/dev/null 2>&1
"$TARGET" lang "$lang" >/dev/null 2>&1

if [ -z "$PROJECTS" ] && [ "$INTERACTIVE" = 1 ]; then
  FOUND=""
  for folder in "$HOME/Developer" "$HOME/Projects" "$HOME/Code" "$HOME/dev" "$HOME/src" "$HOME/repos" "$HOME/work"; do
    [ -d "$folder" ] && FOUND="$FOUND${FOUND:+, }$(tld "$folder")"
  done
  # what Enter keeps: the current setting on reinstall, else what we found, else the default list
  if [ "$HAD_CONF" = 1 ]; then KEEP=$(conf_get project_dirs); else KEEP=${FOUND:-$(conf_get project_dirs)}; fi
  printf '\n%s%s%s\n%s%s%s\n' "$bold" "$(text proj)" "$reset" "$dim" "$(text projwhy)" "$reset" >/dev/tty
  printf '%s  %s: %s%s\n' "$dim" "$(text keep)" "$KEEP" "$reset" >/dev/tty
  PROJECTS=$(ask "> ")
  if [ -z "$PROJECTS" ]; then [ "$HAD_CONF" = 0 ] && PROJECTS="$FOUND"
  else # point out typos, but keep what was typed
    echo "$PROJECTS" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | while IFS= read -r typed; do
      [ -z "$typed" ] && continue
      path=$(echo "$typed" | sed "s|^~|$HOME|"); path=${path%/}
      if [ "$path" = "$HOME" ] || [ "$path" = "" ]; then printf '  %s! %s: %s%s\n' "$dim" "$typed" "$(text home)" "$reset" >/dev/tty
      elif [ ! -d "$path" ]; then printf '  %s! %s: %s%s\n' "$dim" "$typed" "$(text nodir)" "$reset" >/dev/tty; fi
    done
  fi
fi
if [ -n "$PROJECTS" ]; then
  esc=$(printf '%s' "$PROJECTS" | sed 's/[|&]/\\&/g')
  sed -i '' -E "s|^[[:space:]]*project_dirs[[:space:]]*=.*|project_dirs = $esc|" "$CONF" 2>/dev/null
fi

if [ "$INTERACTIVE" = 1 ] && ! command -v mas >/dev/null 2>&1 && command -v brew >/dev/null 2>&1; then
  case "$(ask "$(text mas)")" in y|Y|т|Т|д|Д) brew install mas ;; esac
fi

# ---------------------------------------------------------------- done
echo
say "$(text finish)"
[ -n "$NEED_RELOAD" ] && echo "    $(text reload)"
printf '    %-14s %s# %s%s\n' "macup" "$dim" "$(text menu)" "$reset"
printf '    %-14s %s# %s%s\n' "macup check" "$dim" "$(text check)" "$reset"
printf '    %-14s %s# %s%s\n' "macup help" "$dim" "$(text help)" "$reset"

if [ "$INTERACTIVE" = 1 ]; then
  echo
  case "$(ask "$(text run)")" in n|N|н|Н) ;; *) echo; "$TARGET" check </dev/tty ;; esac
fi
exit 0

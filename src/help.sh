# ---------------------------------------------------------------- help texts
usage(){
  case "$MSG_LANG" in
  uk) cat <<EOF
${B}macup${N} $MACUP_VERSION — догляд за Маком однією командою

Просто набери  ${B}macup${N}  — з'явиться меню.

Команди
  macup check        Перевірити все, потім вибрати, що почистити (або нічого)
  macup all          Оновити інструменти + безпечна чистка + перевірки
  macup update       Лише оновлення (плюс перевірки)
  macup clean        Лише чистка (плюс перевірки)
  macup last         Останній звіт
  macup history      Тренди: вільне місце, swap, батарея, звільнене місце
  macup reports      Відкрити папку зі звітами у Finder
  macup tasks        Усі задачі з id і чи вони увімкнені
  macup config       Створити або відкрити файл налаштувань
  macup lang         Змінити мову (en, uk, ru)
  macup self-update  Встановити свіжу версію з GitHub (через Homebrew: brew upgrade macup)
  macup uninstall    Видалити macup і все, що він створив; --yes без питання
  macup help         Ця довідка

Опції (до будь-якої команди запуску)
  --level РІВЕНЬ     Що можуть видаляти clean/all: safe (типово), standard, aggressive
  --deep             Ще й найбільші папки, старі Downloads, артефакти збірки в проєктах
                     (macup --deep без команди — глибока перевірка)
  --skip a,b         Пропустити задачі на цей запуск, напр. --skip update.brew,clean.*
  --only a,b         Виконати лише ці задачі, напр. --only check.*
  --lang en|uk|ru    Мова для цього запуску
  --no-color         Без кольорів

Без команди (all, update, clean) чи твого вибору після перевірки нічого не змінюється.
Рівні: safe — відновиться само · standard — перекачається · aggressive — програми можуть вийти з акаунта.
Звіти: ~/Library/Logs/macup/
Налаштування: $(tildify "$CONF")
EOF
  ;;
  ru) cat <<EOF
${B}macup${N} $MACUP_VERSION — уход за Маком одной командой

Просто наберите  ${B}macup${N}  — появится меню.

Команды
  macup check        Проверить всё, потом выбрать, что почистить (или ничего)
  macup all          Обновить инструменты + безопасная очистка + проверки
  macup update       Только обновления (плюс проверки)
  macup clean        Только очистка (плюс проверки)
  macup last         Последний отчёт
  macup history      Тренды: свободное место, swap, батарея, освобождённое место
  macup reports      Открыть папку с отчётами в Finder
  macup tasks        Все задачи с id и включены ли они
  macup config       Создать или открыть файл настроек
  macup lang         Сменить язык (en, uk, ru)
  macup self-update  Установить свежую версию с GitHub (через Homebrew: brew upgrade macup)
  macup uninstall    Удалить macup и всё, что он создал; --yes без вопроса
  macup help         Эта справка

Опции (к любой команде запуска)
  --level УРОВЕНЬ    Что могут удалять clean/all: safe (по умолчанию), standard, aggressive
  --deep             Ещё и самые большие папки, старые Downloads, артефакты сборки в проектах
                     (macup --deep без команды — глубокая проверка)
  --skip a,b         Пропустить задачи в этом запуске, напр. --skip update.brew,clean.*
  --only a,b         Выполнить только эти задачи, напр. --only check.*
  --lang en|uk|ru    Язык для этого запуска
  --no-color         Без цветов

Без команды (all, update, clean) или вашего выбора после проверки ничего не меняется.
Уровни: safe — восстановится само · standard — скачается заново · aggressive — приложения могут выйти из аккаунта.
Отчёты: ~/Library/Logs/macup/
Настройки: $(tildify "$CONF")
EOF
  ;;
  *) cat <<EOF
${B}macup${N} $MACUP_VERSION — keep your Mac healthy from one command

Just type  ${B}macup${N}  to get a menu.

Commands
  macup check        Check everything, then pick what to clean (or nothing)
  macup all          Update tools + safe cleanup + checks
  macup update       Updates only (plus checks)
  macup clean        Cleanup only (plus checks)
  macup last         Show the latest report
  macup history      Trends across runs: free space, swap, battery, freed space
  macup reports      Open the reports folder in Finder
  macup tasks        List every task id and whether it's on
  macup config       Create or open your config file
  macup lang         Change language (en, uk, ru)
  macup self-update  Install the latest macup from GitHub (with Homebrew: brew upgrade macup)
  macup uninstall    Remove macup and everything it made; --yes skips the question
  macup help         This help

Options (combine with any run command)
  --level LEVEL      What clean/all may remove: safe (default), standard, aggressive
  --deep             Also scan the largest folders, Downloads and project build artifacts
                     (macup --deep on its own is a deep check)
  --skip a,b         Skip task ids for this run, e.g. --skip update.brew,clean.*
  --only a,b         Run only these task ids, e.g. --only check.*
  --lang en|uk|ru    Language for this run
  --no-color         Plain output

Nothing changes without a command (all, update, clean) or your pick after a check.
Levels: safe rebuilds itself · standard downloads again · aggressive may sign apps out.
Reports: ~/Library/Logs/macup/
Config: $(tildify "$CONF")
EOF
  ;;
  esac
}


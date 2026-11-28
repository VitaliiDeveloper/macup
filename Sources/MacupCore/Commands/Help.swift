/// `macup help` (2.9's help.sh). The texts are 2.9's, line for line; ArgumentsTests holds them as fixtures.
public enum Help {
    /// `usage`: the help in the run's language; `conf` is the config path as the user writes it (~/…).
    public static func text(lang: Lang, colors: Colors, conf: String) -> String {
        switch lang {
        case .uk:
            """
            \(colors.bold)macup\(colors.reset) \(Env.version) — догляд за Маком однією командою

            Просто набери  \(colors.bold)macup\(colors.reset)  — з'явиться меню.

            Команди
              macup check        Перевірити все, потім вибрати, що почистити (або нічого)
              macup all          Оновити інструменти + безпечна чистка + перевірки
              macup update       Лише оновлення (плюс перевірки)
              macup clean        Лише чистка (плюс перевірки)
              macup last         Останній звіт
              macup history      Тренди: вільне місце, swap, батарея, звільнене місце
              macup reports      Скільки звітів і їхній розмір; macup reports clean видаляє їх
              macup tasks        Усі задачі з id і чи вони увімкнені
              macup config       Створити або відкрити файл налаштувань
              macup lang         Змінити мову (en, uk, ru)
              macup self-update  Встановити свіжу версію з GitHub (через Homebrew: brew upgrade macup)
              macup schedule     Необов'язково: перевірка за розкладом зі сповіщенням (weekly, daily, off)
              macup uninstall    Видалити macup і все, що він створив; --yes без питання
              macup help         Ця довідка

            Опції (до будь-якої команди запуску)
              --level РІВЕНЬ     Що можуть видаляти clean/all: safe (типово), standard, aggressive
              --deep             Ще й найбільші папки, старі Downloads, артефакти збірки в проєктах
                                 (macup --deep без команди — глибока перевірка)
              --skip a,b         Пропустити задачі на цей запуск, напр. --skip update.brew,clean.*
              --only a,b         Виконати лише ці задачі, напр. --only check.*
              --enable a,b       Увімкнути вимкнені типово задачі на цей запуск, напр. --enable clean.trash
              --lang en|uk|ru    Мова для цього запуску
              --no-color         Без кольорів
              --quiet            Лише підсумок (усе інше — у звіті)
              --json             Увесь результат одним JSON-об'єктом, для скриптів та інших програм
                                 (також: macup tasks --json, macup history --json, macup reports --json)
              --pick КЛЮЧ,…      Почистити саме ці пункти з macup check --json (поле key), без питань

            Код виходу: 0 — готово · 3 — крок оновлення чи чистки не вдався · 2 — помилка в аргументах.
            Без команди (all, update, clean) чи твого вибору після перевірки нічого не змінюється.
            Рівні: safe — відновиться само · standard — перекачається · aggressive — програми можуть вийти з акаунта.
            Звіти: ~/Library/Logs/macup/
            Налаштування: \(conf)

            """
        case .ru:
            """
            \(colors.bold)macup\(colors.reset) \(Env.version) — уход за Маком одной командой

            Просто наберите  \(colors.bold)macup\(colors.reset)  — появится меню.

            Команды
              macup check        Проверить всё, потом выбрать, что почистить (или ничего)
              macup all          Обновить инструменты + безопасная очистка + проверки
              macup update       Только обновления (плюс проверки)
              macup clean        Только очистка (плюс проверки)
              macup last         Последний отчёт
              macup history      Тренды: свободное место, swap, батарея, освобождённое место
              macup reports      Сколько отчётов и их размер; macup reports clean удаляет их
              macup tasks        Все задачи с id и включены ли они
              macup config       Создать или открыть файл настроек
              macup lang         Сменить язык (en, uk, ru)
              macup self-update  Установить свежую версию с GitHub (через Homebrew: brew upgrade macup)
              macup schedule     Необязательно: проверка по расписанию с уведомлением (weekly, daily, off)
              macup uninstall    Удалить macup и всё, что он создал; --yes без вопроса
              macup help         Эта справка

            Опции (к любой команде запуска)
              --level УРОВЕНЬ    Что могут удалять clean/all: safe (по умолчанию), standard, aggressive
              --deep             Ещё и самые большие папки, старые Downloads, артефакты сборки в проектах
                                 (macup --deep без команды — глубокая проверка)
              --skip a,b         Пропустить задачи в этом запуске, напр. --skip update.brew,clean.*
              --only a,b         Выполнить только эти задачи, напр. --only check.*
              --enable a,b       Включить выключенные по умолчанию задачи на этот запуск, напр. --enable clean.trash
              --lang en|uk|ru    Язык для этого запуска
              --no-color         Без цветов
              --quiet            Только итог (всё остальное — в отчёте)
              --json             Весь результат одним JSON-объектом, для скриптов и других программ
                                 (также: macup tasks --json, macup history --json, macup reports --json)
              --pick КЛЮЧ,…      Почистить именно эти пункты из macup check --json (поле key), без вопросов

            Код выхода: 0 — готово · 3 — шаг обновления или очистки не удался · 2 — ошибка в аргументах.
            Без команды (all, update, clean) или вашего выбора после проверки ничего не меняется.
            Уровни: safe — восстановится само · standard — скачается заново · aggressive — приложения могут выйти из аккаунта.
            Отчёты: ~/Library/Logs/macup/
            Настройки: \(conf)

            """
        case .en:
            """
            \(colors.bold)macup\(colors.reset) \(Env.version) — keep your Mac healthy from one command

            Just type  \(colors.bold)macup\(colors.reset)  to get a menu.

            Commands
              macup check        Check everything, then pick what to clean (or nothing)
              macup all          Update tools + safe cleanup + checks
              macup update       Updates only (plus checks)
              macup clean        Cleanup only (plus checks)
              macup last         Show the latest report
              macup history      Trends across runs: free space, swap, battery, freed space
              macup reports      How many reports and their size; macup reports clean removes them
              macup tasks        List every task id and whether it's on
              macup config       Create or open your config file
              macup lang         Change language (en, uk, ru)
              macup self-update  Install the latest macup from GitHub (with Homebrew: brew upgrade macup)
              macup schedule     Optional: a scheduled check with a notification (weekly, daily, off)
              macup uninstall    Remove macup and everything it made; --yes skips the question
              macup help         This help

            Options (combine with any run command)
              --level LEVEL      What clean/all may remove: safe (default), standard, aggressive
              --deep             Also scan the largest folders, Downloads and project build artifacts
                                 (macup --deep on its own is a deep check)
              --skip a,b         Skip task ids for this run, e.g. --skip update.brew,clean.*
              --only a,b         Run only these task ids, e.g. --only check.*
              --enable a,b       Turn on opt-in tasks for this run, e.g. --enable clean.trash
              --lang en|uk|ru    Language for this run
              --no-color         Plain output
              --quiet            Only the summary (the rest is in the report)
              --json             The whole result as one JSON object, for scripts and other programs
                                 (also: macup tasks --json, macup history --json, macup reports --json)
              --pick KEY,…       Clean exactly these items of macup check --json (their key), without asking

            Exit status: 0 done · 3 an update or cleanup step failed · 2 bad arguments.
            Nothing changes without a command (all, update, clean) or your pick after a check.
            Levels: safe rebuilds itself · standard downloads again · aggressive may sign apps out.
            Reports: ~/Library/Logs/macup/
            Config: \(conf)

            """
        }
    }
}

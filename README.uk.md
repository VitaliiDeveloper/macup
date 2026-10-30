# macup

[English](README.md) · **Українська** · [Русский](README.ru.md)

Одна команда, щоб Мак розробника був оновлений, чистий і справний. Оновлює інструменти, прибирає кеші, які відновлюються самі, перевіряє стан системи й безпеку і показує, як усе змінюється з часом.

## Встановлення

```bash
curl -fsSL https://raw.githubusercontent.com/VitaliiDeveloper/macup/main/install.sh | bash
```

Установник спитає мову (English, Українська, Русский) і де лежать твої проєкти, запропонує поставити `mas` для оновлень з App Store, а потім — першу перевірку. Без sudo і без залежностей: достатньо bash, що є в macOS. Що він змінює:

- ставить `~/.local/bin/macup` і замінює старий macup у `/usr/local/bin`, `/opt/homebrew/bin` або `~/.npm-global/bin`
- створює `~/.config/macup/config` або лишає твій при перевстановленні
- додає `~/.local/bin` у `PATH` у `~/.zshrc` (і в `~/.bash_profile`, якщо він є), якщо його там ще немає

Без запитань:

```bash
curl -fsSL https://raw.githubusercontent.com/VitaliiDeveloper/macup/main/install.sh | bash -s -- --yes --lang uk --projects "~/Code"
```

Або через Homebrew:

```bash
brew install vitaliideveloper/macup/macup
```

Homebrew оновлює його через `brew upgrade` (і `macup update` теж), а `macup self-update` підкаже саме цю команду. Установника тут немає: мова береться з macOS, `macup lang` її змінює, `macup config` задає папки з проєктами.

## Використання

| Команда | Що робить |
|---|---|
| `macup` | Меню |
| `macup check` | Перевірити все, потім вибрати, що почистити (або нічого) |
| `macup all` | Оновлення + чистка до твого рівня + перевірки |
| `macup update` · `macup clean` | Лише оновлення · лише чистка (з перевірками) |
| `macup last` · `macup history` | Останній звіт · тренди між запусками |
| `macup tasks` · `macup config` | Що виконується і id задач · налаштування |
| `macup lang [en\|uk\|ru]` | Мова інтерфейсу |
| `macup self-update` · `macup uninstall` | Оновити або видалити macup |

Опції: `--level safe|standard|aggressive` (що можуть видаляти `clean`/`all`), `--deep` (найбільші папки, зокрема Application Support, старі Downloads, артефакти збірки в проєктах), `--skip id,…`, `--only id,…` (працюють групи: `clean.*`), `--lang xx`, `--no-color`.

Почни з `macup check`: він покаже, що можна почистити, з розмірами й рівнями, і дасть вибрати номери, рівень або нічого. Кожен запуск завершується підсумком і зберігає звіт у `~/Library/Logs/macup/`.

## Що робить

- **Оновлює:** Claude Code (CLI, плагіни, маркетплейси), глобальні npm-пакети, скіли агентів у `~/.agents`, Homebrew, програми App Store (через [`mas`](https://github.com/mas-cli/mas)), pipx, інструменти uv, rustup, Oh My Zsh, розширення GitHub CLI. Оновлення macOS лише показує, ніколи не встановлює.
- **Чистить, три рівні:**
  - 🟢 **safe** (типово; відновлюється само): Xcode DerivedData і прев'ю SwiftUI, старий DeviceSupport і логи пристроїв, кеші симуляторів, симулятори без runtime (і клони для паралельних тестів Xcode); кеші SwiftPM, CocoaPods, Carthage, Homebrew, npm, pnpm, Yarn, pip, uv і Go; кеші Electron-застосунків (VS Code, Cursor, Claude, Slack, Discord і будь-яких інших: macup знаходить їх за будовою папок, а не за списком назв); залишки Codex; старі логи.
  - 🟡 **standard** (перекачається при наступному використанні): Gradle, Android Studio, Maven; кеш збірки Docker і непотрібні образи; старі браузери Playwright/Puppeteer; старіші патч-версії в nvm, rbenv, pyenv, mise і asdf.
  - 🔴 **aggressive** (програми якийсь час повільніші або виходять з акаунта): кеш браузерів (Chrome, Arc, Edge, Brave, Firefox і будь-яких інших на Chromium чи Firefox; профілі, паролі й історію не чіпає ніколи).
  - **Лише якщо вибереш:** runtime-и симуляторів (з датою використання й кількістю симуляторів на них), стирання програм і даних симулятора, симулятори без використання 30 днів; інші великі папки в `~/Library/Caches`; старі `node_modules`; Кошик. Запущені симулятори пропускаються.
- **Вимірює, ніколи не видаляє:** кеші рендеру й прев'ю Final Cut Pro, Premiere/After Effects, DaVinci Resolve, Lightroom Classic і Camera Raw (з пунктом меню самої програми, щоб їх очистити), історію чатів Codex, AI-моделі, Android SDK і емулятори, Xcode Archives, симулятори.
- **Перевіряє:** час роботи, місце на диску і SMART, пам'ять і swap, CPU і перегрів, батарею; FileVault, брандмауер, SIP, Gatekeeper, автооновлення, Time Machine; сторонні й «осиротілі» служби автозапуску; MCP-сервери Claude Code; `brew doctor`; команди, які не запускаються, бо зник node чи Python або їхнє посилання веде на видалений файл, з командою для виправлення (macup її показує, але не запускає); Xcode і runtime-и симуляторів; Docker; розміри того, що macup ніколи не видаляє.

Інструменти, яких у тебе немає, пропускаються.

## Безпека

- **Без команди нічого не змінюється.** Оновлення й чистка — лише через `all`, `update`, `clean` або меню. Поза терміналом `macup` без команди лише показує довідку, тож у скриптах пиши `macup all`.
- **`clean` і `all` зупиняються на рівні `safe`**, якщо не вказати `--level` чи `clean_level`. Перевірка видаляє лише те, що ти вибереш; агресивні й ручні пункти перепитують.
- **Лише перелічені папки кешу, ніколи те, що лежить поруч.** Налаштування, історія чатів, сесії, virtualenv, ключі, `gradle.properties`, `settings.xml` Maven, профілі й паролі браузерів не чіпаються. Закріплені (`.nvmrc`, `.tool-versions`, …) і типові версії лишаються. Символьні посилання не відкриваються.
- **Відкриті програми пропускаються.** Закрий програму й запусти ще раз.
- **`macup check` нічого не ставить і не оновлює.** Але ходить у мережу: оновлює список пакетів Homebrew, питає npm, App Store, Apple і GitHub про доступні версії і на мить запускає MCP-сервери, щоб їх перевірити.
- **Оновлення — до найсвіжішої версії**, зокрема нові мажорні версії npm-пакетів. Якщо фіксуєш версії, вимкни задачу: `skip = update.npm`.
- **Без sudo.** macup його не викликає. Запит пароля під час оновлення програми з Homebrew іде від інсталятора самої програми.
- **`--deep` читає всю домашню теку.** macOS може попросити для Terminal доступ до Documents, Downloads чи даних інших програм; відмова лише скоротить перевірку.

## Налаштування

`macup config` відкриває `~/.config/macup/config`:

```ini
language = uk                          # en, uk, ru
skip = update.mas, check.docker        # задачі, які ніколи не запускати; працюють групи: clean.*
enable = clean.stale_node_modules      # задачі, що вмикаються вручну
clean_level = safe                     # що можуть видаляти clean/all: safe, standard, aggressive
project_dirs = ~/Developer, ~/Code     # для --deep і старих node_modules
device_support_days = 90
stale_project_days = 90
simulator_days = 30
keep_reports_days = 60
```

## Файли

| Шлях | Що там |
|---|---|
| `~/.local/bin/macup` | Скрипт |
| `~/.config/macup/config` | Налаштування |
| `~/Library/Logs/macup/` | Звіти (`.md`) і логи команд (`.log`) |
| `~/Library/Application Support/macup/history.csv` | Історія запусків для трендів |

`macup uninstall` показує все, що видалить, і питає один раз (`--yes` — без питання): скрипт і його старі копії, налаштування, історію, звіти, тимчасові файли перерваних запусків і рядок `PATH`, який установник додав у `~/.zshrc` і `~/.bash_profile`. Рядок лишається, якщо в тій самій папці є інші програми (у `~/.local/bin` часто лежать `claude`, `uv` та інші). Встановлений через Homebrew macup видаляється через `brew uninstall macup`.

## Ліцензія

[MIT](LICENSE)

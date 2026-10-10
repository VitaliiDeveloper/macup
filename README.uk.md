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

## Використання

| Команда | Що робить |
|---|---|
| `macup` | Меню |
| `macup check` | Перевірити все; нічого не ставить і не видаляє |
| `macup all` | Оновлення + безпечна чистка + перевірки |
| `macup update` · `macup clean` | Лише оновлення · лише чистка (з перевірками) |
| `macup last` · `macup history` | Останній звіт · тренди між запусками |
| `macup tasks` · `macup config` | Що виконується і id задач · налаштування |
| `macup lang [en\|uk\|ru]` | Мова інтерфейсу |
| `macup self-update` · `macup uninstall` | Оновити або видалити macup |

Опції: `--deep` (найбільші папки, старі Downloads, артефакти збірки в проєктах), `--skip id,…`, `--only id,…` (працюють групи: `clean.*`), `--lang xx`, `--no-color`.

Почни з `macup check`. Кожен запуск завершується підсумком і зберігає звіт у `~/Library/Logs/macup/`.

## Що робить

- **Оновлює:** Claude Code (CLI, плагіни, маркетплейси), глобальні npm-пакети, скіли агентів у `~/.agents`, Homebrew, програми App Store (через [`mas`](https://github.com/mas-cli/mas)), pipx, інструменти uv, rustup, Oh My Zsh, розширення GitHub CLI. Оновлення macOS лише показує, ніколи не встановлює.
- **Чистить за замовчуванням:** Xcode DerivedData і прев'ю SwiftUI (не при відкритому Xcode), DeviceSupport старші за 90 днів, старі логи пристроїв, недоступні симулятори, кеші симуляторів; кеші SwiftPM, CocoaPods, Carthage, Homebrew, npm, Yarn, pnpm, pip, uv і Go; логи програм і крешрепорти старші за 30 днів; кеш Quick Look.
- **Чистить, лише якщо ввімкнеш:** `clean.stale_node_modules` (проєкти без змін 90 днів) і `clean.trash`.
- **Перевіряє:** час роботи, місце на диску і SMART, пам'ять і swap, CPU і перегрів, батарею; FileVault, брандмауер, SIP, Gatekeeper, автооновлення, Time Machine; сторонні й «осиротілі» служби автозапуску; MCP-сервери Claude Code; `brew doctor`; Xcode і runtime-и симуляторів; Docker; розміри того, що macup ніколи не видаляє.

Інструменти, яких у тебе немає, пропускаються.

## Безпека

- **Без команди нічого не змінюється.** Оновлення й чистка — лише через `all`, `update`, `clean` або меню. Поза терміналом `macup` без команди лише показує довідку, тож у скриптах пиши `macup all`.
- **Чистка видаляє лише те, що відновлюється або перекачується само.** Xcode Archives, Кошик, Downloads і пристрої симуляторів лише вимірюються, ніколи не видаляються.
- **`macup check` нічого не ставить, не оновлює й не видаляє.** Але ходить у мережу: оновлює список пакетів Homebrew, питає npm, App Store, Apple і GitHub про доступні версії і на мить запускає MCP-сервери, щоб їх перевірити.
- **Оновлення — до найсвіжішої версії**, зокрема нові мажорні версії npm-пакетів. Якщо фіксуєш версії, вимкни задачу: `skip = update.npm`.
- **Без sudo.** macup його не викликає. Запит пароля під час оновлення програми з Homebrew іде від інсталятора самої програми.
- **`--deep` читає всю домашню теку.** macOS може попросити для Terminal доступ до Documents, Downloads чи даних інших програм; відмова лише скоротить перевірку.

## Налаштування

`macup config` відкриває `~/.config/macup/config`:

```ini
language = uk                          # en, uk, ru
skip = update.mas, check.docker        # задачі, які ніколи не запускати; працюють групи: clean.*
enable = clean.stale_node_modules      # задачі, що вмикаються вручну
project_dirs = ~/Developer, ~/Code     # для --deep і старих node_modules
device_support_days = 90
stale_project_days = 90
keep_reports_days = 60
```

## Файли

| Шлях | Що там |
|---|---|
| `~/.local/bin/macup` | Скрипт |
| `~/.config/macup/config` | Налаштування |
| `~/Library/Logs/macup/` | Звіти (`.md`) і логи команд (`.log`) |
| `~/Library/Application Support/macup/history.csv` | Історія запусків для трендів |

`macup uninstall` питає, перш ніж видалити скрипт, і ще раз — перш ніж видалити налаштування, історію і звіти. Рядок `PATH`, який установник міг додати в `~/.zshrc`, лишається: `~/.local/bin` використовують і інші інструменти.

## Ліцензія

[MIT](LICENSE)

# macup

[English](README.md) · [Українська](README.uk.md) · **Русский**

Одна команда, чтобы Мак разработчика был обновлён, чист и исправен. Обновляет инструменты, убирает кэши, которые восстанавливаются сами, проверяет состояние системы и безопасность и показывает, как всё меняется со временем.

## Установка

```bash
curl -fsSL https://raw.githubusercontent.com/VitaliiDeveloper/macup/main/install.sh | bash
```

Установщик спросит язык (English, Українська, Русский) и где лежат ваши проекты, предложит поставить `mas` для обновлений из App Store, а потом — первую проверку. Без sudo и без зависимостей: достаточно bash, который есть в macOS. Что он меняет:

- ставит `~/.local/bin/macup` и заменяет старый macup в `/usr/local/bin`, `/opt/homebrew/bin` или `~/.npm-global/bin`
- создаёт `~/.config/macup/config` или оставляет ваш при переустановке
- добавляет `~/.local/bin` в `PATH` в `~/.zshrc` (и в `~/.bash_profile`, если он есть), если его там ещё нет

Без вопросов:

```bash
curl -fsSL https://raw.githubusercontent.com/VitaliiDeveloper/macup/main/install.sh | bash -s -- --yes --lang ru --projects "~/Code"
```

## Использование

| Команда | Что делает |
|---|---|
| `macup` | Меню |
| `macup check` | Проверить всё, потом выбрать, что почистить (или ничего) |
| `macup all` | Обновления + очистка до вашего уровня + проверки |
| `macup update` · `macup clean` | Только обновления · только очистка (с проверками) |
| `macup last` · `macup history` | Последний отчёт · тренды между запусками |
| `macup tasks` · `macup config` | Что выполняется и id задач · настройки |
| `macup lang [en\|uk\|ru]` | Язык интерфейса |
| `macup self-update` · `macup uninstall` | Обновить или удалить macup |

Опции: `--level safe|standard|aggressive` (что могут удалять `clean`/`all`), `--deep` (самые большие папки, старые Downloads, артефакты сборки в проектах), `--skip id,…`, `--only id,…` (работают группы: `clean.*`), `--lang xx`, `--no-color`.

Начните с `macup check`: он покажет, что можно почистить, с размерами и уровнями, и даст выбрать номера, уровень или ничего. Каждый запуск заканчивается итогом и сохраняет отчёт в `~/Library/Logs/macup/`.

## Что делает

- **Обновляет:** Claude Code (CLI, плагины, маркетплейсы), глобальные npm-пакеты, скиллы агентов в `~/.agents`, Homebrew, приложения App Store (через [`mas`](https://github.com/mas-cli/mas)), pipx, инструменты uv, rustup, Oh My Zsh, расширения GitHub CLI. Обновления macOS только показывает, никогда не устанавливает.
- **Чистит, три уровня:**
  - 🟢 **safe** (по умолчанию; восстанавливается само): Xcode DerivedData и превью SwiftUI, старый DeviceSupport и логи устройств, кэши симуляторов; кэши SwiftPM, CocoaPods, Carthage, Homebrew, npm, pnpm, Yarn, pip, uv и Go; кэши VS Code, Cursor, Windsurf, Antigravity, Claude и Codex; остатки Codex; старые логи.
  - 🟡 **standard** (скачается заново при следующем использовании): Gradle, Android Studio, Maven; кэш сборки Docker и ненужные образы; старые браузеры Playwright/Puppeteer; более старые патч-версии в nvm, rbenv, pyenv, mise и asdf.
  - 🔴 **aggressive** (приложения какое-то время медленнее или выходят из аккаунта): кэш браузеров (Arc, Chrome, Firefox, Edge, Brave, Opera, Vivaldi).
  - **Только если выберете:** другие большие папки в `~/Library/Caches`, старые `node_modules`, Корзина.
- **Измеряет, никогда не удаляет:** кэши рендера и превью Final Cut Pro, Premiere/After Effects, DaVinci Resolve, Lightroom Classic и Camera Raw (с пунктом меню самого приложения, чтобы их очистить), историю чатов Codex, AI-модели, Android SDK и эмуляторы, Xcode Archives, симуляторы.
- **Проверяет:** время работы, место на диске и SMART, память и swap, CPU и перегрев, батарею; FileVault, брандмауэр, SIP, Gatekeeper, автообновления, Time Machine; сторонние и «осиротевшие» службы автозапуска; MCP-серверы Claude Code; `brew doctor`; Xcode и runtime симуляторов; Docker; размеры того, что macup никогда не удаляет.

Инструменты, которых у вас нет, пропускаются.

## Безопасность

- **Без команды ничего не меняется.** Обновления и очистка — только через `all`, `update`, `clean` или меню. Вне терминала `macup` без команды только показывает справку, поэтому в скриптах пишите `macup all`.
- **`clean` и `all` останавливаются на уровне `safe`**, если не указать `--level` или `clean_level`. Проверка удаляет только то, что вы выберете; агрессивные и ручные пункты переспрашивают.
- **Только перечисленные папки кэша, никогда то, что лежит рядом.** Настройки, история чатов, сессии, virtualenv, ключи, `gradle.properties`, `settings.xml` Maven, профили и пароли браузеров не трогаются. Закреплённые (`.nvmrc`, `.tool-versions`, …) и версии по умолчанию остаются. Символьные ссылки не открываются.
- **Открытые приложения пропускаются.** Закройте приложение и запустите ещё раз.
- **`macup check` ничего не ставит и не обновляет.** Но ходит в сеть: обновляет список пакетов Homebrew, спрашивает npm, App Store, Apple и GitHub о доступных версиях и на мгновение запускает MCP-серверы, чтобы их проверить.
- **Обновления — до самой свежей версии**, в том числе новые мажорные версии npm-пакетов. Если вы фиксируете версии, отключите задачу: `skip = update.npm`.
- **Без sudo.** macup его не вызывает. Запрос пароля при обновлении приложения из Homebrew исходит от установщика самого приложения.
- **`--deep` читает всю домашнюю папку.** macOS может запросить для Terminal доступ к Documents, Downloads или данным других приложений; отказ только сократит проверку.

## Настройки

`macup config` открывает `~/.config/macup/config`:

```ini
language = ru                          # en, uk, ru
skip = update.mas, check.docker        # задачи, которые никогда не запускать; работают группы: clean.*
enable = clean.stale_node_modules      # задачи, включаемые вручную
clean_level = safe                     # что могут удалять clean/all: safe, standard, aggressive
project_dirs = ~/Developer, ~/Code     # для --deep и старых node_modules
device_support_days = 90
stale_project_days = 90
keep_reports_days = 60
```

## Файлы

| Путь | Что там |
|---|---|
| `~/.local/bin/macup` | Скрипт |
| `~/.config/macup/config` | Настройки |
| `~/Library/Logs/macup/` | Отчёты (`.md`) и логи команд (`.log`) |
| `~/Library/Application Support/macup/history.csv` | История запусков для трендов |

`macup uninstall` спрашивает, прежде чем удалить скрипт, и ещё раз — прежде чем удалить настройки, историю и отчёты. Строка `PATH`, которую установщик мог добавить в `~/.zshrc`, остаётся: `~/.local/bin` используют и другие инструменты.

## Лицензия

[MIT](LICENSE)

# Скрипти сканування

Локальні сканери для **macOS** (`scan-mac.sh`) та **Windows** (`scan-win.ps1`). Оновлюють `data/drives.json` у GitHub через [Contents API](https://docs.github.com/en/rest/repos/contents).

## Файли в `scripts/`

| Файл | Платформа | Призначення |
|------|-----------|-------------|
| `scan-mac.sh` | macOS | Основний сканер (Terminal) |
| `scan-win.ps1` | Windows | Основний сканер (PowerShell 5.1+) |
| `build-mac-apps.sh` | macOS | Збирає `Twix Scan *.app` + іконку для Dock |
| `Twix Scan Drives.command` | macOS | Подвійний клік → меню вибору томів |
| `Twix Scan All Drives.command` | macOS | Подвійний клік → `--all` |
| `Twix Scan Drives.app` | macOS | Генерується локально (`git pull` → `build-mac-apps.sh`) |
| `Twix Scan All Drives.app` | macOS | Те саме, режим «усі томи» |

`.app` у `.gitignore` — після кожного `git pull` на Mac за потреби: `./scripts/build-mac-apps.sh`.

## Можливості

- **Інтерактивний вибір томів** — за замовчуванням після запуску
- **Часткове сканування** — у JSON оновлюються лише обрані диски; решта записів лишаються як були
- **Read-only** щодо підключених дисків — без створення/зміни/видалення файлів на томах
- **Детальні логи** — FS, used/free, прогрес по елементах кореня
- **`entries` у результаті:** спочатку папки, потім файли; у групі — за назвою (як у Finder / Explorer)

## Інтерактивний вибір томів

Після запуску скрипт показує нумерований список підключених несистемних томів (з ФС і зайнятим/загальним обсягом).

```
Підключені томи:
  [1] Black 5 — ExFAT, 3.1 ТБ / 3.6 ТБ
  [2] Gray 1 — APFS, 1.2 ТБ / 4.0 ТБ

Оберіть томи для сканування:
  • номери через кому: 1,3
  • діапазон: 1-3
  • Enter — усі томи
  • q — скасувати

Ваш вибір:
```

| Ввід | Результат |
|------|-----------|
| `1` | Лише том [1] |
| `1,3` | Томи 1 і 3 |
| `2-4` | Томи 2, 3 і 4 |
| *(Enter, порожній рядок)* | Усі показані томи |
| `q` | Вихід без сканування |

**Без меню** (усі томи, для скриптів/cron):

| macOS | Windows |
|-------|---------|
| `./scripts/scan-mac.sh --all` | `.\scripts\scan-win.ps1 -All` |

У **неінтерактивному** режимі (pipe, CI) без `--all`/`-All` скрипт завершиться з помилкою — потрібен явний прапорець.

Довідка macOS: `./scripts/scan-mac.sh --help`

## 1) Створення fine-grained PAT

1. [GitHub → Personal Access Tokens](https://github.com/settings/personal-access-tokens) → **Generate new token** (fine-grained)
2. **Token name:** `twix-drives-scanner`
3. **Resource owner:** `ViTwix`
4. **Repository access:** Only select repositories → `twix.production.drives`
5. **Permissions:** **Contents: Read and write**
6. Згенерувати і **скопіювати** токен (`github_pat_…`) — показується один раз

## 2) `GITHUB_TOKEN`

Порядок підхоплення:

1. Змінна середовища `GITHUB_TOKEN` у поточному shell (найвищий пріоритет)
2. Файл **`.env`** у корені репозиторію (поруч із `data/`, `scripts/`)
3. Помилка з підказкою

### Рекомендовано: `.env` у клоні

**macOS / Linux:**

```bash
cd /шлях/до/twix.production.drives
cp .env.example .env
# відредагуйте .env — один рядок без export:
# GITHUB_TOKEN=github_pat_...
```

**Windows:**

```powershell
cd C:\шлях\до\twix.production.drives
Copy-Item .env.example .env
# відредагуйте .env у Notepad:
# GITHUB_TOKEN=github_pat_...
```

Файл `.env` у `.gitignore` — **не комітити**.

### Альтернатива: змінна середовища

**macOS (zsh)** — `~/.zshrc`:

```bash
export GITHUB_TOKEN='github_pat_...'
```

```bash
source ~/.zshrc
```

**Windows** — User environment (постійно):

```powershell
[Environment]::SetEnvironmentVariable('GITHUB_TOKEN', 'github_pat_...', 'User')
```

Закрити й знову відкрити PowerShell.

### Перевірка

```bash
# macOS — OK якщо є env або .env
./scripts/scan-mac.sh --help
```

```powershell
# Windows
if ($env:GITHUB_TOKEN) { 'OK (env)' } elseif (Test-Path .env) { 'OK (.env file exists)' } else { 'MISSING' }
```

## 3) Перший запуск на macOS

1. [Homebrew](https://brew.sh) → `brew install jq`
2. Клон:

```bash
git clone https://github.com/ViTwix/twix.production.drives.git
cd twix.production.drives
```

3. `cp .env.example .env` → вставити токен
4. Запуск у Terminal:

```bash
chmod +x ./scripts/scan-mac.sh
./scripts/scan-mac.sh
```

**Ярлик у Finder / Dock:**

| Спосіб | Dock (ліворуч, поруч із програмами) | Подвійний клік |
|--------|--------------------------------------|----------------|
| **`Twix Scan Drives.app`** | Так | Так |
| `Twix Scan Drives.command` | Ні (macOS не приймає `.command` як програму) | Так |

Після клону або `git pull` зберіть `.app` один раз:

```bash
./scripts/build-mac-apps.sh
```

Іконка Dock/Finder береться з `AppIcons/Assets.xcassets/AppIcon.appiconset` (той самий набір, що для веб).

У `scripts/` з’являться:

- `Twix Scan Drives.app` — меню вибору томів
- `Twix Scan All Drives.app` — усі томи (`--all`)

**Dock:** перетягни `.app` на **ліву** частину Dock (поруч із Finder, **ліворуч** від риски `···`). На `.command` Dock часто показує «неможливо» — це нормально.

**Важливо:** не перенось `.app` з папки `scripts/` в інше місце — всередині закладений відносний шлях до репо. Можна зробити **alias** на Desktop, що вказує на `.app` у `scripts/`.

Альтернатива без Dock: подвійний клік `Twix Scan Drives.command` (після `chmod +x scripts/*.command`).

Перший запуск `.app`: ПКМ → **Відкрити** (Gatekeeper).

5. Після `HTTP 200/201` (опційно): `git pull origin main`

## 4) Перший запуск на Windows

1. [Git for Windows](https://git-scm.com/download/win)
2. Клон:

```powershell
git clone https://github.com/ViTwix/twix.production.drives.git
cd .\twix.production.drives
```

3. `Copy-Item .env.example .env` → вставити токен
4. У сесії PowerShell (за потреби):

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

5. Запуск:

```powershell
.\scripts\scan-win.ps1
```

6. Після успіху (опційно): `git pull origin main`

### Ярлик Windows (ярлик на робочому столі)

**Об'єкт:** `C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe`

**Аргументи** (меню вибору, вікно лишається відкритим):

```text
-NoExit -ExecutionPolicy Bypass -File "C:\шлях\до\twix.production.drives\scripts\scan-win.ps1"
```

**Усі томи:** додати `-All` в кінці.

**Робоча папка:** корінь клону (де `.env`).

Потрібні `.env` у корені репо або User env `GITHUB_TOKEN`.

## 5) Оновлення сканерів на іншій машині

Сканери — це файли з git, не окремий інсталятор. Щоб отримати нову версію (вибір томів, `.env`, виправлення):

```bash
cd /шлях/до/twix.production.drives
git pull origin main
./scripts/build-mac-apps.sh
```

```powershell
cd C:\шлях\до\twix.production.drives
git pull origin main
```

- **macOS:** після `pull` перезберіть `.app` (`build-mac-apps.sh`), якщо користуєтесь Dock
- **`.env` не в git** — після `pull` переконайтеся, що `.env` лишився на місці (або скопіюйте з іншої машини / створіть з `.env.example`)
- **Веб-UI на Pages** оновлюється сам після push у `main`; на Windows ПК для перегляду достатньо браузера — [twix-production-drives.pages.dev](https://twix-production-drives.pages.dev)
- Node.js на Windows **не потрібен** лише для сканування — тільки Git + PowerShell + `.env`

## 6) Що сканується

| Платформа | Які томи |
|-----------|----------|
| **macOS** | `/Volumes/*`, крім системного диска та `Macintosh HD*` |
| **Windows** | `Fixed` і `Removable` з літерою диска, крім `%SystemDrive%` (зазвичай `C:`) |

У **корені** кожного обраного тому:

- **Папки** — рекурсивний `sizeBytes`
- **Файли** — `sizeBytes`; `ext` (нижній регістр), якщо є розширення
- Пропуск: приховані (`.…` на macOS), `System Volume Information`, кошики тощо

## 7) Troubleshooting

| Проблема | Що робити |
|----------|-----------|
| `GITHUB_TOKEN` / Set GITHUB_TOKEN | Створіть `.env` або export; перезапустіть shell |
| `jq: command not found` (macOS) | `brew install jq` |
| `401` / `403` | Перевірте PAT, права Contents, термін дії |
| `409 Conflict` | Паралельний запис; скрипт робить один retry |
| `422` | Помилка тіла запиту (рідко) |
| `0 елементів` при зайнятому томі | Немає доступу до кореня — том пропущено навмисно |
| Старий `data/drives.json` локально | Нормально — `git pull origin main` |
| PUT failed | Скрипт друкує JSON у stdout для ручного збереження |
| Некоректні розміри (macOS) | Не задавайте `BLOCKSIZE` у shell — у скрипті `unset BLOCKSIZE` |
| `unbound variable` при виборі тома (macOS) | Оновіть скрипт: `git pull origin main` |
| `Unexpected token` / `Р“Р‘` у `scan-win.ps1` (Windows) | Стара кодування файла; `git pull origin main` (потрібен UTF-8 BOM). Запускайте через **Windows PowerShell**, не `cmd` |
| Іконка `.app` не оновилась у Dock | `./scripts/build-mac-apps.sh`, прибрати старий ярлик з Dock, перетягнути `.app` знову |
| `.app` не знаходить скрипт | Не переносити `.app` з `scripts/`; лише alias на Desktop |

## 8) Безпека

- Не логувати й не комітити `GITHUB_TOKEN`
- Сканери не змінюють файли на дисках
- Веб лише читає JSON; запис — лише через ці скрипти + PAT

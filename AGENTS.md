# AGENTS.md

Інструкції для AI-агентів кодування (Claude Code, Cursor тощо), які працюють із цим репозиторієм. Усі команди й параметри звірені з офіційною документацією станом на травень 2026.

---

## Проєкт: twix.production.drives

Особиста система інвентаризації накопичувачів. Відстежує 20–30 зовнішніх HDD/SSD одного весільного відеографа на трьох машинах (Mac Mini, MacBook, Windows PC). Сканери запускаються локально на кожній машині та публікують один JSON-файл у цей публічний GitHub-репозиторій. Статичний веб-інтерфейс на Cloudflare Pages читає цей JSON і надає пошук + перегляд.

**Репозиторій:** `https://github.com/ViTwix/twix.production.drives` (публічний)
**Власник:** ViTwix (Twix / Vitalii Povolotskyi) — соло-розробник
**Локальний шлях розробки:** `/Users/vitaliipovolotskyi/Documents/Drives Twix Production`
**Прод URL:** `*.pages.dev` (Cloudflare Pages, автодеплой із `main`)

## Чому публічний репозиторій

Користувач визначив, що чутливість низька — інвентар містить лише *назви* папок/файлів і *розміри*, без вмісту, без клієнтських даних, без облікових даних. Публічний репозиторій робить архітектуру максимально простою: веб читає `data/drives.json` через `raw.githubusercontent.com`, без проксі, без auth, без Workers. Неочевидний URL Pages виконує роль контролю доступу.

---

## Обов'язкові правила для агентів

- **Read-only для дисків завжди:** будь-який сканер або допоміжний скрипт має працювати тільки на читання щодо підключених томів. Заборонено створення, зміна, перейменування або видалення файлів на сканованих HDD/SSD.
- **Запис тільки у GitHub:** єдиний дозволений запис у рамках продуктового потоку — оновлення `data/drives.json` через GitHub Contents API.
- **Синхронізація документації:** після будь-яких змін коду агент **зобов'язаний** перевірити релевантні `README`/спеки (`README.md`, `DATA_SCHEMA.md`, `scripts/README.md`, цей `AGENTS.md`) і оновити їх до фактичного стану реалізації в тому ж наборі змін.

---

## Як це працює (потік даних)

```
┌───────────┐   ┌───────────┐   ┌──────┐
│ Mac Mini  │   │  MacBook  │   │  PC  │
└─────┬─────┘   └─────┬─────┘   └──┬───┘
      │ scan-mac.sh   │             │ scan-win.ps1
      │               │             │
      └───────────────┴─────────────┘
                      │
                      ▼  GitHub Contents API (PUT, з PAT)
              ┌───────────────────┐
              │   GitHub repo     │
              │ data/drives.json  │
              └─────────┬─────────┘
                        │ raw.githubusercontent.com (max-age=300)
                        ▼
              ┌───────────────────┐
              │ Cloudflare Pages  │
              │   React + Vite    │  ← користувач відкриває у браузері
              └───────────────────┘
```

Кожен запуск сканера показує **підключені несистемні диски** і дозволяє обрати, які сканувати (Enter — усі, `q` — скасувати, прапорець `--all`/`-All` без запиту). Після сканування він забирає поточний `drives.json`, виконує upsert записів обраних дисків за `name`, і робить PUT назад.

---

## Технологічний стек (звірений із докою)

### Сканери

| Платформа | Скрипт | Залежності |
|---|---|---|
| **macOS 14+** | `scripts/scan-mac.sh` | `bash`/`zsh`, `curl` (вбудовано), `jq` (`brew install jq`) |
| **Windows 10/11** | `scripts/scan-win.ps1` | PowerShell 5.1+ (вбудовано) |

### Веб (`web/`)

- **Node.js 20.19+ або 22.12+** (вимога актуальної версії Vite)
- **Vite + React** (JSX, без TypeScript) — мінімум файлів, швидкий HMR
- **Tailwind CSS v4** (стабільна, актуальна `4.3.x`)
  - Установлення: `npm install -D tailwindcss @tailwindcss/vite`
  - Плагін `tailwindcss()` у `vite.config.js`
  - CSS-first конфіг через `@theme { ... }` у `src/index.css`
  - **Єдиний імпорт у CSS:** `@import "tailwindcss";`
  - **Без `tailwind.config.js`** — конфіг тільки через CSS
  - **Без `postcss.config.js`** — плагін `@tailwindcss/vite` сам усе робить
- Без роутера, без бібліотеки стану — одна сторінка, `useState`/`useMemo` достатньо
- Шрифт: `Inter` через `@fontsource-variable/inter` (або системний стек — на розсуд агента)
- Іконки для Apple/Android/desktop: джерело `AppIcons/Assets.xcassets/AppIcon.appiconset`, синхронізація в `web/public` через `web/scripts/sync-app-icons.mjs` (`predev`/`prebuild`/`prepreview`)

### Хостинг

- **Cloudflare Pages**, автодеплой із `main`
- **Root directory:** `/web` (не `/`!)
- **Framework preset:** Vite
- **Build command:** `npm install && npm run build`
- **Build output directory:** `dist`

---

## Структура директорій (цільова)

```
twix.production.drives/
├── AGENTS.md              ← цей файл
├── README.md              ← огляд для людини
├── DATA_SCHEMA.md         ← специфікація JSON-схеми
├── .env.example           ← шаблон GITHUB_TOKEN (копіювати в .env, не комітити)
├── .gitignore
├── data/
│   └── drives.json        ← єдине джерело правди, записують сканери
├── scripts/
│   ├── scan-mac.sh
│   ├── scan-win.ps1
│   └── README.md          ← налаштування й використання сканерів
└── web/
    ├── index.html
    ├── package.json
    ├── scripts/
    │   └── sync-app-icons.mjs
    ├── vite.config.js
    ├── public/
    │   ├── favicon.ico
    │   ├── apple-touch-icon.png
    │   ├── icon-192.png
    │   ├── icon-512.png
    │   └── site.webmanifest
    └── src/
        ├── main.jsx
        ├── App.jsx
        ├── index.css      ← @import "tailwindcss"; + @theme
        ├── lib/
        │   ├── format.js  ← formatBytes, formatDate, pluralizeUk
        │   └── search.js  ← логіка пошуку
        └── components/    ← опційно; у поточній реалізації UI зібрано в App.jsx
```

Агент може згорнути `components/` в `App.jsx`, якщо так чистіше — користувач явно віддає перевагу **меншій кількості файлів** над жорсткою декомпозицією.

---

## Початкові задачі збірки (саме у цьому порядку)

### 1. Скелет репозиторію

- Створити `.gitignore`:
  ```
  node_modules/
  dist/
  .env
  .env.local
  .DS_Store
  Thumbs.db
  *.log
  ```
- Створити стартовий `data/drives.json`:
  ```json
  { "updatedAt": null, "drives": [] }
  ```

### 2. Згенерувати `web/`

```bash
npm create vite@latest web -- --template react
cd web
npm install
npm install -D tailwindcss @tailwindcss/vite
```

Прибрати дефолтний boilerplate (логотипи, демо-код, заглушковий `App.css` у тому стані, в якому його залишила Vite).

Налаштувати `web/vite.config.js`:
```js
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

export default defineConfig({
  plugins: [react(), tailwindcss()],
})
```

Налаштувати `web/src/index.css` (приклад мінімального налаштування — токени уточнить дизайн):
```css
@import "tailwindcss";

@theme {
  /* Семантичні токени */
  --color-bg: #0a0a0b;
  --color-surface: #131316;
  --color-surface-elevated: #1c1c21;
  --color-border: #26262d;
  --color-text: #e8e8ec;
  --color-text-muted: #8a8a94;
  --color-accent: #6366f1;
  --color-ok: #10b981;
  --color-warn: #f59e0b;
  --color-danger: #f43f5e;
}

@layer base {
  body {
    @apply bg-[var(--color-bg)] text-[var(--color-text)];
    font-family: 'Inter Variable', system-ui, sans-serif;
  }
}

@layer components {
  /* Повторювані патерни класів (3+ вживань) виносити сюди */
}
```

### 3. Зібрати веб-інтерфейс

Див. розділ [Специфікація Web UI](#специфікація-web-ui) нижче. Як мокдані для розробки використовувати приклад із `DATA_SCHEMA.md`.

### 4. Написати `scripts/scan-mac.sh`

Див. [Специфікація сканерів](#специфікація-сканерів).

### 5. Написати `scripts/scan-win.ps1`

### 6. Написати `scripts/README.md`

Має містити:
- Покрокову інструкцію створення fine-grained PAT (із посиланням `https://github.com/settings/personal-access-tokens`)
- Як виставити `GITHUB_TOKEN`: пріоритет env var → `.env` у корені репо → помилка; альтернатива через `~/.zshrc` / Windows User env
- Інтерактивний вибір томів (номери, діапазон, Enter = усі, `q` = скасувати) і прапорці `--all` / `-All`
- Як оновити сканери на іншій машині (`git pull`) і що веб на Pages оновлюється без локальної установки
- Розділ Troubleshooting: відсутній `jq`, прострочений PAT, 401/403/409/422 від API, `BLOCKSIZE` env var, перезапуск шела після зміни env var

### 7. Smoke-тест

Запустити `scan-mac.sh` на маленькому зовнішньому томі. Переконатися що:
- Інтерактивний вибір томів і `--all` для повного проходу працюють
- JSON формується коректно
- GitHub API повертає 200 або 201
- `data/drives.json` у репо оновився
- Веб через 5–10 секунд показує новий запис (cache-buster має змусити браузер забрати свіже)

---

## Схема даних (коротко)

Повна специфікація — в `DATA_SCHEMA.md`.

```json
{
  "updatedAt": "2026-05-15T14:30:00Z",
  "drives": [
    {
      "name": "Black 3",
      "scannedAt": "2026-05-15T14:30:00Z",
      "filesystem": "APFS",
      "totalBytes": 4000787030016,
      "freeBytes": 802345678912,
      "usedBytes": 3198441351104,
      "entries": [
        { "type": "folder", "name": "07.09.2025 Lviv", "sizeBytes": 245678912000 },
        { "type": "file",   "name": "wedding_final.mp4", "ext": "mp4", "sizeBytes": 12500000000 }
      ]
    }
  ]
}
```

**Ключові правила:**
- `name` — унікальний ключ. Сканер робить upsert за назвою. Ніколи не створювати дублікати.
- `ext` — нижній регістр, без початкової крапки (наприклад, `"mp4"`). Для файлів без розширення поле повністю пропускається.
- Усі розміри — **байти** як цілі числа.
- Усі часові мітки — ISO 8601 UTC.
- Назви дисків на кшталт `"Black 3"`, `"Gray 1"` зберігати точно як вводить користувач. **Не slugify, не нормалізувати.**

---

## Специфікація сканерів

### Спільна логіка (обидва скрипти)

1. **Перевірити `GITHUB_TOKEN`** — спочатку env var, інакше `.env` у корені репо; якщо немає — вийти з кодом 1 і повідомленням-інструкцією.
2. **Знайти всі зовнішні/несистемні томи** з їхніми label, виключивши системний диск.
3. **Інтерактивний вибір томів** (за замовчуванням): показати нумерований список; користувач вводить номери через кому або діапазон (`1-3`); Enter — усі томи; `q` — скасувати. Прапорець `--all` (macOS) / `-All` (Windows) пропускає вибір і сканує всі знайдені томи. У неінтерактивному режимі без прапорця — помилка з підказкою.
4. **Прохід обраних томів**: у межах одного запуску послідовно просканувати кожен обраний том.
5. **Назва диска**: брати label/назву тому як `name`.
6. **Назва машини не зберігається**: сканер не пише у JSON інформацію про пристрій.
7. **Просканувати корінь** кожного обраного тому:
   - Пропустити приховані / системні записи (списки нижче).
   - Для кожної **папки**: порахувати сумарний рекурсивний розмір у байтах, записати `{ type, name, sizeBytes }`.
   - Для кожного **файла**: записати `{ type, name, ext, sizeBytes }` (`ext` пропускати, якщо нема).
   - Прогрес: для томів із багатьма елементами у корені друкувати `[12/47] 07.09.2025 Lviv…` — `du -sk` на великих папках займає секунди.
8. **Зібрати інформацію про том**: тип файлової системи, total/free/used у байтах.
9. **GET** `data/drives.json` з GitHub. Якщо 404 — почати з порожнього об'єкта (без `sha` у наступному PUT).
10. **Upsert** запису диска за `name`. Виставити `scannedAt` у поточну UTC ISO 8601. Перед збереженням сортувати `entries` у порядку файлового менеджера: спершу папки, потім файли; в межах групи — за назвою. Опційно сортувати `drives` за `name` за зростанням.
11. **Оновити `updatedAt`** на кореневому об'єкті.
12. **PUT** новий вміст (base64) з попереднім `sha` (або без `sha`, якщо це перший раз). Commit message: `scan: full sweep at …` якщо обрано всі томи; інакше `scan: Black 3, Gray 1 at …`.
13. **У разі успіху** (200 або 201): надрукувати URL Cloudflare Pages.
14. **У разі помилки мережі / 5xx / 409**: надрукувати новий JSON у stdout (щоб користувач міг скопіювати), вийти з кодом 1.

### Що пропускати

**macOS:**
- Усе, що починається з `.` (`.DS_Store`, `.Spotlight-V100`, `.fseventsd`, `.Trashes`, `.TemporaryItems`, `.DocumentRevisions-V100`, `.apdisk` тощо)
- Також службові кореневі папки: `System Volume Information`, `$RECYCLE.BIN`, `$Recycle.Bin`, `RECYCLER`

**Windows:**
- `System Volume Information`
- `$RECYCLE.BIN`, `$Recycle.Bin`, `RECYCLER`
- Будь-що з атрибутом `Hidden` чи `System`

### macOS: команди й обхід пасток

**Визначення системного диска і перебір зовнішніх:**

```bash
# Отримати device node системного / тому
SYSTEM_DEV=$(diskutil info / | awk -F': *' '/Device Node/ {print $2; exit}')
# Наприклад "/dev/disk3s1s1"
SYSTEM_DISK="${SYSTEM_DEV%s*}"   # обріжемо до /dev/disk3

# Перебрати /Volumes/*, виключивши Macintosh HD і системний disk
for vol in /Volumes/*; do
  [[ ! -d "$vol" ]] && continue
  name=$(basename "$vol")
  # Виключити Macintosh HD і Macintosh HD - Data
  [[ "$name" == "Macintosh HD"* ]] && continue

  vol_dev=$(diskutil info "$vol" 2>/dev/null | awk -F': *' '/Device Node/ {print $2; exit}')
  [[ -z "$vol_dev" ]] && continue
  # Виключити томи на тому самому фізичному диску, що й системний
  [[ "$vol_dev" == "$SYSTEM_DISK"* ]] && continue

  # Це зовнішній том
  echo "$vol"
done
```

**Інформація про том:**

```bash
VOL="/Volumes/Black 3"

# Файлова система
FS=$(diskutil info "$VOL" | awk -F': *' '/File System Personality/ {print $2; exit}')
# Наприклад "APFS", "ExFAT", "MS-DOS FAT32", "Mac OS Extended"

# Total / used / free у байтах.
# ВАЖЛИВО: macOS df за замовчуванням використовує 512-байтові блоки,
# а змінна BLOCKSIZE може це переломати. Завжди -k → 1024-байтові блоки.
read -r TOTAL_KB USED_KB FREE_KB < <(df -k "$VOL" | awk 'NR==2 {print $2, $3, $4}')
TOTAL_BYTES=$((TOTAL_KB * 1024))
USED_BYTES=$((USED_KB * 1024))
FREE_BYTES=$((FREE_KB * 1024))
```

**Розмір папки / файла:**

```bash
# Розмір папки у байтах (du -sk → KB → ×1024)
folder_size_bytes() {
  local kb
  kb=$(du -sk "$1" 2>/dev/null | awk '{print $1}')
  echo $((kb * 1024))
}

# Розмір файла у байтах (BSD-style stat)
file_size_bytes() {
  stat -f%z "$1"
}
```

**Налаштування скрипта (на початку):**

```bash
#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=en_US.UTF-8
unset BLOCKSIZE   # запобігаємо викривленню du/df через env
```

### Windows: команди й обхід пасток

**Перелік зовнішніх томів** (виключаючи системний диск):

```powershell
Get-Volume |
  Where-Object {
    $_.DriveLetter -and
    ($_.DriveType -eq 'Fixed' -or $_.DriveType -eq 'Removable') -and
    ("$($_.DriveLetter):" -ne $env:SystemDrive)
  }
```

> Зовнішні USB HDD/SSD у Windows часто реєструються як `Fixed`, а не `Removable` (це залежить від firmware пристрою). Тому фільтр включає обидва типи, але виключає системний диск через `$env:SystemDrive` (зазвичай `C:`).

**Інформація про том:**

```powershell
$letter = 'E'   # вибраний користувачем
$vol = Get-Volume -DriveLetter $letter
$fs    = $vol.FileSystemType           # "NTFS", "exFAT", тощо
$total = [int64]$vol.Size
$free  = [int64]$vol.SizeRemaining
$used  = $total - $free
```

**Розмір папки / файла:**

```powershell
# Папка
$folderSize = (Get-ChildItem -LiteralPath $folder -Recurse -File -Force -ErrorAction SilentlyContinue |
               Measure-Object -Property Length -Sum).Sum
if ($null -eq $folderSize) { $folderSize = 0 }

# Файл
$fileSize = (Get-Item -LiteralPath $file).Length
```

**Налаштування скрипта (на початку):**

```powershell
#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$PSDefaultParameterValues['Out-File:Encoding'] = 'utf8'
```

### GitHub Contents API — точні запити

Базовий URL для нашого репо:
```
https://api.github.com/repos/ViTwix/twix.production.drives/contents/data/drives.json
```

**Хедери (для обох GET і PUT):**
```
Accept: application/vnd.github+json
Authorization: Bearer $GITHUB_TOKEN
X-GitHub-Api-Version: 2026-03-10
User-Agent: twix-drives-scanner
```

**GET — отримати поточний файл:**

```bash
curl -sS -L \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "X-GitHub-Api-Version: 2026-03-10" \
  -H "User-Agent: twix-drives-scanner" \
  "https://api.github.com/repos/ViTwix/twix.production.drives/contents/data/drives.json"
```

Відповідь **200**: JSON із полями `content` (base64), `sha`, `encoding` (`"base64"`).
Відповідь **404**: файл не існує → стартуємо з `{"updatedAt": null, "drives": []}`, без `sha` у PUT.

> **Примітка про великі файли:** для файлів >1 МБ GitHub може повернути `"content": ""` / `"encoding": "none"`. Для нашого файла (максимум ~5–10 МБ при 30 дисках × 500 entries це теоретичний верх) це малоймовірно, але якщо так трапиться — fallback: GET через `Accept: application/vnd.github.raw+json` віддає сам файл (без base64), а `sha` тягнемо другим GET без `raw` Accept. Поки файл маленький — перший спосіб достатній.

**PUT — створити або оновити:**

```bash
curl -sS -L -X PUT \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "X-GitHub-Api-Version: 2026-03-10" \
  -H "User-Agent: twix-drives-scanner" \
  -d "$BODY" \
  "https://api.github.com/repos/ViTwix/twix.production.drives/contents/data/drives.json"
```

Де `BODY` — JSON виду:

```json
{
  "message": "scan: Black 3 at 2026-05-15T14:30:00Z",
  "content": "<base64>",
  "sha": "<previous_sha>",
  "branch": "main"
}
```

- При **першому створенні** — поле `sha` пропустити повністю. GitHub повертає **201 Created**.
- При **оновленні** — `sha` обов'язковий. GitHub повертає **200 OK**.

Інші статус-коди для обробки: **401 Unauthorized** (токен невалідний), **403 Forbidden** (rate limit чи нема прав), **404** (репо/шлях не знайдено), **409 Conflict** (sha не збігається — хтось редагував паралельно), **422 Unprocessable Entity** (валідація — поганий base64 або відсутні обов'язкові поля). Сканер має ці помилки чітко відображати з тілом відповіді.

### Змінна середовища

- `GITHUB_TOKEN` — fine-grained PAT з правами `Contents: read/write` тільки на цей репо. Обов'язково. **Ніколи не логувати, не друкувати, не вставляти у commit message.** Порядок підхоплення: (1) змінна середовища, (2) `.env` у корені репо (`GITHUB_TOKEN=…`), (3) помилка з підказкою (див. `scripts/README.md`).

### Крайові випадки

- **Немає прав доступу до папки**: пропустити запис, надрукувати попередження у stderr, продовжити.
- **Назва файла з Unicode / лапками / пробілами / переносами**: зберігати як є. `jq` (macOS) і `ConvertTo-Json -Depth 10` (Windows) коректно екранують усі такі символи.
- **Тисячі елементів у корені**: показувати прогрес. На дисках з великим вмістом `du -sk` на одну папку може займати 5–30 секунд.
- **Порожній том**: валідно, `"entries": []`.
- **Перший PUT на цей шлях**: без `sha`, очікувати 201.
- **Паралельне сканування з двох машин**: останній PUT перемагає (буде 409 у другого — нехай сканер повторить GET → upsert → PUT один раз і вийде з помилкою, якщо знову 409). Локінг не додаємо — це prosumer tool.

---

## Специфікація Web UI

### Візуальний напрям

Чистий, сучасний, відчуття персонального інструмента. Орієнтир: Linear / Vercel dashboard / Raycast — **не** корпоративний SaaS. Темна тема за замовчуванням. Багато повітря. Делікатні бордери, без важких тіней. Анімації лише там, де покращують зрозумілість (200 ms ease-out).

### Завантаження даних

```js
// На монтуванні застосунку
const url = `https://raw.githubusercontent.com/ViTwix/twix.production.drives/main/data/drives.json?t=${Date.now()}`;
const res = await fetch(url);
if (!res.ok) throw new Error(`HTTP ${res.status}`);
const data = await res.json();
```

`raw.githubusercontent.com` віддає `Cache-Control: max-age=300` (5 хвилин). Cache-buster `?t=Date.now()` гарантує свіжий fetch після сканування.

Поки дані завантажуються — skeleton-картки. У разі помилки — error-стан із кнопкою "Спробувати ще раз".

### Макет

```
┌─────────────────────────────────────────────────────────┐
│  Twix Production Drives        Оновлено: 15.05.2026     │
│  ┌────────────────────────────────────────────┐         │
│  │ 🔍  Пошук за назвою диска, папки або файла…│         │
│  └────────────────────────────────────────────┘         │
│                                                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │ Black 3      │  │ Gray 1       │  │ Black 1      │  │
│  │ ▓▓▓▓▓▓▓░░ 80%│  │ ▓▓▓▓░░░░░ 40%│  │ ▓▓▓▓▓▓▓▓░ 90%│  │
│  │ 3.2 / 4.0 ТБ │  │ 1.6 / 4.0 ТБ │  │ 3.6 / 4.0 ТБ │  │
│  │ 47 папок,    │  │ 12 папок,    │  │ 23 папки,    │  │
│  │  3 файли     │  │  0 файлів    │  │  1 файл      │  │
│  └──────────────┘  └──────────────┘  └──────────────┘  │
└─────────────────────────────────────────────────────────┘
```

- **Верхня панель**: sticky-мінімалістична шапка без рамки, заголовок "Twix Production Drives", підзаголовок із форматованим `updatedAt`, нижче поле пошуку.
- **Список дисків**: один вертикальний список (по одному диску в ряд/блок), без багатоколонкової сітки.
- **Кожна картка**:
  - Назва диска (велика, font-medium), вирівняна ліворуч
  - Праворуч перед прогрес-баром: `Останнє сканування: {date}` (малий, приглушений)
  - Горизонтальний прогрес-бар використаного обсягу у %
    - <70%: зелений (`var(--color-ok)`)
    - 70–90%: бурштиновий (`var(--color-warn)`)
    - >90%: червоний (`var(--color-danger)`)
  - Використано / загалом у форматованих байтах
  - Лічильник з відмінюванням: "{n} папок, {m} файлів"
- Тексти у картках і деталях не мають накладатися: довгі рядки обрізати (`truncate`) і не допускати overflow за межі блоку.
- **Клік по диску** → розгортає деталі inline у тому ж елементі списку (accordion-поведінка, без popup/overlay). У деталях — повний список entries у порядку "папки зверху, файли нижче, у межах групи — за назвою", з іконкою типу (📁/📄); назва entry ліворуч, розмір у тому ж рядку праворуч.

### Пошук — з показом збігів прямо на картці

Одне поле вводу. Дебаунс на 15k елементах не потрібен. Логіка:

1. Перевести в нижній регістр, обрізати пробіли (`trim`). Стрипнути початкову крапку, якщо є (щоб `.mp4` і `mp4` працювали однаково).
2. Якщо запит порожній → показати всі диски, за замовчуванням сортувати за `name` за зростанням у natural-порядку (числа в назвах як числа, case-insensitive; поведінка близька до macOS/Windows). **Не** показувати блок збігів.
3. Інакше включати диск, якщо **будь-що** з цього збігається:
   - `name` диска містить запит
   - `name` будь-якого entry містить запит
   - `ext` будь-якого файла дорівнює запиту
4. **На кожній картці у відфільтрованому стані** під лічильником додати блок:
   ```
   Збіги:
     📁 07.09.2025 Lviv         245 ГБ
     📁 12.10.2024 Lviv City    198 ГБ
     📄 Lviv_wedding.mp4         12 ГБ
   ```
  - Показувати всі матчі, відсортовані за `sizeBytes` desc (без згортання `+ ще N`).
5. У детальному перегляді диска, якщо пошук активний — матчі підсвічувати й піднімати у топ списку.

Для 20–30 дисків × ~500 entries = ~15k елементів — звичайного `Array.filter` з `useMemo` більш ніж достатньо. **Не додавати Fuse.js чи інші бібліотеки пошуку.**

### UI-рядки (українською)

| Ключ | Текст |
|---|---|
| Title | `Twix Production Drives` |
| Updated label | `Оновлено: {date}` |
| Search placeholder | `Пошук за назвою диска, папки або файла…` |
| Usage line | `{used} / {total}` |
| Counts | `{n} папок, {m} файлів` (з українським відмінюванням) |
| Last scan | `Останнє сканування: {date}` |
| Matches header | `Збіги:` |
| Empty (no drives) | `Ще немає сканованих дисків. Запустіть скрипт у /scripts/` |
| Empty (no matches) | `Нічого не знайдено за запитом «{q}»` |
| Error | `Не вдалося завантажити дані` + кнопка `Спробувати ще раз` |
| Sort indicator | *не використовується в поточному UI* |

### Допоміжні форматери (`src/lib/format.js`)

```js
// 1.23 ТБ / 456 ГБ / 12.3 МБ / 543 КБ / 27 Б
// Українські абревіатури (ТБ/ГБ/МБ/КБ/Б), база 1024
// 1 знак після коми для значень <10 у поточній одиниці
// 0 знаків для значень ≥10
export function formatBytes(bytes) { /* … */ }

// "15.05.2026, 14:30" — локаль uk-UA, 24h
export function formatDate(iso) {
  return new Intl.DateTimeFormat('uk-UA', {
    year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', hour12: false,
  }).format(new Date(iso));
}

// Українське відмінювання за CLDR-правилами:
// one  (1, 21, 31…)         → forms[0] "файл"
// few  (2-4, 22-24…)        → forms[1] "файли"
// many (0, 5-20, 25-30, …)  → forms[2] "файлів"
// Винятки 11-14 автоматично потрапляють у "many" (11 файлів)
export function pluralizeUk(n, forms) { /* forms: [one, few, many] */ }
```

### Продуктивність

- Мемоізувати результати фільтра й сортувань через `useMemo`
- Віртуалізація не потрібна
- Prefetch детальних переглядів не потрібен — дані вже завантажені

### Сортування дисків у UI

- Постійно: **за назвою** (natural sort, як у desktop-файлових менеджерах).
- Ручного перемикача сортування в UI немає.

---

## Код-стайл і конвенції

- **JavaScript, не TypeScript**. ES modules. Сучасний синтаксис (arrow functions, destructuring, optional chaining).
- **Відступи**: 2 пробіли. Без табів.
- **Лапки**: одинарні в JS, подвійні в JSX-атрибутах.
- **Компоненти**: PascalCase. Ім'я файла відповідає імені компонента. Default export для компонентів.
- **Утилітні файли**: camelCase імена функцій, named exports.
- **Tailwind v4**:
  - Конфіг теми (кольори, типографіка) — у `src/index.css` під `@theme`
  - Повторювані патерни (3+ рази) → `@layer components { .card-surface { … } }`
  - Без inline `style={{}}`, окрім runtime-значень (ширина прогрес-бару)
  - Семантичні назви кольорів через CSS custom properties у `@theme`
  - **Не створювати `tailwind.config.js`** — конфіг тільки через CSS
- **Bash**: на початку `set -euo pipefail`, `LC_ALL=en_US.UTF-8`, `unset BLOCKSIZE`. Усі змінні — у лапки. Для bash-специфічних місць — `[[ ]]` замість `[ ]`.
- **PowerShell**: `#Requires -Version 5.1`, `Set-StrictMode -Version Latest`, `$ErrorActionPreference = 'Stop'`. Comment-based help блок на початку. Для кастомних функцій — approved verbs.
- **Коментарі**: українською, лаконічні. Код — самодокументований.
- **Локалізація текстів**: UI-рядки, CLI-повідомлення, повідомлення помилок, документація — українською. Імена змінних, функцій, файлів, commit messages — англійською.
- **Без `console.log` у продакшн-вебкоді**.
- **Commit messages**: чіткі, англійською. Без жорсткого формату.
- **Безпека**: ніколи не логувати, не друкувати й не комітити значення `GITHUB_TOKEN`.
- **Вебзастосунок ніколи не пише в GitHub.** Read-only. Запис роблять лише сканери.
- **Сканери ніколи не пишуть на сканований диск.** Тільки читання metadata/розмірів.

---

## GitHub PAT — ручне налаштування (один раз, робить користувач)

1. Відкрити `https://github.com/settings/personal-access-tokens`
2. **Generate new token** (Fine-grained tokens)
3. **Token name:** `twix-drives-scanner`
4. **Expiration:** до 1 року (366 днів — максимум для fine-grained, постав нагадування на ротацію)
5. **Resource owner:** `ViTwix`
6. **Repository access:** Only select repositories → `twix.production.drives`
7. **Repository permissions:**
   - **Contents: Read and write**
   - Metadata: Read-only (додасться автоматично)
8. **Generate token** і скопіювати значення (`github_pat_…`) — GitHub показує його лише один раз.
9. Задати токен на **кожній** машині, де запускаються сканери (один із варіантів):
   - **Рекомендовано:** `.env` у корені клону (`cp .env.example .env`, рядок `GITHUB_TOKEN=github_pat_…`, без `export`). Не комітити.
   - **macOS (zsh):** `export GITHUB_TOKEN='github_pat_…'` у `~/.zshrc`, потім `source ~/.zshrc`.
   - **Windows:** `[Environment]::SetEnvironmentVariable('GITHUB_TOKEN', 'github_pat_…', 'User')`, перезапустити PowerShell.
   - Пріоритет під час запуску сканера: env var → `.env` → помилка.

---

## Cloudflare Pages — ручне налаштування (один раз, робить користувач)

1. Запушити перший коміт у `main`.
2. У Cloudflare Dashboard: **Workers & Pages → Create → Pages → Connect to Git**.
3. Вибрати репозиторій `ViTwix/twix.production.drives`.
4. Налаштування збірки:
   - **Production branch:** `main`
   - **Framework preset:** **Vite**
   - **Build command:** `npm install && npm run build`
   - **Build output directory:** `dist`
   - **Root directory (advanced) → Path:** `/web` ← **критично; без цього CF Pages шукатиме `package.json` у корені й валитиметься**
5. **Save and Deploy**.
6. Отримати URL виду `https://twix-production-drives.pages.dev`.

Опційно — у **Settings → Build → Build watch paths** додати `web/*` і `data/drives.json`, щоб уникати зайвих rebuild при змінах у `scripts/` чи `*.md`.

---

## Чим цей проєкт НЕ є

- ❌ Не backup-інструмент (без синхронізації файлів, без вмісту).
- ❌ Не real-time (лише snapshot, ручний запуск сканування).
- ❌ Не multi-user (без auth, без конкурентного редагування).
- ❌ Не трекає вміст файлів або хеші — тільки назви й розміри.
- ❌ Не рекурсивний перегляд структури — лише рівень 1.
- ❌ Не історичний — тільки поточний стан (перемагає останній запис).

---

## Швидкий чекліст валідації (для агента після збірки)

- [ ] `data/drives.json` існує та має валідну структуру `{ updatedAt, drives[] }`
- [ ] `web/package.json` містить `tailwindcss` ≥4.0 і `@tailwindcss/vite` ≥4.0
- [ ] `web/vite.config.js` підключає плагін `tailwindcss()`
- [ ] `web/src/index.css` починається з `@import "tailwindcss";`
- [ ] **Немає** `web/tailwind.config.js` і `web/postcss.config.js`
- [ ] `web/` збирається без помилок: `cd web && npm install && npm run build`
- [ ] У `web/dist/` є `index.html` і asset-файли
- [ ] Локальний preview (`npm run preview`) коректно завантажує `drives.json` і рендерить картки
- [ ] Пошук фільтрує картки за назвою диска, папки, файла й розширенням
- [ ] При активному пошуку на картках показуються блоки "Збіги:"
- [ ] `scan-mac.sh` на macOS: показує зовнішні томи (без системного/`Macintosh HD*`), інтерактивний вибір і `--all` працюють; PUT повертає 200/201
- [ ] `scan-win.ps1` на Windows 10/11: список томів без диска `C:`, інтерактивний вибір і `-All` працюють аналогічно
- [ ] Після сканування веб через cache-buster показує нові дані без жорсткого refresh
- [ ] `scripts/README.md` покриває PAT, env vars, troubleshooting
- [ ] `.gitignore` виключає `node_modules`, `dist`, `.env`, OS-сміття
- [ ] Жодного `console.log` у `web/src/`
- [ ] Жодного посилання на `GITHUB_TOKEN` у логах / `console.log` / commit message

---

## Довідка: реальні назви дисків (приклади)

Диски позначаються шаблонами на кшталт:
- `Black 1`, `Black 2`, `Black 3`
- `Gray 1`, `Gray 2`, `Gray 3`

Зберігати назви **точно** як вводить користувач — включно з регістром і пробілом. Без slugify. Без нормалізації.

Приклад формату назви папки у користувача: `07.09.2025 Lviv` — дата (`DD.MM.YYYY`) + пробіл + локація/подія. UI трактує як plain text, без парсингу.

---

## Що поза скоупом (не реалізовувати без окремого запиту)

- Аутентифікація користувачів
- Кілька snapshot-ів / часові ряди
- Хеші файлів / дедуплікація
- Сканування на боці хмари (сканер за дизайном локальний)
- Мобільні застосунки
- Email-сповіщення
- Запис у GitHub із браузера
- TypeScript
- SSR / SSG
- Кастомний домен (поки що `.pages.dev`)

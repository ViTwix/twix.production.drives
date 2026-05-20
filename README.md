# twix.production.drives

Особистий інвентар накопичувачів для обліку зовнішніх HDD/SSD на кількох машинах (Mac Mini, MacBook, Windows PC).

Локальні сканери знімають знімок **кореня** кожного обраного диска й публікують один JSON у GitHub. Статичний веб на Cloudflare Pages читає цей JSON і дає пошук по всіх дисках — наприклад: «де папка `07.09.2025 Lviv`?».

**Продакшн-веб:** [https://twix-production-drives.pages.dev](https://twix-production-drives.pages.dev)  
**Репозиторій:** [https://github.com/ViTwix/twix.production.drives](https://github.com/ViTwix/twix.production.drives)

## Як це працює

```
локальна машина (Mac / PC) ──┐
                             ├──► data/drives.json (GitHub) ──► Cloudflare Pages (перегляд)
локальна машина (Mac / PC) ──┘
```

| Частина | Що робить |
|--------|-----------|
| **Сканери** (`scripts/`) | Показують підключені томи → ви обираєте які сканувати → read-only обхід кореня → `PUT` у GitHub |
| **Дані** (`data/drives.json`) | Єдине джерело правди; один запис на диск (`name` — унікальний ключ) |
| **Веб** (`web/`) | Read-only UI; дані з `raw.githubusercontent.com`; кнопка **«Оновити дані»** після скану |

Нескановані в цьому запуску диски в JSON **не змінюються** — оновлюються лише обрані (upsert за `name`).

## Структура проєкту

```
.
├── .env.example         ← шаблон для GITHUB_TOKEN (скопіювати в .env)
├── AGENTS.md            ← повна специфікація для AI-агентів
├── DATA_SCHEMA.md       ← JSON-схема
├── data/drives.json     ← інвентар (у git; сканери пишуть через API)
├── scripts/
│   ├── scan-mac.sh      ← macOS
│   ├── scan-win.ps1     ← Windows
│   └── README.md        ← детальна інструкція сканерів
└── web/                 ← Vite + React + Tailwind v4
```

## Стек

- **Сканери:** bash + `jq` + `curl` (macOS); PowerShell 5.1+ (Windows)
- **Веб:** Node.js 20.19+, Vite, React 19, Tailwind CSS v4
- **Хостинг UI:** Cloudflare Pages (автодеплой з `main`, root `/web`)
- **Дані:** GitHub Contents API → `data/drives.json`

## Швидкий старт

### Веб-перегляд (без встановлення)

Відкрийте [twix-production-drives.pages.dev](https://twix-production-drives.pages.dev). Після сканування на будь-якій машині натисніть **«Оновити дані»** (або оновіть сторінку).

### Веб (локальна розробка)

```bash
cd web
npm install
npm run dev
```

→ `http://localhost:5173`

### Сканування дисків

Потрібен fine-grained PAT з **Contents: read/write** на цей репо — див. [`scripts/README.md`](scripts/README.md).

**Токен** (пріоритет зверху вниз):

1. Змінна `GITHUB_TOKEN` у shell (якщо вже є)
2. Файл `.env` у корені клону: `GITHUB_TOKEN=github_pat_…`
3. Інакше — помилка з підказкою

**macOS:**

```bash
cp .env.example .env   # один раз, вставити токен
./scripts/scan-mac.sh
```

**Windows (PowerShell):**

```powershell
Copy-Item .env.example .env   # один раз, вставити токен
.\scripts\scan-win.ps1
```

#### Інтерактивний вибір томів

Після запуску з’являється нумерований список підключених томів:

| Ввід | Дія |
|------|-----|
| `1` або `1,3` | Сканувати вказані номери |
| `1-3` | Діапазон |
| **Enter** (порожньо) | Усі підключені томи |
| `q` | Скасувати |

Без меню (усі томи одразу): `./scripts/scan-mac.sh --all` або `.\scripts\scan-win.ps1 -All`

Повна інструкція, PAT, troubleshooting — у [`scripts/README.md`](scripts/README.md).

## Оновлення на іншій машині

### Веб-застосунок (перегляд у браузері)

**Нічого встановлювати не потрібно.** UI деплоїться з GitHub на Cloudflare Pages автоматично після push у `main`.

1. Відкрийте [https://twix-production-drives.pages.dev](https://twix-production-drives.pages.dev)
2. Після оновлення коду в репо — жорстке оновлення сторінки (Ctrl+F5) або кнопка **«Оновити дані»**

Якщо бачите стару версію UI довго — зачекайте 1–2 хв після деплою Cloudflare або очистіть кеш браузера.

### Сканери (macOS / Windows)

На кожній машині, де запускаєте сканування, потрібен **актуальний клон репозиторію** зі скриптами.

**Якщо репо вже клоновано** (типовий випадок на другому ПК):

```powershell
cd C:\шлях\до\twix.production.drives
git pull origin main
```

```bash
cd ~/шлях/до/twix.production.drives
git pull origin main
```

Переконайтеся, що є `.env` з `GITHUB_TOKEN` (скопіюйте з іншої машини безпечним способом або створіть з `.env.example`). Токен у git не комітиться.

**Якщо на Windows ПК ще немає клону:**

```powershell
git clone https://github.com/ViTwix/twix.production.drives.git
cd .\twix.production.drives
Copy-Item .env.example .env
# відредагуйте .env — вставте GITHUB_TOKEN
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\scripts\scan-win.ps1
```

Деталі першого налаштування Windows — у [`scripts/README.md`](scripts/README.md).

### Локальна розробка вебу (`web/`)

Тільки якщо збираєте UI локально:

```bash
cd web
git pull origin main
npm install
npm run dev
```

## Після сканування

- Сканер пише **напряму в GitHub**; локальний `data/drives.json` у клоні сам не змінюється.
- Щоб підтягнути JSON у клон: `git pull origin main`
- У браузері — **«Оновити дані»** на Pages (cache-buster обходить 5-хв кеш raw.githubusercontent.com)

## Обмеження за дизайном

- Один запуск = snapshot обраних дисків; історії немає
- Лише корінь диска (папки + файли верхнього рівня, рекурсивний розмір папок)
- Ручний запуск; публічний репо + неочевидний URL Pages

## Безпека (read-only для дисків)

- Сканери **не змінюють** файли на HDD/SSD — лише читають метадані та розміри
- Веб **не пише** в GitHub
- Єдиний запис у системі — `PUT data/drives.json` через PAT (ніколи не комітити токен)

## Ліцензія

Особистий проєкт, без ліцензії.

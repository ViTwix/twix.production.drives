# twix.production.drives

Особистий інвентар накопичувачів для обліку зовнішніх HDD/SSD на кількох машинах.

Локальні сканери (один для macOS, один для Windows) знімають знімок кореня кожного диска в один JSON-файл у цьому репозиторії. Статичний веб-інтерфейс на Cloudflare Pages читає цей JSON і дозволяє шукати одразу по всіх дисках — «де папка `07.09.2025 Lviv`?» → відповідь знайдена.

## Як це працює

```
локальна машина (Mac / PC) ──┐
                             ├──► data/drives.json ──► Cloudflare Pages (read-only viewer)
локальна машина (Mac / PC) ──┘     (цей репозиторій)
```

- **Сканери** (`scripts/`): запускаються вручну, коли підключається диск. Вони обходять корінь, обчислюють розміри папок і надсилають дані в цей репозиторій через GitHub Contents API.
- **Дані** (`data/drives.json`): єдине джерело правди. Один запис на диск, ключ — назва диска (наприклад, `"Black 3"`).
- **Веб** (`web/`): Vite + React + Tailwind v4. Завантажує `data/drives.json` напряму з `raw.githubusercontent.com`. Без бекенду.

## Структура проєкту

```
.
├── AGENTS.md            ← повна специфікація для AI-агентів кодування
├── DATA_SCHEMA.md       ← довідник JSON-схеми
├── data/drives.json     ← дані інвентарю
├── scripts/             ← scan-mac.sh, scan-win.ps1, README.md
└── web/                 ← UI на Vite + React + Tailwind v4
```

## Стек

- **Сканери:** bash + `jq` + `curl` (macOS); PowerShell 5.1+ (Windows)
- **Веб:** Node.js 20.19+, Vite, React 19, Tailwind CSS v4
- **Хостинг:** Cloudflare Pages (`*.pages.dev`)
- **Сховище даних:** GitHub Contents API → `data/drives.json` у цьому репо

## Швидкий старт

### Веб (локальна розробка)

```bash
cd web
npm install
npm run dev
```

Сторінка буде доступна на `http://localhost:5173`.

### Сканування диска

Потрібен fine-grained Personal Access Token із правами `Contents: read/write` на цей репозиторій (див. `scripts/README.md`).

**macOS:**
```bash
export GITHUB_TOKEN='github_pat_…'   # один раз, додати в ~/.zshrc
./scripts/scan-mac.sh
```

**Windows:**
```powershell
[Environment]::SetEnvironmentVariable('GITHUB_TOKEN', 'github_pat_…', 'User')  # один раз
.\scripts\scan-win.ps1
```

Деталі — у `scripts/README.md`.

## Обмеження за дизайном

- Одне сканування = поточний стан. Історія не зберігається.
- Лише інвентар кореневого рівня (кореневі папки + кореневі файли). Без занурення в структуру, тільки підсумкові розміри.
- Запуск сканування лише вручну.
- Публічний репозиторій, неочевидна веб-адреса — для персонального використання.

## Ліцензія

Особистий проєкт, без ліцензії.

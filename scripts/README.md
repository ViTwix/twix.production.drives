# Скрипти сканування

Ця папка містить локальні сканери:

- `scan-mac.sh` для macOS
- `scan-win.ps1` для Windows

Обидва скрипти оновлюють `data/drives.json` у GitHub через Contents API.
Один запуск сканера = сканування **всіх підключених несистемних дисків** на поточній машині.
Порядок `entries` у результаті: спочатку папки, потім файли; у межах кожної групи — за назвою (як у файлових менеджерах macOS/Windows).
Під час роботи скрипти друкують детальні логи по кожному тому: файлова система, used/free, кількість елементів у корені, скільки папок/файлів оброблено і скільки елементів пропущено.

## 1) Створення fine-grained PAT

1. Відкрийте [GitHub Personal Access Tokens](https://github.com/settings/personal-access-tokens).
2. Натисніть **Generate new token** (fine-grained).
3. Заповніть:
   - **Token name**: `twix-drives-scanner`
   - **Resource owner**: `ViTwix`
   - **Repository access**: `Only select repositories` → `twix.production.drives`
   - **Repository permissions**: `Contents: Read and write`
4. Згенеруйте токен і скопіюйте значення (воно показується один раз).

## 2) Встановлення `GITHUB_TOKEN`

### macOS (zsh)

Додайте у `~/.zshrc`:

```bash
export GITHUB_TOKEN='github_pat_...'
```

Потім застосуйте:

```bash
source ~/.zshrc
```

### Windows (PowerShell)

```powershell
[Environment]::SetEnvironmentVariable('GITHUB_TOKEN', 'github_pat_...', 'User')
```

Після цього закрийте і знову відкрийте PowerShell.

## 3) Повне налаштування і запуск на macOS

1. Встановіть Homebrew (якщо ще немає): [https://brew.sh](https://brew.sh)
2. Встановіть `jq`:

```bash
brew install jq
```

3. Склонуйте репозиторій:

```bash
git clone https://github.com/ViTwix/twix.production.drives.git
cd twix.production.drives
```

4. Додайте `GITHUB_TOKEN` у `~/.zshrc` (див. розділ вище), потім:

```bash
source ~/.zshrc
```

5. Перевірте, що токен підхопився:

```bash
echo "${GITHUB_TOKEN:+OK}"
```

6. Запустіть сканування:

```bash
chmod +x ./scripts/scan-mac.sh
./scripts/scan-mac.sh
```

7. Після успішного `HTTP 200/201` підтягніть оновлений JSON локально:

```bash
git pull origin main
```

## 4) Повне налаштування і запуск на Windows

1. Встановіть Git for Windows (якщо ще немає): [https://git-scm.com/download/win](https://git-scm.com/download/win)
2. Склонуйте репозиторій:

```powershell
git clone https://github.com/ViTwix/twix.production.drives.git
cd .\twix.production.drives
```

3. Додайте `GITHUB_TOKEN` у User environment (див. розділ вище), закрийте та заново відкрийте PowerShell.

4. Перевірте, що токен підхопився:

```powershell
if ($env:GITHUB_TOKEN) { 'OK' } else { 'MISSING' }
```

5. За потреби дозвольте запуск локальних скриптів у поточній сесії:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

6. Запустіть сканування:

```powershell
.\scripts\scan-win.ps1
```

7. Після успішного `HTTP 200/201` підтягніть оновлений JSON локально:

```powershell
git pull origin main
```

## 5) Що саме сканується

- **macOS:** усі томи з `/Volumes`, крім системного диска та `Macintosh HD*`.
- **Windows:** усі диски типу `Fixed` або `Removable`, крім системного (`$env:SystemDrive`, зазвичай `C:`).
- У межах кожного тому сканується **корінь**:
  - папки: рахується рекурсивний `sizeBytes`
  - файли: береться `sizeBytes` + `ext` (якщо є)
- Приховані/системні службові елементи пропускаються.

## 6) Troubleshooting

- `jq: command not found` (macOS): встановіть `jq` через `brew install jq`.
- `GITHUB_TOKEN` не підхопився: перезапустіть shell/PowerShell після зміни env vars.
- Проблеми з обрахунком розмірів (macOS): переконайтеся, що `BLOCKSIZE` не заданий вручну; у скрипті він скидається автоматично.
- `401 Unauthorized`: токен невалідний/прострочений або скопійований з помилкою.
- `403 Forbidden`: немає потрібних прав або спрацювали ліміти API.
- `409 Conflict`: паралельне оновлення файла; сканер робить один автоматичний retry.
- `422 Unprocessable Entity`: помилка в тілі запиту (валідація GitHub API).
- Сканер показав попередження про `0 елементів` при зайнятому обсязі: том тимчасово пропущено, щоб не затерти дані порожнім `entries`. Перевірте доступ до кореня тому і запустіть сканер ще раз.
- Локально в `data/drives.json` старі дані після успішного скану: це нормально, бо скрипт пише одразу в GitHub. Зробіть `git pull origin main`.

Якщо мережа/PUT неуспішний, скрипт друкує сформований JSON у stdout, щоб можна було перевірити або зберегти дані вручну.

## 7) Безпечний режим читання

- Сканери не створюють, не змінюють і не видаляють файли на сканованих дисках.
- Веб застосунок працює тільки в read-only режимі: лише `GET` `drives.json`.
- Єдиний запис виконується через GitHub Contents API (`PUT data/drives.json` у репозиторії).

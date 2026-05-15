# Скрипти сканування

Ця папка містить локальні сканери:

- `scan-mac.sh` для macOS
- `scan-win.ps1` для Windows

Обидва скрипти оновлюють `data/drives.json` у GitHub через Contents API.
Один запуск сканера = сканування **всіх підключених несистемних дисків** на поточній машині.
Порядок `entries` у результаті: спочатку папки, потім файли; у межах кожної групи — за назвою (як у файлових менеджерах macOS/Windows).

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

## 3) Запуск сканерів

### macOS

```bash
chmod +x ./scripts/scan-mac.sh
./scripts/scan-mac.sh
```

Скрипт автоматично сканує всі зовнішні томи з `/Volumes`, виключаючи системний диск та службові системні томи.

### Windows

```powershell
.\scripts\scan-win.ps1
```

Скрипт автоматично сканує всі підключені диски типу `Fixed`/`Removable`, виключаючи системний диск (`C:` / `$env:SystemDrive`).

## 4) Troubleshooting

- `jq: command not found` (macOS): встановіть `jq` через `brew install jq`.
- `GITHUB_TOKEN` не підхопився: перезапустіть shell/PowerShell після зміни env vars.
- Проблеми з обрахунком розмірів (macOS): переконайтеся, що `BLOCKSIZE` не заданий вручну; у скрипті він скидається автоматично.
- `401 Unauthorized`: токен невалідний/прострочений або скопійований з помилкою.
- `403 Forbidden`: немає потрібних прав або спрацювали ліміти API.
- `409 Conflict`: паралельне оновлення файла; сканер робить один автоматичний retry.
- `422 Unprocessable Entity`: помилка в тілі запиту (валідація GitHub API).

Якщо мережа/PUT неуспішний, скрипт друкує сформований JSON у stdout, щоб можна було перевірити або зберегти дані вручну.

## 5) Безпечний режим читання

- Сканери не створюють, не змінюють і не видаляють файли на сканованих дисках.
- Веб застосунок працює тільки в read-only режимі: лише `GET` `drives.json`.
- Єдиний запис виконується через GitHub Contents API (`PUT data/drives.json` у репозиторії).

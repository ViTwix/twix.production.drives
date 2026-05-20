#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=en_US.UTF-8
unset BLOCKSIZE

API_URL="https://api.github.com/repos/ViTwix/twix.production.drives/contents/data/drives.json"
PAGES_URL="https://twix-production-drives.pages.dev"

print_err() {
  echo "$*" >&2
}

log_info() {
  printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

log_warn() {
  print_err "[WARN $(date '+%H:%M:%S')] $*"
}

iso_now_utc() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

folder_size_bytes() {
  local kb
  kb=$(du -sk "$1" 2>/dev/null | awk '{print $1}')
  echo $((kb * 1024))
}

file_size_bytes() {
  stat -f%z "$1"
}

human_bytes_short() {
  local bytes="$1"
  local unit value

  if (( bytes >= 1099511627776 )); then
    unit='ТБ'
    value=$(awk -v b="$bytes" 'BEGIN { printf "%.1f", b/1099511627776 }')
  elif (( bytes >= 1073741824 )); then
    unit='ГБ'
    value=$(awk -v b="$bytes" 'BEGIN { printf "%.1f", b/1073741824 }')
  elif (( bytes >= 1048576 )); then
    unit='МБ'
    value=$(awk -v b="$bytes" 'BEGIN { printf "%.0f", b/1048576 }')
  else
    unit='КБ'
    value=$(awk -v b="$bytes" 'BEGIN { printf "%.0f", b/1024 }')
  fi

  printf '%s %s' "$value" "$unit"
}

discover_volumes() {
  VOLUMES=()
  local vol name vol_dev

  SYSTEM_DEV=$(diskutil info / | awk -F': *' '/Device Node/ {print $2; exit}')
  SYSTEM_DISK="${SYSTEM_DEV%s*}"

  for vol in /Volumes/*; do
    [[ -d "$vol" ]] || continue
    name=$(basename "$vol")
    [[ "$name" == "Macintosh HD"* ]] && continue

    vol_dev=$(diskutil info "$vol" 2>/dev/null | awk -F': *' '/Device Node/ {print $2; exit}')
    [[ -z "$vol_dev" ]] && continue
    [[ "$vol_dev" == "$SYSTEM_DISK"* ]] && continue

    VOLUMES+=("$vol")
  done
}

print_volume_menu() {
  local vol name fs total_kb used_kb free_kb total_bytes used_bytes
  local idx=1

  echo
  echo "Підключені томи:"
  for vol in "${VOLUMES[@]}"; do
    name=$(basename "$vol")
    fs=$(diskutil info "$vol" 2>/dev/null | awk -F': *' '/File System Personality/ {print $2; exit}')
    [[ -z "$fs" ]] && fs='Unknown'

    if read -r total_kb used_kb free_kb < <(df -k "$vol" 2>/dev/null | awk 'NR==2 {print $2, $3, $4}'); then
      total_bytes=$((total_kb * 1024))
      used_bytes=$((used_kb * 1024))
      printf '  [%d] %s — %s, %s / %s\n' \
        "$idx" "$name" "$fs" \
        "$(human_bytes_short "$used_bytes")" \
        "$(human_bytes_short "$total_bytes")"
    else
      printf '  [%d] %s — %s\n' "$idx" "$name" "$fs"
    fi
    idx=$((idx + 1))
  done
  echo
  echo "Оберіть томи для сканування:"
  echo "  • номери через кому: 1,3"
  echo "  • діапазон: 1-3"
  echo "  • Enter — усі томи"
  echo "  • q — скасувати"
  echo
}

parse_volume_selection() {
  local input="$1"
  local -a parts=()
  local -a indices=()
  local -a unique_indices=()
  local part start end idx

  SELECTED_VOLUMES=()

  input=$(printf '%s' "$input" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')

  if [[ "$input" == "q" ]]; then
    return 1
  fi

  if [[ -z "$input" ]]; then
    SELECTED_VOLUMES=("${VOLUMES[@]}")
    return 0
  fi

  IFS=',' read -ra parts <<<"$input"
  for part in "${parts[@]}"; do
    [[ -z "$part" ]] && continue
    if [[ "$part" =~ ^([0-9]+)-([0-9]+)$ ]]; then
      start="${BASH_REMATCH[1]}"
      end="${BASH_REMATCH[2]}"
      if (( start > end )); then
        print_err "Невірний діапазон: $part"
        return 2
      fi
      for ((idx = start; idx <= end; idx++)); do
        indices+=("$idx")
      done
    elif [[ "$part" =~ ^[0-9]+$ ]]; then
      indices+=("$part")
    else
      print_err "Невірний формат вибору: $part"
      return 2
    fi
  done

  if [[ ${#indices[@]} -eq 0 ]]; then
    print_err "Не вказано жодного тому."
    return 2
  fi

  unique_indices=()
  while IFS= read -r idx; do
    [[ -n "$idx" ]] && unique_indices+=("$idx")
  done < <(printf '%s\n' "${indices[@]}" | LC_ALL=C sort -un)

  for idx in "${unique_indices[@]}"; do
    if (( idx < 1 || idx > ${#VOLUMES[@]} )); then
      print_err "Номер поза діапазоном: $idx (доступно 1–${#VOLUMES[@]})"
      return 2
    fi
    SELECTED_VOLUMES+=("${VOLUMES[$((idx - 1))]}")
  done

  return 0
}

prompt_volume_selection() {
  local choice

  print_volume_menu
  read -r -p "Ваш вибір: " choice

  if ! parse_volume_selection "$choice"; then
    case $? in
      1)
        echo "Скасовано."
        exit 0
        ;;
      *)
        exit 1
        ;;
    esac
  fi
}

github_get() {
  curl -sS -L \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "X-GitHub-Api-Version: 2026-03-10" \
    -H "User-Agent: twix-drives-scanner" \
    "$API_URL" \
    -w $'\n%{http_code}'
}

github_put() {
  local payload="$1"

  curl -sS -L -X PUT \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "X-GitHub-Api-Version: 2026-03-10" \
    -H "User-Agent: twix-drives-scanner" \
    -d "$payload" \
    "$API_URL" \
    -w $'\n%{http_code}'
}

load_remote_json() {
  local response status body content
  response=$(github_get)
  status="${response##*$'\n'}"
  body="${response%$'\n'*}"

  case "$status" in
    200)
      REMOTE_SHA=$(jq -r '.sha // ""' <<<"$body")
      content=$(jq -r '.content // ""' <<<"$body" | tr -d '\n')
      if [[ -z "$content" ]]; then
        print_err "Помилка: GitHub повернув порожній content для data/drives.json"
        print_err "$body"
        exit 1
      fi
      if ! REMOTE_JSON=$(printf '%s' "$content" | base64 --decode 2>/dev/null); then
        print_err "Помилка: не вдалося декодувати content з GitHub"
        print_err "$body"
        exit 1
      fi
      ;;
    404)
      REMOTE_SHA=""
      REMOTE_JSON='{"updatedAt": null, "drives": []}'
      ;;
    *)
      print_err "Помилка GET GitHub API (HTTP $status)"
      print_err "$body"
      exit 1
      ;;
  esac
}

build_next_json() {
  local source_json="$1"
  local drive_json="$2"
  local now_iso="$3"

  jq -c \
    --argjson drive "$drive_json" \
    --arg now "$now_iso" \
    '
      {
        updatedAt: $now,
        drives: (
          ((.drives // []) | map(select(.name != $drive.name))) + [$drive]
          | sort_by(.name)
        )
      }
    ' <<<"$source_json"
}

build_put_payload() {
  local message="$1"
  local content_b64="$2"
  local sha="$3"

  jq -c -n \
    --arg message "$message" \
    --arg content "$content_b64" \
    --arg branch "main" \
    --arg sha "$sha" \
    '
      if $sha == "" then
        {message: $message, content: $content, branch: $branch}
      else
        {message: $message, content: $content, branch: $branch, sha: $sha}
      end
    '
}

load_github_token_from_env_file() {
  local env_file="$1"
  local line value

  [[ -f "$env_file" ]] || return 1

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ "$line" =~ ^[[:space:]]*$ ]] && continue
    if [[ "$line" =~ ^[[:space:]]*GITHUB_TOKEN[[:space:]]*=[[:space:]]*(.*)$ ]]; then
      value="${BASH_REMATCH[1]}"
      if [[ "$value" =~ ^\"(.*)\"$ ]]; then
        value="${BASH_REMATCH[1]}"
      elif [[ "$value" =~ ^\'(.*)\'$ ]]; then
        value="${BASH_REMATCH[1]}"
      fi
      value="${value#"${value%%[![:space:]]*}"}"
      value="${value%"${value##*[![:space:]]}"}"
      if [[ -n "$value" ]]; then
        export GITHUB_TOKEN="$value"
        return 0
      fi
    fi
  done <"$env_file"

  return 1
}

ensure_github_token() {
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    return 0
  fi

  local repo_root env_file
  repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
  env_file="$repo_root/.env"

  if load_github_token_from_env_file "$env_file"; then
    return 0
  fi

  print_err "Помилка: не задано GITHUB_TOKEN."
  print_err "Створіть $env_file з рядком: GITHUB_TOKEN=github_pat_…"
  print_err "Або export GITHUB_TOKEN у ~/.zshrc (див. scripts/README.md)"
  exit 1
}

if ! command -v jq >/dev/null 2>&1; then
  print_err "Помилка: не знайдено jq. Встановіть: brew install jq"
  exit 1
fi

SCAN_ALL=false
for arg in "$@"; do
  case "$arg" in
    -a | --all) SCAN_ALL=true ;;
    -h | --help)
      echo "Використання: $(basename "$0") [--all]"
      echo "  без прапорців — інтерактивний вибір підключених томів"
      echo "  --all, -a    — сканувати всі підключені томи без запиту"
      echo "  GITHUB_TOKEN — env var або .env у корені репозиторію"
      exit 0
      ;;
    *)
      print_err "Невідомий аргумент: $arg (див. --help)"
      exit 1
      ;;
  esac
done

ensure_github_token

discover_volumes

if [[ ${#VOLUMES[@]} -eq 0 ]]; then
  print_err "Не знайдено зовнішніх томів для сканування."
  exit 1
fi

if [[ "$SCAN_ALL" == true ]]; then
  SELECTED_VOLUMES=("${VOLUMES[@]}")
elif [[ -t 0 ]]; then
  prompt_volume_selection
else
  print_err "Неінтерактивний режим: додайте --all для сканування всіх томів."
  exit 1
fi

SCANNED_DRIVE_NAMES=()
for vol in "${SELECTED_VOLUMES[@]}"; do
  SCANNED_DRIVE_NAMES+=("$(basename "$vol")")
done

echo
if [[ ${#SELECTED_VOLUMES[@]} -eq ${#VOLUMES[@]} ]]; then
  echo "Сканую всі ${#SELECTED_VOLUMES[@]} том(ів)..."
else
  echo "Сканую ${#SELECTED_VOLUMES[@]} з ${#VOLUMES[@]} том(ів): $(IFS=', '; echo "${SCANNED_DRIVE_NAMES[*]}")"
fi

SCANNED_DRIVES=()
NOW_ISO=$(iso_now_utc)
volume_count=${#SELECTED_VOLUMES[@]}

for volume_index in "${!SELECTED_VOLUMES[@]}"; do
  SELECTED_VOLUME="${SELECTED_VOLUMES[$volume_index]}"
  DRIVE_NAME=$(basename "$SELECTED_VOLUME")

  echo
  printf "=== [%d/%d] Сканую том: %s ===\n" "$((volume_index + 1))" "$volume_count" "$DRIVE_NAME"

  FS=$(diskutil info "$SELECTED_VOLUME" | awk -F': *' '/File System Personality/ {print $2; exit}')
  [[ -z "$FS" ]] && FS="Unknown"

  if ! read -r TOTAL_KB USED_KB FREE_KB < <(df -k "$SELECTED_VOLUME" | awk 'NR==2 {print $2, $3, $4}'); then
    print_err "Попередження: пропускаю том (не вдалося отримати df): $DRIVE_NAME"
    continue
  fi

  TOTAL_BYTES=$((TOTAL_KB * 1024))
  USED_BYTES=$((USED_KB * 1024))
  FREE_BYTES=$((FREE_KB * 1024))
  log_info "Том \"$DRIVE_NAME\": FS=$FS, used=$(printf '%s' "$USED_BYTES"), free=$(printf '%s' "$FREE_BYTES")"

  ROOT_ITEMS=()
  if ! while IFS= read -r -d '' item; do
    base_name=$(basename "$item")
    [[ "$base_name" == .* ]] && continue
    case "$base_name" in
      "System Volume Information" | "\$RECYCLE.BIN" | "\$Recycle.Bin" | "RECYCLER")
        continue
        ;;
    esac
    ROOT_ITEMS+=("$item")
  done < <(find "$SELECTED_VOLUME" -mindepth 1 -maxdepth 1 -print0 2>/dev/null); then
    print_err "Попередження: не вдалося прочитати корінь тому: $DRIVE_NAME"
    continue
  fi

  item_count=${#ROOT_ITEMS[@]}
  if ((item_count == 0)) && ((USED_BYTES > 10485760)); then
    log_warn "Том \"$DRIVE_NAME\" має зайнятий обсяг, але корінь повернув 0 елементів. Пропускаю, щоб не записати порожні дані."
    continue
  fi

  log_info "Том \"$DRIVE_NAME\": знайдено $item_count елемент(ів) у корені"

  ENTRY_LINES=()
  folders_processed=0
  files_processed=0
  skipped_items=0

  for i in "${!ROOT_ITEMS[@]}"; do
    item="${ROOT_ITEMS[$i]}"
    base_name=$(basename "$item")
    printf "  [%d/%d] %s...\n" "$((i + 1))" "$item_count" "$base_name"

    if [[ -d "$item" ]]; then
      if ! size_bytes=$(folder_size_bytes "$item"); then
        log_warn "Пропускаю папку без доступу: $base_name"
        skipped_items=$((skipped_items + 1))
        continue
      fi

      ENTRY_LINES+=("$(jq -c -n \
        --arg name "$base_name" \
        --argjson sizeBytes "$size_bytes" \
        '{type: "folder", name: $name, sizeBytes: $sizeBytes}')")
      folders_processed=$((folders_processed + 1))
      continue
    fi

    if [[ -f "$item" ]]; then
      if ! size_bytes=$(file_size_bytes "$item" 2>/dev/null); then
        log_warn "Пропускаю файл без доступу: $base_name"
        skipped_items=$((skipped_items + 1))
        continue
      fi

      ext=""
      if [[ "$base_name" == *.* && "$base_name" != .* ]]; then
        ext="${base_name##*.}"
        ext=$(printf '%s' "$ext" | tr '[:upper:]' '[:lower:]')
      fi

      if [[ -n "$ext" ]]; then
        ENTRY_LINES+=("$(jq -c -n \
          --arg name "$base_name" \
          --arg ext "$ext" \
          --argjson sizeBytes "$size_bytes" \
          '{type: "file", name: $name, ext: $ext, sizeBytes: $sizeBytes}')")
      else
        ENTRY_LINES+=("$(jq -c -n \
          --arg name "$base_name" \
          --argjson sizeBytes "$size_bytes" \
          '{type: "file", name: $name, sizeBytes: $sizeBytes}')")
      fi
      files_processed=$((files_processed + 1))
    fi
  done

  if [[ ${#ENTRY_LINES[@]} -eq 0 ]]; then
    ENTRIES_JSON='[]'
  else
    ENTRIES_JSON=$(printf '%s\n' "${ENTRY_LINES[@]}" | jq -cs '
      sort_by(
        if .type == "folder" then 0 else 1 end,
        (.name | ascii_downcase)
      )
    ')
  fi

  log_info "Підсумок \"$DRIVE_NAME\": папок=$folders_processed, файлів=$files_processed, пропущено=$skipped_items, entries=${#ENTRY_LINES[@]}"

  DRIVE_JSON=$(jq -c -n \
    --arg name "$DRIVE_NAME" \
    --arg scannedAt "$NOW_ISO" \
    --arg filesystem "$FS" \
    --argjson totalBytes "$TOTAL_BYTES" \
    --argjson freeBytes "$FREE_BYTES" \
    --argjson usedBytes "$USED_BYTES" \
    --argjson entries "$ENTRIES_JSON" \
    '{
      name: $name,
      scannedAt: $scannedAt,
      filesystem: $filesystem,
      totalBytes: $totalBytes,
      freeBytes: $freeBytes,
      usedBytes: $usedBytes,
      entries: $entries
    }')

  SCANNED_DRIVES+=("$DRIVE_JSON")
done

if [[ ${#SCANNED_DRIVES[@]} -eq 0 ]]; then
  print_err "Не вдалося зібрати дані з жодного тому. Перевірте попередження вище."
  exit 1
fi

load_remote_json
NEXT_JSON="$REMOTE_JSON"
for DRIVE_JSON in "${SCANNED_DRIVES[@]}"; do
  NEXT_JSON=$(build_next_json "$NEXT_JSON" "$DRIVE_JSON" "$NOW_ISO")
done

NEXT_B64=$(printf '%s' "$NEXT_JSON" | base64 | tr -d '\n')
if [[ ${#SCANNED_DRIVES[@]} -eq ${#VOLUMES[@]} ]]; then
  COMMIT_MESSAGE="scan: full sweep at ${NOW_ISO} (${#SCANNED_DRIVES[@]} drives)"
else
  COMMIT_MESSAGE="scan: $(IFS=', '; echo "${SCANNED_DRIVE_NAMES[*]}") at ${NOW_ISO}"
fi
log_info "Підготовлено ${#SCANNED_DRIVES[@]} запис(ів) дисків. Записую в GitHub..."
PAYLOAD=$(build_put_payload "$COMMIT_MESSAGE" "$NEXT_B64" "$REMOTE_SHA")

PUT_RESPONSE=$(github_put "$PAYLOAD")
PUT_STATUS="${PUT_RESPONSE##*$'\n'}"
PUT_BODY="${PUT_RESPONSE%$'\n'*}"

if [[ "$PUT_STATUS" == "409" ]]; then
  log_warn "Отримано 409 Conflict. Повторюю один раз..."
  load_remote_json
  NEXT_JSON="$REMOTE_JSON"
  for DRIVE_JSON in "${SCANNED_DRIVES[@]}"; do
    NEXT_JSON=$(build_next_json "$NEXT_JSON" "$DRIVE_JSON" "$NOW_ISO")
  done
  NEXT_B64=$(printf '%s' "$NEXT_JSON" | base64 | tr -d '\n')
  PAYLOAD=$(build_put_payload "$COMMIT_MESSAGE" "$NEXT_B64" "$REMOTE_SHA")
  PUT_RESPONSE=$(github_put "$PAYLOAD")
  PUT_STATUS="${PUT_RESPONSE##*$'\n'}"
  PUT_BODY="${PUT_RESPONSE%$'\n'*}"
fi

case "$PUT_STATUS" in
  200|201)
    log_info "Готово. Дані оновлено успішно (HTTP $PUT_STATUS)."
    log_info "Веб: $PAGES_URL"
    ;;
  *)
    print_err "Помилка PUT GitHub API (HTTP $PUT_STATUS). message=\"$COMMIT_MESSAGE\""
    print_err "$PUT_BODY"
    print_err "Нижче надруковано JSON, який не вдалося записати:"
    echo "$NEXT_JSON"
    exit 1
    ;;
esac

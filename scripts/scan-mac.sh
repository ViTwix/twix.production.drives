#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=en_US.UTF-8
unset BLOCKSIZE

API_URL="https://api.github.com/repos/ViTwix/twix.production.drives/contents/data/drives.json"
PAGES_URL="https://twix-production-drives.pages.dev"
MACHINE_FILE="${HOME}/.twix-drives-machine"

print_err() {
  echo "$*" >&2
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

choose_machine() {
  if [[ -f "$MACHINE_FILE" ]]; then
    local stored
    stored=$(<"$MACHINE_FILE")
    if [[ "$stored" == "Mac Mini" || "$stored" == "MacBook" ]]; then
      echo "$stored"
      return
    fi
  fi

  echo "Оберіть назву цієї машини:"
  echo "  1) Mac Mini"
  echo "  2) MacBook"
  read -r -p "Вибір [1-2]: " choice

  case "$choice" in
    1) echo "Mac Mini" >"$MACHINE_FILE" ;;
    2) echo "MacBook" >"$MACHINE_FILE" ;;
    *)
      print_err "Некоректний вибір машини"
      exit 1
      ;;
  esac

  cat "$MACHINE_FILE"
}

if [[ "${1:-}" == "--reset-machine" ]]; then
  rm -f "$MACHINE_FILE"
  echo "Збережену назву машини скинуто."
  exit 0
fi

: "${GITHUB_TOKEN:?Set GITHUB_TOKEN env var (see scripts/README.md)}"

if ! command -v jq >/dev/null 2>&1; then
  print_err "Помилка: не знайдено jq. Встановіть: brew install jq"
  exit 1
fi

SYSTEM_DEV=$(diskutil info / | awk -F': *' '/Device Node/ {print $2; exit}')
SYSTEM_DISK="${SYSTEM_DEV%s*}"

VOLUMES=()
for vol in /Volumes/*; do
  [[ -d "$vol" ]] || continue
  name=$(basename "$vol")
  [[ "$name" == "Macintosh HD"* ]] && continue

  vol_dev=$(diskutil info "$vol" 2>/dev/null | awk -F': *' '/Device Node/ {print $2; exit}')
  [[ -z "$vol_dev" ]] && continue
  [[ "$vol_dev" == "$SYSTEM_DISK"* ]] && continue

  VOLUMES+=("$vol")
done

if [[ ${#VOLUMES[@]} -eq 0 ]]; then
  print_err "Не знайдено зовнішніх томів для сканування."
  exit 1
fi

echo "Доступні томи:"
for i in "${!VOLUMES[@]}"; do
  printf "  %d) %s\n" "$((i + 1))" "$(basename "${VOLUMES[$i]}")"
done

read -r -p "Оберіть номер тому: " volume_idx
if ! [[ "$volume_idx" =~ ^[0-9]+$ ]] || ((volume_idx < 1 || volume_idx > ${#VOLUMES[@]})); then
  print_err "Некоректний вибір тому."
  exit 1
fi

SELECTED_VOLUME="${VOLUMES[$((volume_idx - 1))]}"
DEFAULT_DRIVE_NAME=$(basename "$SELECTED_VOLUME")
read -r -p "Назва диска [${DEFAULT_DRIVE_NAME}]: " DRIVE_NAME
DRIVE_NAME="${DRIVE_NAME:-$DEFAULT_DRIVE_NAME}"

MACHINE_NAME=$(choose_machine)
NOW_ISO=$(iso_now_utc)

FS=$(diskutil info "$SELECTED_VOLUME" | awk -F': *' '/File System Personality/ {print $2; exit}')
read -r TOTAL_KB USED_KB FREE_KB < <(df -k "$SELECTED_VOLUME" | awk 'NR==2 {print $2, $3, $4}')
TOTAL_BYTES=$((TOTAL_KB * 1024))
USED_BYTES=$((USED_KB * 1024))
FREE_BYTES=$((FREE_KB * 1024))

ROOT_ITEMS=()
for item in "$SELECTED_VOLUME"/*; do
  [[ -e "$item" ]] || continue
  base_name=$(basename "$item")
  [[ "$base_name" == .* ]] && continue
  ROOT_ITEMS+=("$item")
done

entries_tmp=$(mktemp)
item_count=${#ROOT_ITEMS[@]}

for i in "${!ROOT_ITEMS[@]}"; do
  item="${ROOT_ITEMS[$i]}"
  base_name=$(basename "$item")
  printf "[%d/%d] %s...\n" "$((i + 1))" "$item_count" "$base_name"

  if [[ -d "$item" ]]; then
    if ! size_bytes=$(folder_size_bytes "$item"); then
      print_err "Попередження: пропускаю папку без доступу: $base_name"
      continue
    fi

    jq -c -n \
      --arg name "$base_name" \
      --argjson sizeBytes "$size_bytes" \
      '{type: "folder", name: $name, sizeBytes: $sizeBytes}' >>"$entries_tmp"
    continue
  fi

  if [[ -f "$item" ]]; then
    if ! size_bytes=$(file_size_bytes "$item" 2>/dev/null); then
      print_err "Попередження: пропускаю файл без доступу: $base_name"
      continue
    fi

    ext=""
    if [[ "$base_name" == *.* && "$base_name" != .* ]]; then
      ext="${base_name##*.}"
      ext="${ext,,}"
    fi

    if [[ -n "$ext" ]]; then
      jq -c -n \
        --arg name "$base_name" \
        --arg ext "$ext" \
        --argjson sizeBytes "$size_bytes" \
        '{type: "file", name: $name, ext: $ext, sizeBytes: $sizeBytes}' >>"$entries_tmp"
    else
      jq -c -n \
        --arg name "$base_name" \
        --argjson sizeBytes "$size_bytes" \
        '{type: "file", name: $name, sizeBytes: $sizeBytes}' >>"$entries_tmp"
    fi
  fi
done

ENTRIES_JSON=$(jq -cs 'sort_by(.sizeBytes) | reverse' "$entries_tmp")
rm -f "$entries_tmp"

DRIVE_JSON=$(jq -c -n \
  --arg name "$DRIVE_NAME" \
  --arg scannedAt "$NOW_ISO" \
  --arg scannedFrom "$MACHINE_NAME" \
  --arg filesystem "$FS" \
  --argjson totalBytes "$TOTAL_BYTES" \
  --argjson freeBytes "$FREE_BYTES" \
  --argjson usedBytes "$USED_BYTES" \
  --argjson entries "$ENTRIES_JSON" \
  '{
    name: $name,
    scannedAt: $scannedAt,
    scannedFrom: $scannedFrom,
    filesystem: $filesystem,
    totalBytes: $totalBytes,
    freeBytes: $freeBytes,
    usedBytes: $usedBytes,
    entries: $entries
  }')

load_remote_json
NEXT_JSON=$(build_next_json "$REMOTE_JSON" "$DRIVE_JSON" "$NOW_ISO")
NEXT_B64=$(printf '%s' "$NEXT_JSON" | base64 | tr -d '\n')
COMMIT_MESSAGE="scan: ${DRIVE_NAME} from ${MACHINE_NAME} at ${NOW_ISO}"
PAYLOAD=$(build_put_payload "$COMMIT_MESSAGE" "$NEXT_B64" "$REMOTE_SHA")

PUT_RESPONSE=$(github_put "$PAYLOAD")
PUT_STATUS="${PUT_RESPONSE##*$'\n'}"
PUT_BODY="${PUT_RESPONSE%$'\n'*}"

if [[ "$PUT_STATUS" == "409" ]]; then
  print_err "Отримано 409 Conflict. Повторюю один раз..."
  load_remote_json
  NEXT_JSON=$(build_next_json "$REMOTE_JSON" "$DRIVE_JSON" "$NOW_ISO")
  NEXT_B64=$(printf '%s' "$NEXT_JSON" | base64 | tr -d '\n')
  PAYLOAD=$(build_put_payload "$COMMIT_MESSAGE" "$NEXT_B64" "$REMOTE_SHA")
  PUT_RESPONSE=$(github_put "$PAYLOAD")
  PUT_STATUS="${PUT_RESPONSE##*$'\n'}"
  PUT_BODY="${PUT_RESPONSE%$'\n'*}"
fi

case "$PUT_STATUS" in
  200|201)
    echo "Готово. Дані оновлено успішно (HTTP $PUT_STATUS)."
    echo "Веб: $PAGES_URL"
    ;;
  *)
    print_err "Помилка PUT GitHub API (HTTP $PUT_STATUS)"
    print_err "$PUT_BODY"
    print_err "Нижче надруковано JSON, який не вдалося записати:"
    echo "$NEXT_JSON"
    exit 1
    ;;
esac

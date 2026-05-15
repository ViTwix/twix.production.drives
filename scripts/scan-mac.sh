#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=en_US.UTF-8
unset BLOCKSIZE

API_URL="https://api.github.com/repos/ViTwix/twix.production.drives/contents/data/drives.json"
PAGES_URL="https://twix-production-drives.pages.dev"

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

echo "Знайдено ${#VOLUMES[@]} том(ів). Запускаю повне сканування..."

SCANNED_DRIVES=()
NOW_ISO=$(iso_now_utc)
volume_count=${#VOLUMES[@]}

for volume_index in "${!VOLUMES[@]}"; do
  SELECTED_VOLUME="${VOLUMES[$volume_index]}"
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

  ROOT_ITEMS=()
  for item in "$SELECTED_VOLUME"/*; do
    [[ -e "$item" ]] || continue
    base_name=$(basename "$item")
    [[ "$base_name" == .* ]] && continue
    case "$base_name" in
      "System Volume Information" | "\$RECYCLE.BIN" | "\$Recycle.Bin" | "RECYCLER")
        continue
        ;;
    esac
    ROOT_ITEMS+=("$item")
  done

  item_count=${#ROOT_ITEMS[@]}
  ENTRY_LINES=()

  for i in "${!ROOT_ITEMS[@]}"; do
    item="${ROOT_ITEMS[$i]}"
    base_name=$(basename "$item")
    printf "  [%d/%d] %s...\n" "$((i + 1))" "$item_count" "$base_name"

    if [[ -d "$item" ]]; then
      if ! size_bytes=$(folder_size_bytes "$item"); then
        print_err "Попередження: пропускаю папку без доступу: $base_name"
        continue
      fi

      ENTRY_LINES+=("$(jq -c -n \
        --arg name "$base_name" \
        --argjson sizeBytes "$size_bytes" \
        '{type: "folder", name: $name, sizeBytes: $sizeBytes}')")
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
  print_err "Не вдалося зібрати дані з жодного тому."
  exit 1
fi

load_remote_json
NEXT_JSON="$REMOTE_JSON"
for DRIVE_JSON in "${SCANNED_DRIVES[@]}"; do
  NEXT_JSON=$(build_next_json "$NEXT_JSON" "$DRIVE_JSON" "$NOW_ISO")
done

NEXT_B64=$(printf '%s' "$NEXT_JSON" | base64 | tr -d '\n')
COMMIT_MESSAGE="scan: full sweep at ${NOW_ISO} (${#SCANNED_DRIVES[@]} drives)"
PAYLOAD=$(build_put_payload "$COMMIT_MESSAGE" "$NEXT_B64" "$REMOTE_SHA")

PUT_RESPONSE=$(github_put "$PAYLOAD")
PUT_STATUS="${PUT_RESPONSE##*$'\n'}"
PUT_BODY="${PUT_RESPONSE%$'\n'*}"

if [[ "$PUT_STATUS" == "409" ]]; then
  print_err "Отримано 409 Conflict. Повторюю один раз..."
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

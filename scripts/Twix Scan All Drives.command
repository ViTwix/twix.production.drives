#!/usr/bin/env bash
# Подвійний клік → сканування всіх підключених томів без меню (--all)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

export LC_ALL=en_US.UTF-8

"$SCRIPT_DIR/scan-mac.sh" --all
status=$?

echo
if (( status == 0 )); then
  read -r -p "Готово. Enter щоб закрити…" _
else
  read -r -p "Завершено з помилкою ($status). Enter щоб закрити…" _
fi

exit "$status"

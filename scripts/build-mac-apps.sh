#!/usr/bin/env bash
# Збирає Twix Scan Drives.app / Twix Scan All Drives.app для Dock (macOS).
# .app має лишатися в scripts/ поруч із scan-mac.sh — шлях до репо обчислюється відносно.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ICON_SRC="$REPO_ROOT/AppIcons/Assets.xcassets/AppIcon.appiconset"
BUILD_DIR="$SCRIPT_DIR/.mac-app-build"
ICNS_PATH=""

prepare_app_icon() {
  local iconset_dir="$BUILD_DIR/AppIcon.iconset"

  if [[ -n "$ICNS_PATH" && -f "$ICNS_PATH" ]]; then
    return 0
  fi

  if ! command -v iconutil >/dev/null 2>&1; then
    echo "Попередження: iconutil не знайдено — .app без іконки." >&2
    return 0
  fi

  local -a required=(16.png 32.png 64.png 128.png 256.png 512.png 1024.png)
  local name

  for name in "${required[@]}"; do
    if [[ ! -f "$ICON_SRC/$name" ]]; then
      echo "Попередження: немає $ICON_SRC/$name — .app без іконки." >&2
      return 0
    fi
  done

  rm -rf "$iconset_dir"
  mkdir -p "$iconset_dir"

  cp "$ICON_SRC/16.png" "$iconset_dir/icon_16x16.png"
  cp "$ICON_SRC/32.png" "$iconset_dir/icon_16x16@2x.png"
  cp "$ICON_SRC/32.png" "$iconset_dir/icon_32x32.png"
  cp "$ICON_SRC/64.png" "$iconset_dir/icon_32x32@2x.png"
  cp "$ICON_SRC/128.png" "$iconset_dir/icon_128x128.png"
  cp "$ICON_SRC/256.png" "$iconset_dir/icon_128x128@2x.png"
  cp "$ICON_SRC/256.png" "$iconset_dir/icon_256x256.png"
  cp "$ICON_SRC/512.png" "$iconset_dir/icon_256x256@2x.png"
  cp "$ICON_SRC/512.png" "$iconset_dir/icon_512x512.png"
  cp "$ICON_SRC/1024.png" "$iconset_dir/icon_512x512@2x.png"

  ICNS_PATH="$BUILD_DIR/AppIcon.icns"
  iconutil -c icns "$iconset_dir" -o "$ICNS_PATH"
}

build_app() {
  local app_name="$1"
  local command_file="$2"
  local app_dir="$SCRIPT_DIR/${app_name}.app"
  local macos_dir="$app_dir/Contents/MacOS"
  local resources_dir="$app_dir/Contents/Resources"
  local plist_path="$app_dir/Contents/Info.plist"

  rm -rf "$app_dir"
  mkdir -p "$macos_dir" "$resources_dir"

  cat >"$macos_dir/run" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

BINDIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_DIR="$(cd "$BINDIR/../../.." && pwd)"
COMMAND_FILE="$SCRIPTS_DIR/COMMAND_PLACEHOLDER"

if [[ ! -f "$COMMAND_FILE" ]]; then
  osascript -e "display alert \"Twix Scan\" message \"Не знайдено COMMAND_PLACEHOLDER. Залиште .app у папці scripts/ репозиторію.\" as critical"
  exit 1
fi

open -a Terminal "$COMMAND_FILE"
EOF

  sed -i '' "s/COMMAND_PLACEHOLDER/$command_file/g" "$macos_dir/run"
  chmod +x "$macos_dir/run"

  cat >"$plist_path" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>run</string>
  <key>CFBundleIdentifier</key>
  <string>dev.twix.scan-drives</string>
  <key>CFBundleName</key>
  <string>${app_name}</string>
  <key>CFBundleDisplayName</key>
  <string>${app_name}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
</dict>
</plist>
EOF

  if [[ -n "$ICNS_PATH" && -f "$ICNS_PATH" ]]; then
    cp "$ICNS_PATH" "$resources_dir/AppIcon.icns"
  fi

  echo "Створено: $app_dir"
}

prepare_app_icon
build_app "Twix Scan Drives" "Twix Scan Drives.command"
build_app "Twix Scan All Drives" "Twix Scan All Drives.command"

echo
echo "Перетягніть .app у Dock (ліворуч від лінії ···, поруч із Finder)."
echo "Не переносьте .app з папки scripts/ — інакше не знайде скрипти."
echo "Якщо macOS блокує: ПКМ → Відкрити."

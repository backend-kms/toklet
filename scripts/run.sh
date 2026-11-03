#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]]; then
  echo 'Toklet은 macOS 13 이상에서 실행할 수 있습니다.' >&2
  exit 1
fi
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP_DIR="$PWD/.build/Toklet.app"
mkdir -p "$APP_DIR/Contents/MacOS"
cp "$BIN_DIR/Toklet" "$APP_DIR/Contents/MacOS/Toklet"
cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Toklet</string>
<key>CFBundleDisplayName</key><string>Toklet</string>
<key>CFBundleIdentifier</key><string>local.toklet.app</string>
<key>CFBundleExecutable</key><string>Toklet</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP_DIR"
if [[ "${1:-}" == --build-only ]]; then
  printf '빌드 완료: %s\n' "$APP_DIR"
  exit 0
fi
open "$APP_DIR"
printf '실행 완료: %s\n' "$APP_DIR"

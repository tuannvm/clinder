#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Clinder"
BUNDLE_ID="dev.tuannvm.clinder"
BUNDLE="$ROOT/dist/$APP_NAME.app"
APP_BINARY="$BUNDLE/Contents/MacOS/$APP_NAME"
APP_RESOURCES="$BUNDLE/Contents/Resources"
INSTALLED_BUNDLE="/Applications/$APP_NAME.app"
EXECUTABLE="$ROOT/.build/debug/$APP_NAME"
APP_ICON="$ROOT/Assets/AppIcon.icns"

cd "$ROOT"

pkill -x "$APP_NAME" 2>/dev/null || true
swift build

if [[ ! -f "$APP_ICON" || "$ROOT/Assets/AppIcon.svg" -nt "$APP_ICON" ]]; then
  "$ROOT/script/generate_icon.sh"
fi

rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$APP_RESOURCES"
cp "$EXECUTABLE" "$APP_BINARY"
chmod +x "$APP_BINARY"
cp "$APP_ICON" "$APP_RESOURCES/AppIcon.icns"

cat > "$BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

open_app() {
  /usr/bin/open -n "$BUNDLE"
}

install_app() {
  rm -rf "$INSTALLED_BUNDLE"
  cp -R "$BUNDLE" "$INSTALLED_BUNDLE"
}

open_installed_app() {
  /usr/bin/open -n "$INSTALLED_BUNDLE"
}

case "$MODE" in
  stage|build)
    ;;
  run)
    open_app
    ;;
  --install|install)
    install_app
    ;;
  --install-run|install-run)
    install_app
    open_installed_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    echo "$APP_NAME launched"
    ;;
  *)
    echo "usage: $0 [stage|build|run|install|install-run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac

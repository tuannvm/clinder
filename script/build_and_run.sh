#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Clinder"
BUNDLE_ID="dev.tuannvm.clinder"
APP_VERSION="${VERSION:-0.1.0}"
MIN_MACOS_VERSION="${CLINDER_MIN_MACOS_VERSION:-27.0}"
if [[ "$MODE" == "release" && -z "${VERSION:-}" ]]; then
  APP_VERSION="0.0.1"
fi
BUNDLE="$ROOT/dist/$APP_NAME.app"
APP_BINARY="$BUNDLE/Contents/MacOS/$APP_NAME"
APP_RESOURCES="$BUNDLE/Contents/Resources"
INSTALLED_BUNDLE="/Applications/$APP_NAME.app"
EXECUTABLE="$ROOT/.build/debug/$APP_NAME"
APP_ICON="$ROOT/Assets/AppIcon.icns"
ENV_FILE="$ROOT/.env"
RELEASE_TAG="v$APP_VERSION"
RELEASE_ARCHIVE="$ROOT/dist/$APP_NAME-$APP_VERSION-macos-arm64.zip"

cd "$ROOT"

if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "$ENV_FILE"
  set +a
fi

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
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_MACOS_VERSION</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

sign_app() {
  local identity="${CLINDER_CODE_SIGN_IDENTITY:-}"
  if [[ -z "$identity" ]]; then
    return
  fi

  local args=(--force --sign "$identity")
  if [[ -n "${CLINDER_CODE_SIGN_OPTIONS:-}" ]]; then
    args+=(--options "$CLINDER_CODE_SIGN_OPTIONS")
  fi
  if [[ -n "${CLINDER_CODE_SIGN_TIMESTAMP:-}" ]]; then
    args+=(--timestamp="$CLINDER_CODE_SIGN_TIMESTAMP")
  fi

  codesign "${args[@]}" "$BUNDLE"
  codesign --verify --strict --deep "$BUNDLE"

  local signing_details
  signing_details="$(codesign -dvvv "$BUNDLE" 2>&1)"

  if [[ -n "${CLINDER_SITE_ID:-}" ]] && ! grep -q "TeamIdentifier=$CLINDER_SITE_ID" <<<"$signing_details"; then
    echo "error: signed app does not match CLINDER_SITE_ID=$CLINDER_SITE_ID" >&2
    exit 1
  fi

  if [[ -n "${CLINDER_DEVELOPER_NAME:-}" ]] && ! grep -q "Authority=.*$CLINDER_DEVELOPER_NAME" <<<"$signing_details"; then
    echo "error: signed app does not match CLINDER_DEVELOPER_NAME=$CLINDER_DEVELOPER_NAME" >&2
    exit 1
  fi
}

sign_app

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

release_app() {
  if ! command -v gh >/dev/null; then
    echo "error: gh CLI is required for release" >&2
    exit 1
  fi

  rm -f "$RELEASE_ARCHIVE"
  ditto -c -k --sequesterRsrc --keepParent "$BUNDLE" "$RELEASE_ARCHIVE"

  local target
  target="$(git rev-parse HEAD)"

  if gh release view "$RELEASE_TAG" >/dev/null 2>&1; then
    gh release upload "$RELEASE_TAG" "$RELEASE_ARCHIVE#Clinder $APP_VERSION macOS arm64" --clobber
  else
    gh release create "$RELEASE_TAG" "$RELEASE_ARCHIVE#Clinder $APP_VERSION macOS arm64" \
      --target "$target" \
      --title "Clinder $APP_VERSION" \
      --notes "Clinder $APP_VERSION macOS arm64 build."
  fi

  echo "Created release asset: $RELEASE_ARCHIVE"
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
  release)
    release_app
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

#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SVG="$ROOT/Assets/AppIcon.svg"
ICONSET="$ROOT/Assets/AppIcon.iconset"
ICNS="$ROOT/Assets/AppIcon.icns"

rm -rf "$ICONSET"
mkdir -p "$ICONSET"

render() {
  local size="$1"
  local scale="$2"
  local pixels=$((size * scale))
  local suffix=""
  if [[ "$scale" -eq 2 ]]; then
    suffix="@2x"
  fi
  rsvg-convert -w "$pixels" -h "$pixels" "$SVG" -o "$ICONSET/icon_${size}x${size}${suffix}.png"
}

render 16 1
render 16 2
render 32 1
render 32 2
render 128 1
render 128 2
render 256 1
render 256 2
render 512 1
render 512 2

iconutil -c icns "$ICONSET" -o "$ICNS"

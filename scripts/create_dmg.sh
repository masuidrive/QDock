#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-}"

if [[ -z "$VERSION" ]]; then
  echo "Usage: $0 <version>"
  echo "Example: $0 1.1.0"
  exit 1
fi

DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/QDock.app"
STAGING_DIR="$DIST_DIR/dmg-root"
DMG_NAME="QDock-v${VERSION}-mac-universal.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"

if [[ ! -d "$APP_DIR" ]]; then
  echo "[dmg] Missing app bundle at $APP_DIR"
  echo "[dmg] Run scripts/build_universal_app.sh first."
  exit 1
fi

echo "[dmg] Preparing staging directory"
rm -rf "$STAGING_DIR" "$DMG_PATH"
mkdir -p "$STAGING_DIR"
cp -R "$APP_DIR" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

echo "[dmg] Creating $DMG_NAME"
hdiutil create \
  -volname "QDock" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

rm -rf "$STAGING_DIR"

echo "[dmg] Created $DMG_PATH"

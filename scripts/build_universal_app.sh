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
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
BUILD_OUTPUT_DIR="$ROOT_DIR/.build/apple/Products/Release"

echo "[build] Cleaning dist directory"
rm -rf "$DIST_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

echo "[build] Building universal binary (arm64 + x86_64)"
swift build -c release --arch arm64 --arch x86_64

if [[ ! -f "$BUILD_OUTPUT_DIR/QDock" ]]; then
  echo "[build] Missing universal binary at $BUILD_OUTPUT_DIR/QDock"
  exit 1
fi

echo "[build] Copying binary and resources into .app bundle"
cp "$BUILD_OUTPUT_DIR/QDock" "$MACOS_DIR/QDock"
chmod +x "$MACOS_DIR/QDock"

if [[ -d "$BUILD_OUTPUT_DIR/QDock_QDock.bundle" ]]; then
  cp -R "$BUILD_OUTPUT_DIR/QDock_QDock.bundle" "$RESOURCES_DIR/"
fi

cp "$ROOT_DIR/QDock/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$ROOT_DIR/QDock/Resources/IconExports/QDock-Premium.icns" "$RESOURCES_DIR/QDock.icns"

BUILD_NUMBER="$(echo "$VERSION" | tr -cd '0-9.')"
if [[ -z "$BUILD_NUMBER" ]]; then
  BUILD_NUMBER="1"
fi

PLIST_BUDDY="/usr/libexec/PlistBuddy"
"$PLIST_BUDDY" -c "Set :CFBundleExecutable QDock" "$CONTENTS_DIR/Info.plist" || \
  "$PLIST_BUDDY" -c "Add :CFBundleExecutable string QDock" "$CONTENTS_DIR/Info.plist"
"$PLIST_BUDDY" -c "Set :CFBundleShortVersionString $VERSION" "$CONTENTS_DIR/Info.plist"
"$PLIST_BUDDY" -c "Set :CFBundleVersion $BUILD_NUMBER" "$CONTENTS_DIR/Info.plist"
"$PLIST_BUDDY" -c "Set :CFBundleIconFile QDock.icns" "$CONTENTS_DIR/Info.plist" || \
  "$PLIST_BUDDY" -c "Add :CFBundleIconFile string QDock.icns" "$CONTENTS_DIR/Info.plist"

echo "[build] Ad-hoc signing app bundle"
codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

echo "[build] Universal app bundle created at $APP_DIR"

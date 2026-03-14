#!/bin/bash
set -e

APP_NAME="ObsidianPilot"
BUILD_DIR=".build/release"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
INSTALL_DIR="/Applications"

echo "=== Building $APP_NAME ==="
swift build -c release 2>&1

echo "=== Creating .app bundle ==="
rm -rf "$APP_BUNDLE"
mkdir -p "$CONTENTS/MacOS"
mkdir -p "$CONTENTS/Resources"

# Copy executable
cp "$BUILD_DIR/$APP_NAME" "$CONTENTS/MacOS/$APP_NAME"

# Copy Info.plist
cp "$APP_NAME/Info.plist" "$CONTENTS/Info.plist"

# Copy app icon
cp "$APP_NAME/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"

# Copy resources (asset catalog)
if [ -d "$BUILD_DIR/ObsidianPilot_ObsidianPilot.bundle" ]; then
    cp -R "$BUILD_DIR/ObsidianPilot_ObsidianPilot.bundle" "$CONTENTS/Resources/"
fi

echo "=== Installing to $INSTALL_DIR ==="
rm -rf "$INSTALL_DIR/$APP_NAME.app"
cp -R "$APP_BUNDLE" "$INSTALL_DIR/"

echo ""
echo "✅ $APP_NAME.app installed to $INSTALL_DIR"
echo "   Launch from Spotlight or Applications folder"
echo "   Menu bar icon: brain.head.profile"

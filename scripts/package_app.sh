#!/bin/zsh

set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
source "$PROJECT_DIR/Config/AppMetadata.sh"
BUILD_VARIANT="${MOSS_BUILD_VARIANT:-debug}"

case "$BUILD_VARIANT" in
    debug)
        BUILD_DIR="$PROJECT_DIR/.build/arm64-apple-macosx/debug"
        APP_DIR="$PROJECT_DIR/dist/Moss.app"
        ;;
    release-universal)
        BUILD_DIR="$PROJECT_DIR/.build/apple/Products/Release"
        APP_DIR="$PROJECT_DIR/dist/release/Moss.app"
        ;;
    *)
        echo "Unknown Moss build variant: $BUILD_VARIANT" >&2
        exit 1
        ;;
esac
CONTENTS_DIR="$APP_DIR/Contents"

cd "$PROJECT_DIR"
if [[ "$BUILD_VARIANT" == "release-universal" ]]; then
    swift build -c release --arch arm64 --arch x86_64
else
    swift build
fi

if [[ "$APP_DIR" != "$PROJECT_DIR/dist/Moss.app" \
    && "$APP_DIR" != "$PROJECT_DIR/dist/release/Moss.app" ]]; then
    echo "Refusing to replace unexpected app path: $APP_DIR" >&2
    exit 1
fi
rm -rf "$APP_DIR"

mkdir -p "$CONTENTS_DIR/MacOS"
mkdir -p "$CONTENTS_DIR/Resources"
cp "$BUILD_DIR/Moss" "$CONTENTS_DIR/MacOS/Moss"
cp "$PROJECT_DIR/Sources/Moss/Resources/moss-reminder.png" "$CONTENTS_DIR/Resources/moss-reminder.png"
cp "$PROJECT_DIR/Sources/Moss/Resources/moss-walk.png" "$CONTENTS_DIR/Resources/moss-walk.png"
cp "$PROJECT_DIR/Sources/Moss/Resources/moss-walk-up.png" "$CONTENTS_DIR/Resources/moss-walk-up.png"
cp "$PROJECT_DIR/Sources/Moss/Resources/moss-walk-down.png" "$CONTENTS_DIR/Resources/moss-walk-down.png"
cp "$PROJECT_DIR/Sources/Moss/Resources/moss-land.png" "$CONTENTS_DIR/Resources/moss-land.png"
cp "$PROJECT_DIR/Sources/Moss/Resources/moss-happy.png" "$CONTENTS_DIR/Resources/moss-happy.png"
cp "$PROJECT_DIR/Sources/Moss/Resources/moss-sleep.png" "$CONTENTS_DIR/Resources/moss-sleep.png"
cp "$PROJECT_DIR/Sources/Moss/Resources/moss-wake.png" "$CONTENTS_DIR/Resources/moss-wake.png"
cp "$PROJECT_DIR/Sources/Moss/Resources/moss-panel-entry.png" "$CONTENTS_DIR/Resources/moss-panel-entry.png"
cp "$PROJECT_DIR/Sources/Moss/Resources/moss-celebrate-hands.png" "$CONTENTS_DIR/Resources/moss-celebrate-hands.png"
cp "$PROJECT_DIR/Sources/Moss/Resources/moss-celebrate-hop.png" "$CONTENTS_DIR/Resources/moss-celebrate-hop.png"
cp "$PROJECT_DIR/Sources/Moss/Resources/moss-celebrate-twirl.png" "$CONTENTS_DIR/Resources/moss-celebrate-twirl.png"
cp "$PROJECT_DIR/Sources/Moss/Resources/moss-celebrate-wand.png" "$CONTENTS_DIR/Resources/moss-celebrate-wand.png"
cp "$PROJECT_DIR/Sources/Moss/Resources/moss-celebrate-leaves.png" "$CONTENTS_DIR/Resources/moss-celebrate-leaves.png"
cp "$PROJECT_DIR/Sources/Moss/Resources/moss-fireworks-cast.png" "$CONTENTS_DIR/Resources/moss-fireworks-cast.png"
cp "$PROJECT_DIR/Sources/Moss/Resources/BoldPixels.ttf" "$CONTENTS_DIR/Resources/BoldPixels.ttf"
cp "$PROJECT_DIR/Sources/Moss/Resources/Moss.icns" "$CONTENTS_DIR/Resources/Moss.icns"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDisplayName</key>
    <string>PLACEHOLDER_DISPLAY_NAME</string>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>Moss</string>
    <key>CFBundleIconFile</key>
    <string>Moss</string>
    <key>CFBundleIdentifier</key>
    <string>com.placeholder.moss</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>PLACEHOLDER_DISPLAY_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.0.0</string>
    <key>CFBundleVersion</key>
    <string>0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSMultipleInstancesProhibited</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>PLACEHOLDER_COPYRIGHT</string>
    <key>NSRemindersFullAccessUsageDescription</key>
    <string>Moss syncs quests with a dedicated list in Apple Reminders.</string>
    <key>NSRemindersUsageDescription</key>
    <string>Moss syncs quests with a dedicated list in Apple Reminders.</string>
</dict>
</plist>
PLIST

plutil -replace CFBundleDisplayName -string "$MOSS_DISPLAY_NAME" "$CONTENTS_DIR/Info.plist"
plutil -replace CFBundleName -string "$MOSS_DISPLAY_NAME" "$CONTENTS_DIR/Info.plist"
plutil -replace CFBundleIdentifier -string "$MOSS_BUNDLE_IDENTIFIER" "$CONTENTS_DIR/Info.plist"
plutil -replace CFBundleShortVersionString -string "$MOSS_MARKETING_VERSION" "$CONTENTS_DIR/Info.plist"
plutil -replace CFBundleVersion -string "$MOSS_BUILD_NUMBER" "$CONTENTS_DIR/Info.plist"
plutil -replace NSHumanReadableCopyright -string "Copyright © 2026 $MOSS_COPYRIGHT_OWNER. All rights reserved." "$CONTENTS_DIR/Info.plist"

codesign --force --sign - "$APP_DIR"

if [[ "$BUILD_VARIANT" == "release-universal" ]]; then
    DSYM_SOURCE="$BUILD_DIR/Moss.dSYM"
    DSYM_DESTINATION="$PROJECT_DIR/dist/release/Moss.dSYM"
    if [[ -d "$DSYM_SOURCE" ]]; then
        rm -rf "$DSYM_DESTINATION"
        cp -R "$DSYM_SOURCE" "$DSYM_DESTINATION"
    fi
fi

echo "$APP_DIR"

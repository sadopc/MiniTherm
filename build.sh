#!/bin/sh
# Builds release binaries and assembles build/MiniTherm.app (menu bar app, no Dock icon).
set -eu
cd "$(dirname "$0")"

swift build -c release
bin=$(swift build -c release --show-bin-path)

app=build/MiniTherm.app
rm -rf build
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/MiniTherm" "$app/Contents/MacOS/MiniTherm"
# the fan-control daemon ships inside the app; the app installs it on request
cp "$bin/minitherm-helper" Resources/local.minitherm.helper.plist Resources/AppIcon.icns "$app/Contents/Resources/"
cp -R Resources/*.lproj "$app/Contents/Resources/"

cat > "$app/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>local.minitherm</string>
    <key>CFBundleName</key><string>MiniTherm</string>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleLocalizations</key><array><string>en</string><string>tr</string></array>
    <key>CFBundleExecutable</key><string>MiniTherm</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
EOF

codesign --force --sign - "$app/Contents/Resources/minitherm-helper"
codesign --force --sign - "$app"
echo "built $app"

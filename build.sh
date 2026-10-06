#!/bin/sh
# Builds release binaries and assembles build/CoreTemp.app (menu bar app, no Dock icon).
set -eu
cd "$(dirname "$0")"

swift build -c release
bin=$(swift build -c release --show-bin-path)

app=build/CoreTemp.app
rm -rf build
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/CoreTemp" "$app/Contents/MacOS/CoreTemp"
# the fan-control daemon ships inside the app; the app installs it on request
cp "$bin/coretemp-helper" Resources/local.coretemp.helper.plist "$app/Contents/Resources/"
cp -R Resources/*.lproj "$app/Contents/Resources/"

cat > "$app/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>local.coretemp</string>
    <key>CFBundleName</key><string>CoreTemp</string>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleLocalizations</key><array><string>en</string><string>tr</string></array>
    <key>CFBundleExecutable</key><string>CoreTemp</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
EOF

codesign --force --sign - "$app/Contents/Resources/coretemp-helper"
codesign --force --sign - "$app"
echo "built $app"

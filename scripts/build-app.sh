#!/bin/bash
# Build dist/LocalSearch.app with only the Command Line Tools (macOS 26 SDK).
set -e
cd "$(dirname "$0")/.."
export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk
swift build -c release
BIN=$(swift build -c release --show-bin-path)
APP=dist/LocalSearch.app
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/LocalSearch" "$BIN/local-search-mcp" "$APP/Contents/MacOS/"
[ -d Resources ] && cp -R Resources/. "$APP/Contents/Resources/" 2>/dev/null || true
cat > "$APP/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.localsearch.LocalSearch</string>
<key>CFBundleName</key><string>Local Search</string>
<key>CFBundleExecutable</key><string>LocalSearch</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PL
codesign --force --sign - --deep "$APP"
echo "Built $APP"

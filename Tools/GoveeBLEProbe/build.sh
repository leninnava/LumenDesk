#!/bin/sh
# Builds GoveeBLEProbe.app. It must be an app bundle with a Bluetooth usage description, or macOS
# kills it on first Bluetooth access.
#
# Run it with `open` so it is its own responsible process for the Bluetooth permission prompt:
#   open -W --stdout /tmp/probe.log --stderr /tmp/probe.log GoveeBLEProbe.app --args H60A1 status
set -e
cd "$(dirname "$0")"
app=GoveeBLEProbe.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
swiftc -O -target "$(uname -m)-apple-macos14.0" main.swift -o "$app/Contents/MacOS/GoveeBLEProbe"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>GoveeBLEProbe</string>
    <key>CFBundleIdentifier</key><string>dev.lumendesk.GoveeBLEProbe</string>
    <key>CFBundleName</key><string>GoveeBLEProbe</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSBackgroundOnly</key><true/>
    <key>NSBluetoothAlwaysUsageDescription</key>
    <string>The probe talks to your Govee light over Bluetooth to test which commands it accepts.</string>
</dict>
</plist>
PLIST
codesign --force --sign - "$app"
echo "built $app"

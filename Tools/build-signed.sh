#!/bin/sh
# Debug build signed with this Mac's Apple Development certificate (fork).
#
# A stable signature keeps macOS's Local Network and Bluetooth permissions across rebuilds;
# unsigned builds count as a new app every time and silently lose them. Signing also turns on
# the App Sandbox. Upstream's team ID stays in the project; this uses yours.
#
# The command-line signing settings apply to every target, so the embedded LumenDeskControls
# extension (Control Center controls and the desktop widget) is signed with the same identity and
# its own entitlements. Both join the App Group "<team ID>.com.lumendesk.LumenDesk", expanded from
# DEVELOPMENT_TEAM; a team-prefixed group on macOS needs no provisioning profile.
set -eo pipefail
cd "$(dirname "$0")/.."

team=$(security find-certificate -c "Apple Development" -p 2>/dev/null \
    | openssl x509 -noout -subject 2>/dev/null \
    | sed -nE 's/.*OU ?= ?([A-Z0-9]{10}).*/\1/p' || true)
if [ -z "$team" ]; then
    echo "No Apple Development certificate found. Add one in Xcode → Settings → Accounts → Manage Certificates." >&2
    exit 1
fi

xcodebuild -project LumenDesk.xcodeproj -scheme LumenDesk -configuration Debug \
    -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath .build/dd \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Apple Development" DEVELOPMENT_TEAM="$team" \
    PROVISIONING_PROFILE_SPECIFIER="" "$@" build | { grep -E "error:|BUILD (SUCCEEDED|FAILED)" || true; }

codesign --verify --deep --strict .build/dd/Build/Products/Debug/LumenDesk.app

echo "open .build/dd/Build/Products/Debug/LumenDesk.app"

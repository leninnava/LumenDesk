#!/bin/sh
# Runs the unit tests (unsigned, separate DerivedData), then unregisters the test build so its
# controls extension doesn't shadow the installed app's. Extra arguments go to xcodebuild,
# e.g. -only-testing:LumenDeskTests/ControlsSnapshotTests.
set -o pipefail
cd "$(dirname "$0")/.."
status=0
xcodebuild -project LumenDesk.xcodeproj -scheme LumenDesk -configuration Debug \
    -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath .build/dd-test \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO "$@" test \
    | { grep -E "error:|' failed|TEST (SUCCEEDED|FAILED)|Executed" || true; } || status=$?
Tools/unregister-build.sh .build/dd-test/Build/Products/Debug/LumenDesk.app
exit $status

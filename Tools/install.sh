#!/bin/sh
# Builds a signed Release copy and installs it as /Applications/LumenDesk.app (fork).
#
# Quits any running LumenDesk first: only one app can own UDP 4002, and the old copy mustn't run
# while it's replaced. The signature matches Tools/build-signed.sh builds, so macOS keeps
# the Local Network and Bluetooth permissions. Turn on Settings → General → "Open LumenDesk at
# login" from the installed copy, so login opens that one.
set -eo pipefail
cd "$(dirname "$0")/.."

Tools/build-signed.sh Release "$@"
app=.build/dd/Build/Products/Release/LumenDesk.app
dest=/Applications/LumenDesk.app
if [ ! -d "$app" ]; then
    echo "The build didn't produce $app." >&2
    exit 1
fi

# Quit every running copy (a Debug build and an installed one can both be running). SIGTERM
# rather than an Apple event, which would ask for Automation permission; settings are saved as
# they change, so nothing is lost.
if pgrep -x LumenDesk >/dev/null; then
    echo "Quitting LumenDesk…"
    pkill -TERM -x LumenDesk || true
    i=0
    while pgrep -x LumenDesk >/dev/null && [ $i -lt 10 ]; do
        sleep 0.5
        i=$((i + 1))
    done
    pkill -KILL -x LumenDesk 2>/dev/null || true
fi

rm -rf "$dest"
ditto "$app" "$dest"
echo "Installed $dest"
echo "Open it with: open $dest"

#!/bin/sh
# Removes a build-folder LumenDesk.app (and its controls extension) from LaunchServices and
# PlugInKit, so only /Applications/LumenDesk.app provides Control Center controls and widgets.
# Usage: Tools/unregister-build.sh path/to/LumenDesk.app [...]
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
for app in "$@"; do
    [ -d "$app" ] || continue
    path=$(cd "$app" && pwd)
    case "$path" in /Applications/*) continue ;; esac
    pluginkit -r "$path/Contents/PlugIns/LumenDeskControls.appex" 2>/dev/null || true
    "$lsregister" -u "$path" 2>/dev/null || true
done

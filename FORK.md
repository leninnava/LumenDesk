# Fork notes

This fork of [SeanPVera/LumenDesk](https://github.com/SeanPVera/LumenDesk) replaces the macOS
interface with standard macOS controls and adds Govee features the original lacks. The protocol and
discovery code (`LumenDesk/Services`) and the light model (`LightManager`) are upstream's and stay
close to it, so upstream changes merge cleanly and protocol fixes can go back as PRs.

## Layout

- `LumenDesk/NativeMac/`: the macOS interface (main window, menu bar extra, Settings). All
  `#if os(macOS)`.
- `LumenDeskApp.swift`: the macOS scenes point at `NativeMac/`. iOS still uses upstream's views.
- Upstream's macOS views are left in the tree but unused, to keep merges small.

## Remotes

- `origin`: `leninnava/LumenDesk` (push here)
- `upstream`: `SeanPVera/LumenDesk` (pull from here, PRs go here)

## Building

The checked-in `LumenDesk.xcodeproj` is hand-maintained. Don't regenerate it with XcodeGen: that
rewrites most of the file and drops the shared scheme. Add new files to `project.pbxproj` by hand
(the fork's IDs use the `F7`/`F8`/`F9` prefixes).

```sh
Tools/build-signed.sh            # Debug; `Tools/build-signed.sh Release` for Release
open .build/dd/Build/Products/Debug/LumenDesk.app
```

`Tools/install.sh` builds a signed Release copy, quits any running LumenDesk and replaces
`/Applications/LumenDesk.app`. Turn on Settings → General → "Open LumenDesk at login" from that
copy so login opens the installed one.

`build-signed.sh` signs with this Mac's Apple Development certificate (a free Apple ID works; add
it in Xcode → Settings → Accounts → Manage Certificates). Keep builds signed: macOS ties Local
Network and Bluetooth permission to the signature, and an unsigned build counts as a new app on
every rebuild, so lights silently stop answering even though the permission switch shows on. If
the certificate shows as invalid, install Apple's WWDR G3 intermediate
(`https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer`).

Signed builds run in the App Sandbox, so settings live in
`~/Library/Containers/com.lumendesk.LumenDesk`, separate from any earlier unsigned run.

## Shortcuts, Siri and Control Center

- **App Intents** (`LumenDesk/Intents/`, macOS 13+ and iOS): lights, rooms and scenes as entities;
  turn a light, room or all lights on/off/toggle, set light or room brightness, apply a scene;
  App Shortcuts phrases for Siri and Spotlight. They run in the app's process and reach the same
  `LightManager` as the windows through `AppServices.shared`. A cold launch waits up to 4 s for
  lights to be rediscovered. They skip the app's confirmation alerts, which a Shortcut can't answer.
- **LumenDeskControls** (`LumenDeskControls/`, macOS 26+ only): an "All Lights" control, a
  per-room control (pick the room when adding it) and a Rooms desktop widget. The extension only
  draws; its toggles run intents from `LumenDesk/Shared/` that the system performs in the app
  (`ForegroundContinuableIntent` on macOS 26, `allowedExecutionTargets = .main` on 27). The app
  writes room/all-lights state to the App Group `<team ID>.com.lumendesk.LumenDesk`
  (`NativeControlsBridge`) and reloads the controls when it changes. Team-prefixed groups need no
  provisioning profile, so `Tools/build-signed.sh` signs both with the free team as before.
- Xcode registers every build it makes with LaunchServices, so a build in another folder can show
  up as a second LumenDesk in the controls gallery. Remove stale copies with
  `pluginkit -r <path>/LumenDesk.app/Contents/PlugIns/LumenDeskControls.appex`.

## Mac integration

- **Open at login** (Settings → General) uses `SMAppService.mainApp`. Services start from the menu
  bar icon too, so a login launch works even when the main window stays closed.
- **Shortcuts** (Settings → Shortcuts) are Carbon hot keys: no Accessibility permission, and they
  work in the sandbox. A combination needs ⌘, ⌥ or ⌃ (⌘ alone is refused); one another app
  registered first can't be taken and is flagged.
- **Automations** (Settings → Automations) turn lights off on sleep or screen lock and restore the
  ones they turned off once the Mac is awake and unlocked. Sleep is held for 3 s through IOKit's
  power notifications so the commands leave first; if that registration fails, only
  `NSWorkspace.willSleepNotification` remains and macOS doesn't wait. Restores wait 5 s after
  wake and for a network (up to 30 s more), because Wi-Fi rejoins after the wake notification.
  Display sleep alone doesn't count; locking and switching users do.
- **Release Bluetooth lights when idle** (Settings → General, off by default) closes
  Bluetooth-only lights' links after 1, 5 or 15 minutes without a command so the Govee app can
  connect; the next command reconnects. Status polling doesn't reopen a released link, so the
  light's state isn't refreshed until then.

## What we learned on real hardware

- **Govee H60A1 (12" RGBWW + RGBIC ceiling light) ignores `ptReal` over LAN.** Power-off sent as
  a `ptReal` frame (`33 01 00`) left the light on, so scenes and segment colours, which are `ptReal`
  frames, do nothing over Wi-Fi. Plain LAN commands (`turn`, `brightness`, `colorwc`, `devStatus`)
  work.
- **The H60A1 accepts the same frames over Bluetooth** (checked with `Tools/GoveeBLEProbe`):
  - It advertises as `GVH60A1XXXX` and needs the legacy encrypted session (AES-ECB + RC4,
    handshake `e7 01` / `e7 02`); plain frames get no reply.
  - Power (`33 01`), brightness (`33 04`, 0–100) and status queries (`aa 01/04/05`) work.
  - Ring segments: `33 05 15 01 r g b 00×5 <mask, 3 bytes LE>`, **13 segments, bits 0–12**. Bits
    13–19 do nothing. The main panel is not in the mask; it follows the plain colour/white commands.
  - Scenes: the `a3` upload frames plus `33 05 04 <code LE>` from Govee's public scene library;
    the light reports `aa 05 04 <code>` afterwards.
  - It advertises intermittently (gaps over 30 s), so keep one connection open with a keep-alive
    instead of connecting per command. Scan with duplicates allowed, or a device whose first
    advert lacks a name is never matched.
  - Its Bluetooth name ends one higher than its Wi-Fi device ID (`…CACF` vs `…CA:CE`), which is how
    to pair the two transports.
  - Right after a Bluetooth session, the first LAN command can be ignored; retry it.
- **A full-tunnel VPN swallows Govee discovery.** With a VPN route for `224.0.0.0/4` through
  `utun`, the multicast scan never reaches Wi-Fi unless the socket is pinned to the LAN interface
  (`IP_MULTICAST_IF`). Upstream already pins per interface and skips `utun`/`ipsec`.
- **First launch can mark lights offline.** Replies that arrive while macOS's "allow incoming
  connections" prompt is still open are dropped; the light stays "Not responding" until a rescan or
  relaunch.
- Only one app can own UDP 4002. Quit other Govee LAN tools (Home Assistant, govee2mqtt, HomeBar)
  before running LumenDesk.

## Security

Reviewed 2026-10-15 (findings F1–F12). Fixed in the fork, not yet proposed upstream:

- **F1 (High, upstream code):** a Govee scan reply's `ip` text went to `NSLog` as its format
  string, so one UDP packet from anyone on the LAN crashed the app. Now passed as an argument.
- **F2:** a LAN reply with a `ble:` device ID could create a Bluetooth-only light and make the app
  connect to any nearby peripheral by that name. Govee device IDs must now be MAC-style,
  Bluetooth-only status also requires the `Bluetooth` address, and the Bluetooth controller
  refuses names that weren't paired.
- **F3/F5:** discovery (multicast, broadcast and a unicast sweep of the subnet) and 30-second
  polling ran on every network, including Nanoleaf requests that carry its token in the URL.
  LumenDesk now does this only on networks the user marked as home (Settings → Network); a manual
  scan still works anywhere. Networks are recognised by subnet, router IP and the router's MAC,
  which configd publishes in `State:/Network/Service/<id>/IPv4` (`ARPResolvedHardwareAddress`)
  and a sandboxed app can read without Location access; the kernel's ARP and neighbour tables
  only return `02:00:00:00:00:00` to apps. A home saved before this matches on subnet and router
  IP and takes the MAC the first time it matches; after that a different or missing MAC is not
  home.
- **F4:** scene parameters over ~4 KB crashed frame encoding. Parameters over 2 KB, responses over
  2 MB and catalogues over 500 scenes are now rejected.
- **F5 (Nanoleaf):** off a home network the Nanoleaf client sends nothing to a saved controller:
  queued and in-flight requests are dropped, streams end, event-stream listeners stop, and a
  rescan only browses Bonjour. Coming home refreshes each controller and listens again.
- **F6:** Govee scan replies are accepted only for 15 s after a scan, so unsolicited replies can't
  add lights or move an existing light to another address.
- **F7:** Bluetooth lights are bound to the peripheral identifier recorded at pairing (lights
  paired earlier bind on first connection), advert names must match Govee's naming schemes, the
  peripheral and pairing lists are capped, and reconnects after a failure wait 5 s.
- **F8:** the UDP receive loop handles at most 64 datagrams per wake-up. LIFX replies must carry
  the client's own (non-zero) source, only a `StateService` reply introduces a device, and the
  target maps hold at most 256 devices, oldest evicted first.
- **F11:** removed `com.apple.security.device.midi`, which isn't an App Sandbox entitlement (the
  sandbox profile allows CoreMIDI's `com.apple.midiserver` to every app).
- **F12:** `build-signed.sh` now fails when the build fails.

Still open: the home check trusts a MAC the LAN can spoof, and a home saved before the MAC was
read takes whichever router it next matches on subnet and router IP.

## Plan

1. Native macOS interface and a working menu bar extra. *(done)*
2. Govee over Bluetooth: scenes and segments for models that ignore `ptReal` on LAN (H60A1). *(done)*
3. Govee cloud API as a fallback, only if a model works over neither LAN nor Bluetooth.

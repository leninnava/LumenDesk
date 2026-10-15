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
xcodebuild -project LumenDesk.xcodeproj -scheme LumenDesk -configuration Debug \
  -destination "platform=macOS" -derivedDataPath .build/dd \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
open .build/dd/Build/Products/Debug/LumenDesk.app
```

Unsigned builds run without the App Sandbox (entitlements are only applied when signed).

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

## Plan

1. Native macOS interface and a working menu bar extra. *(done)*
2. Govee over Bluetooth: scenes and segments for models that ignore `ptReal` on LAN (H60A1).
3. Govee cloud API as a fallback, only if a model works over neither LAN nor Bluetooth.

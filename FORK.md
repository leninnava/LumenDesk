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
  work. Govee's cloud API lists scenes and 13 segments for this model; Bluetooth is untested.
- **A full-tunnel VPN swallows Govee discovery.** With a VPN route for `224.0.0.0/4` through
  `utun`, the multicast scan never reaches Wi-Fi unless the socket is pinned to the LAN interface
  (`IP_MULTICAST_IF`). Upstream already pins per interface and skips `utun`/`ipsec`.
- **First launch can mark lights offline.** Replies that arrive while macOS's "allow incoming
  connections" prompt is still open are dropped; the light stays "Not responding" until a rescan or
  relaunch.
- Only one app can own UDP 4002. Quit other Govee LAN tools (Home Assistant, govee2mqtt, HomeBar)
  before running LumenDesk.

## Plan

1. Native macOS interface and a working menu bar extra. *(in progress)*
2. Govee cloud API: API key in Settings (Keychain), scenes, segments for cloud-only models such as
   the H60A1.
3. Bluetooth fallback for scenes and segments, if the H60A1 accepts them over BLE.

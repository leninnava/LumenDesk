# Upstream suggestions

Fixes and proposals for [SeanPVera/LumenDesk](https://github.com/SeanPVera/LumenDesk) found while
building this fork. Upstream conventions: an issue first for anything beyond a clear bug, plain
imperative PR titles, a Validation section, fixes applied to both the native app and the web
bridge (`web/bridge`), sequential `A1…`/`B1…` project IDs, README updated when behaviour changes.
Verify each item against current `upstream/main` before filing; drafts live in
`~/Projects/LumenDesk-upstream-drafts/`.

## Filed

| Item | Issue | PR | Status |
|---|---|---|---|
| Crafted Govee scan reply crashes the app (NSLog format string) | #142 | #143 | Open, awaiting review |

## Bugs (issue, then a small PR)

1. **Unsolicited and invalid Govee scan replies.** Any host can send a scan reply at any time; IDs
   aren't validated, and a reply with an existing ID moves that light to the sender's address.
   Fork fix: MAC-style ID check, accept scan replies only for 15 s after a scan. Needs the same in
   `web/bridge/src/govee.js`. The scan window touches CLAUDE.md's "notify on every discovery
   response" rule, so discuss first. (Fork: `fix(security): harden LAN and Bluetooth input`.)
2. **LIFX replies from other clients and unbounded maps.** Replies with `source == 0` (or not our
   source) are accepted, and every parsed packet's target is added to `macByTarget`/`targetsByMac`.
   Fork fix: `LIFXReplyFilter` (our source only, only `StateService` adds devices, cap 256).
3. **UDP drain loop can be flooded.** `UDPSocket.drain()` loops until the socket is empty; bound it
   (the read source is level-triggered). One-line change.
4. **`com.apple.security.device.midi` isn't a real entitlement.** Not in Xcode's entitlement
   definitions or the sandbox profile; CoreMIDI works sandboxed without it. Remove it.
5. **First launch: Govee lights stay "Not responding".** Replies are dropped while macOS's "accept
   incoming connections" prompt is open; lights go stale and only a rescan recovers. Draft:
   `issue-first-launch-stale.md`.
6. **Menu bar icon invisible and unclickable** (the `LumenMark` label in `MenuBarExtra`). Re-check
   against current Spectrum Studio before filing.
7. **Unsigned dev builds silently lose Local Network permission.** CLAUDE.md's build commands use
   `CODE_SIGNING_ALLOWED=NO`; each rebuild counts as a new app for Local Network privacy and the
   firewall, so lights stop answering with the permission switch shown as on. Docs note, or a
   signing option.

## Engine API issues (found building native screens)

8. **Sunrise/sunset schedules are fixed actions.** `atSunrise` always turns lights on and
   `atSunset` always off, so "dim to 25% at sunset" can't be expressed. Suggest a trigger
   (time / sunrise / sunset + offset) separate from the action.
9. **Schedule ordering drifts.** `addSchedule` sorts a room's schedules by time; `updateSchedule`
   and `duplicateSchedule` don't. `duplicateSchedule` also fails silently at the per-room limit.
10. **Schedule delete has no confirmation or undo**, unlike scenes and rooms.
11. **Scene delete persists only by side effect.** `performDeleteScene` doesn't save; the change
    reaches disk because `reconcileFavoriteOrder()` happens to save.
12. **`animatingEffect(for:)` reads unpublished state**, so views update only because
    `activeEffects` changes at the same time.
13. **`LightManager.maximumSchedulesPerRoom` is main-actor-isolated**, so pure validation code
    can't read it without a Swift 6 warning; make it `nonisolated static let`.
14. **Stale comment:** `Room.schedules` says "Up to 4 per room"; the limit is 12.
15. **Music Mode is an effect with a magic ID** (`music-pulse` through `startEffect`), so effect
    lists must filter it by ID.

## Network behaviour (discussion issue)

16. **Discovery and polling run on every network.** Each launch multicasts, broadcasts and
    unicast-sweeps the whole /24 for Govee and LIFX (over 1,000 datagrams; looks like a port scan
    to office IDS), and saved Nanoleaf controllers are polled with the token in the URL wherever
    the Mac is. Fork approach: home networks recognised by subnet, router IP and router MAC
    (configd `ARPResolvedHardwareAddress`); off-home, no automatic scans, polling or Nanoleaf
    traffic. Offer as an idea, not a PR — the UI is fork-specific.

## Hardware findings (information issue)

17. **Govee H60A1 ignores `ptReal` over LAN** (even `33 01 00`); segments and scenes work over
    Bluetooth (encrypted session; 13 ring segments, bits 0–12; main panel not in the mask). Not in
    `GoveeSegmentProfile`, so Segment Studio silently does nothing. Draft: `issue-h60a1-ptreal.md`.

## Feature proposals (ask before porting)

18. **Govee Bluetooth transport**: scenes and segments for models that ignore LAN `ptReal`, and
    full control of Bluetooth-only lights (H6008), with manual pairing bound to the peripheral.
    Large; also needs iOS and their UI.
19. **Govee scene library** (Govee's public catalogue, cached). Downloads from Govee's servers,
    which conflicts with the project's local-first stance — likely fork-only.

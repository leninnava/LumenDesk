# LumenDesk for Mac

A Mac-native controller for the smart lights in your home. It talks to LIFX and Govee lights
directly, over your Wi-Fi or Bluetooth, with no accounts or cloud, and puts them where macOS puts
everything else: Control Center, widgets, Shortcuts, Siri and the keyboard.

This is a fork of [LumenDesk](https://github.com/SeanPVera/LumenDesk) by SeanPVera. It keeps
LumenDesk's lighting engine and replaces the Mac interface with one built from standard macOS
controls. The iOS app is upstream's, unchanged.

## What it does

**A native app**
- An **Overview** that opens on what you need right now: how many lights are on, Turn All On/Off,
  rooms with one switch and a brightness slider each, and Add Light.
- Rooms, lights, saved scenes, effects, Music Mode and schedules, in a standard sidebar window
  with Settings, light and dark mode, and VoiceOver labels.
- Lights shown as tiles or a list; rooms name new lights after themselves ("Living Room Bulb").

**Part of macOS**
- **Control Center** controls for all lights, a room or a single light, and desktop **widgets**
  for rooms and a room's lights. Or a menu bar icon instead, if you prefer (Settings → General).
- **Shortcuts, Siri and Spotlight** actions: turn a light, room or everything on or off, set
  brightness, apply a scene.
- **Keyboard shortcuts** that work from any app, without Accessibility permission.
- **Automations**: lights off when the Mac sleeps or the screen locks, and back on afterwards.
- Opens at login.

**Lights**
- **LIFX** over Wi-Fi.
- **Govee** over Wi-Fi (with LAN Control turned on in the Govee Home app) and over **Bluetooth**,
  including Govee's scenes and per-segment colour for models that only accept them over Bluetooth
  (such as the H60A1 ceiling light), and bulbs with no Wi-Fi control at all (such as the H6008).
- **Nanoleaf** Shapes and Aurora are supported by the engine; the Mac interface doesn't pair them
  yet.

**Private by default**
- Everything runs on your local network. The only internet request is Govee's public scene list,
  downloaded once per model and cached.
- LumenDesk searches for lights on its own only on networks you mark as home, and connects over
  Bluetooth only to lights you added.

## Requirements

- macOS 13 or later. Control Center controls and widgets need macOS 26 or later.
- To build: Xcode 26 and an Apple Development certificate (a free Apple ID works; add one in
  Xcode → Settings → Accounts → Manage Certificates).

## Install

```sh
Tools/install.sh
```

It builds a signed Release copy and installs it as `/Applications/LumenDesk.app`. On first launch,
allow Local Network, Bluetooth and incoming connections, then mark your network as home when
LumenDesk asks.

## Develop

- `Tools/build-signed.sh` builds a signed Debug copy; `Tools/test.sh` runs the unit tests.
- [FORK.md](FORK.md) explains the fork's layout, what we learned on real hardware, and the
  security review.
- [UPSTREAM.md](UPSTREAM.md) lists fixes we've offered, or plan to offer, back to LumenDesk.
- Upstream's full feature reference is in [README-upstream.md](README-upstream.md).

## Attributions

LumenDesk for Mac stands on other people's work:

- **[LumenDesk](https://github.com/SeanPVera/LumenDesk)** by SeanPVera (MIT): the whole lighting
  engine (discovery, LIFX/Govee/Nanoleaf protocols, scenes, effects, Music Mode, schedules,
  persistence), the iOS app and the web client. This fork's changes are the Mac interface, the
  macOS integrations and the Govee Bluetooth support.
- **[Govee Mac](https://github.com/maxrross/goveemac)** by the Govee Mac contributors (MIT): the
  Govee Bluetooth frame format and legacy encrypted-session handshake are adapted from it.
- **[Govee-Sync](https://github.com/Didilusse/Govee-Sync)** by Adil Rahmani (MIT) and
  **[govee-ble-segments](https://github.com/mpalczew/govee-ble-segments)** (MIT): the Bluetooth
  packet framing and session protocol that Govee Mac builds on.
- **[govee2mqtt](https://github.com/wez/govee2mqtt)** by Wez Furlong (MIT): Govee scene encoding
  and the public scene-library endpoint; its test vectors are in our tests.
- **[Govee integration for Home Assistant](https://github.com/lasswellt/govee-homeassistant)**
  (MIT): its protocol reference documented the segment colour packet and the H60A1's capabilities.
- **[Govee reverse-engineering notes](https://github.com/egold555/Govee-Reverse-Engineering)**:
  background on Govee's protocols (read, not copied).
- **Tanner Helland**: the colour-temperature-to-RGB approximation used for Bluetooth white light.
- Upstream LumenDesk itself credits OpenRGB, govee2mqtt and homebridge-govee for parts of its
  Govee LAN support.

License notices for adapted code are in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

LIFX, Govee and Nanoleaf are trademarks of their owners. This project isn't affiliated with or
endorsed by them, or by SeanPVera's LumenDesk.

## License

MIT, as upstream. See [LICENSE](LICENSE).

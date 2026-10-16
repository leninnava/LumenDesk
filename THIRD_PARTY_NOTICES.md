# Third-party notices

LumenDesk for Mac is a fork of LumenDesk (MIT, Copyright (c) 2026 SeanPVera; see LICENSE). It
also adapts code or protocol details from the projects below, each under the MIT License:

| Project | Copyright | Used for |
|---|---|---|
| [Govee Mac](https://github.com/maxrross/goveemac) | Copyright (c) 2026 Govee Mac contributors | Govee Bluetooth frames and legacy session handshake (`GoveeBluetoothProtocol.swift`, `Tools/GoveeBLEProbe`) |
| [Govee-Sync](https://github.com/Didilusse/Govee-Sync) | Copyright (c) 2025 Adil Rahmani | Bluetooth packet framing, via Govee Mac |
| [govee-ble-segments](https://github.com/mpalczew/govee-ble-segments) | Copyright (c) 2026 (as stated in its license) | Legacy encrypted session protocol, via Govee Mac |
| [govee2mqtt](https://github.com/wez/govee2mqtt) | Copyright (c) 2024-Present Wez Furlong | Scene encoding and test vectors, scene-library endpoint |
| [Govee integration for Home Assistant](https://github.com/lasswellt/govee-homeassistant) | Copyright (c) 2021 Florian Lagg (@LaggAt) | Segment colour packet format and H60A1 capability data (documentation) |

The MIT License, which applies to each project above:

> Permission is hereby granted, free of charge, to any person obtaining a copy of this software
> and associated documentation files (the "Software"), to deal in the Software without
> restriction, including without limitation the rights to use, copy, modify, merge, publish,
> distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the
> Software is furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in all copies or
> substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING
> BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
> NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
> DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
> OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

The colour-temperature-to-RGB approximation follows Tanner Helland's published algorithm.

import CommonCrypto
import Foundation

/// Govee's Bluetooth control protocol (fork). The 20-byte frames are the same ones the LAN
/// `ptReal` command relays (see `GoveeProtocol.blePacket`); some models, such as the H60A1
/// ceiling light, only obey them over Bluetooth.
///
/// Frame layout and the legacy encrypted session follow goveemac (MIT,
/// github.com/maxrross/goveemac), which credits Govee-Sync by Adil Rahmani (MIT) and
/// mpalczew/govee-ble-segments (MIT). Scene encoding follows govee2mqtt (MIT, wez/govee2mqtt).
enum GoveeBluetoothProtocol {
    static let serviceUUID = "00010203-0405-0607-0809-0A0B0C0D1910"
    static let controlUUID = "00010203-0405-0607-0809-0A0B0C0D2B11"
    static let notifyUUID = "00010203-0405-0607-0809-0A0B0C0D2B10"

    /// Models whose firmware ignores `ptReal` over LAN but accepts the same frames over
    /// Bluetooth, so scenes and segments have to go through Bluetooth.
    static let framesOnlyOverBluetooth: Set<String> = ["H60A1"]

    /// Ring segments addressable with the segment-colour frame, for models where the LAN
    /// segment catalogue doesn't apply.
    static let bluetoothSegmentCounts: [String: Int] = ["H60A1": 13]

    // MARK: Frames

    /// Power, brightness and mode queries; the light answers each with an `aa …` frame.
    static let statusQueries: [[UInt8]] = [0x01, 0x04, 0x05].map { GoveeProtocol.blePacket([0xAA, $0]) }
    static let keepAlive = GoveeProtocol.blePacket([0xAA, 0x01])
    static let sessionHello = GoveeProtocol.blePacket([0xE7, 0x01])
    static let sessionFinish = GoveeProtocol.blePacket([0xE7, 0x02])

    /// Colour for the segments in `segments` (0-based).
    static func segmentColorFrame(_ rgb: (r: Int, g: Int, b: Int), segments: [Int]) -> [UInt8] {
        GoveeProtocol.segmentColorPacket(r: rgb.r, g: rgb.g, b: rgb.b, segments: segments)
    }

    /// Largest scene parameter accepted. Real ones are a few hundred bytes (H60A1's largest is
    /// 211); the line counter is one byte, so anything near 4 KB can't be encoded at all.
    static let maxSceneParamBytes = 2048

    /// A scene from Govee's scene library: its parameter uploaded as `a3` lines, then the
    /// scene code selected with `33 05 04`. Empty when the parameter is too large to send.
    static func sceneFrames(code: UInt16, param: Data) -> [[UInt8]] {
        guard param.count <= maxSceneParamBytes else { return [] }
        let select = GoveeProtocol.blePacket([0x33, 0x05, 0x04, UInt8(code & 0xFF), UInt8(code >> 8)])
        guard !param.isEmpty else { return [select] }

        var data: [UInt8] = [0xA3, 0x00, 0x01, 0x00 /* line count */, 0x02]
        var lines: UInt8 = 0
        var lastLineMarker = 1
        for byte in param {
            if data.count % 19 == 0 {
                lines += 1
                data.append(0xA3)
                lastLineMarker = data.count
                data.append(lines)
            }
            data.append(byte)
        }
        data[lastLineMarker] = 0xFF  // the last line is numbered 0xff
        data[3] = lines + 1

        let uploads = stride(from: 0, to: data.count, by: 19).map {
            GoveeProtocol.blePacket(Array(data[$0..<min($0 + 19, data.count)]))
        }
        return uploads + [select]
    }

    // MARK: Basic control (lights reachable only over Bluetooth)

    // Checked on the H6008 bulb: colour mode 0x0d, brightness 0–100, no session encryption.

    static func powerFrame(on: Bool) -> [UInt8] {
        GoveeProtocol.blePacket([0x33, 0x01, on ? 1 : 0])
    }

    static func brightnessFrame(percent: Int) -> [UInt8] {
        GoveeProtocol.blePacket([0x33, 0x04, UInt8(min(max(percent, 1), 100))])
    }

    static func colorFrame(r: Int, g: Int, b: Int) -> [UInt8] {
        GoveeProtocol.blePacket([0x33, 0x05, 0x0D, clamp(r), clamp(g), clamp(b)])
    }

    /// White at a colour temperature: the RGB the bulb should approximate, then kelvin (big-endian).
    static func whiteFrame(kelvin: Int) -> [UInt8] {
        let k = min(max(kelvin, 2000), 9000)
        let rgb = rgb(forKelvin: k)
        return GoveeProtocol.blePacket([0x33, 0x05, 0x0D, clamp(rgb.r), clamp(rgb.g), clamp(rgb.b),
                                        UInt8(k >> 8), UInt8(k & 0xFF)])
    }

    /// Approximate RGB of a black-body colour temperature (Tanner Helland's fit).
    static func rgb(forKelvin kelvin: Int) -> (r: Int, g: Int, b: Int) {
        let t = Double(kelvin) / 100
        let r = t <= 66 ? 255 : 329.698727446 * pow(t - 60, -0.1332047592)
        let g = t <= 66 ? 99.4708025861 * log(t) - 161.1195681661 : 288.1221695283 * pow(t - 60, -0.0755148492)
        let b = t >= 66 ? 255 : (t <= 19 ? 0 : 138.5177312231 * log(t - 10) - 305.0447927307)
        return (Int(r.rounded()), Int(g.rounded()), Int(b.rounded()))
    }

    private static func clamp(_ value: Int) -> UInt8 { UInt8(min(max(value, 0), 255)) }

    // MARK: Replies

    enum Reply: Equatable {
        case power(Bool)
        case brightness(Int)
        case mode([UInt8])
    }

    /// Colour or white reported in a `0d` mode reply (`aa 05 0d r g b k_hi k_lo`).
    static func colorState(fromMode mode: [UInt8]) -> (r: Int, g: Int, b: Int, kelvin: Int)? {
        guard mode.count >= 6, mode[0] == 0x0D else { return nil }
        return (Int(mode[1]), Int(mode[2]), Int(mode[3]), Int(mode[4]) << 8 | Int(mode[5]))
    }

    static func parse(_ frame: [UInt8]) -> Reply? {
        guard frame.count >= 3, frame[0] == 0xAA else { return nil }
        switch frame[1] {
        case 0x01: return .power(frame[2] == 1)
        case 0x04: return .brightness(Int(frame[2]))
        case 0x05: return .mode(Array(frame[2...]))
        default: return nil
        }
    }

    // MARK: Matching a Bluetooth advert to a LAN light

    /// Splits an advert name such as `GVH60A1ABCE` or `ihoment_H6008_3C4D` into the model and
    /// the two-byte suffix taken from the device's MAC address.
    static func parseName(_ name: String) -> (sku: String, suffix: UInt16)? {
        let upper = name.uppercased()
        // Anchored: only Govee's own naming schemes, not any name that happens to end like one.
        guard let match = upper.range(of: #"^(GV|IHOMENT_|GOVEE_)H[0-9A-F]{4}_?[0-9A-F]{4}$"#,
                                      options: .regularExpression) else {
            return nil
        }
        let token = upper[match].replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "IHOMENT", with: "").replacingOccurrences(of: "GOVEE", with: "")
            .replacingOccurrences(of: "GV", with: "")
        guard let suffix = UInt16(token.suffix(4), radix: 16) else { return nil }
        return (String(token.prefix(5)), suffix)
    }

    /// Whether a Bluetooth advert belongs to the LAN light with this SKU and device ID
    /// (`0E:60:12:34:56:78:AB:CD`). The Bluetooth MAC is usually the Wi-Fi MAC plus one.
    static func advertName(_ name: String, matchesSKU sku: String?, deviceID: String) -> Bool {
        guard let sku, let advert = parseName(name), advert.sku == sku.uppercased() else { return false }
        let bytes = deviceID.split(separator: ":").compactMap { UInt8($0, radix: 16) }
        guard bytes.count >= 2 else { return false }
        let wifiSuffix = UInt16(bytes[bytes.count - 2]) << 8 | UInt16(bytes[bytes.count - 1])
        return advert.suffix == wifiSuffix || advert.suffix == wifiSuffix &+ 1
    }
}

/// Govee's legacy Bluetooth session: AES-128-ECB over the first 16 bytes of a frame and RC4,
/// freshly keyed per frame, over the last 4. The handshake uses a fixed key; the light then
/// hands out the session key.
struct GoveeSessionCipher {
    static let handshake = GoveeSessionCipher(key: Array("MakingLifeSmarte".utf8))!

    private let key: [UInt8]

    init?(key: [UInt8]) {
        guard key.count == 16 else { return nil }
        self.key = key
    }

    func encrypt(_ frame: [UInt8]) -> [UInt8]? { transform(frame, decrypt: false) }
    func decrypt(_ frame: [UInt8]) -> [UInt8]? { transform(frame, decrypt: true) }

    private func transform(_ frame: [UInt8], decrypt: Bool) -> [UInt8]? {
        guard frame.count == 20 else { return nil }
        var head = [UInt8](repeating: 0, count: 16)
        var moved = 0
        let status = CCCrypt(CCOperation(decrypt ? kCCDecrypt : kCCEncrypt), CCAlgorithm(kCCAlgorithmAES),
                             CCOptions(kCCOptionECBMode), key, 16, nil, Array(frame.prefix(16)), 16,
                             &head, 16, &moved)
        guard status == kCCSuccess, moved == 16 else { return nil }

        var state = Array(0..<256)
        var j = 0
        for i in 0..<256 {
            j = (j + state[i] + Int(key[i % 16])) & 255
            state.swapAt(i, j)
        }
        var i = 0
        j = 0
        let tail = frame.suffix(4).map { byte -> UInt8 in
            i = (i + 1) & 255
            j = (j + state[i]) & 255
            state.swapAt(i, j)
            return byte ^ UInt8(state[(state[i] + state[j]) & 255])
        }
        return head + tail
    }
}

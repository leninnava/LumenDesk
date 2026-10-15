// Govee Bluetooth probe: connects to one Govee light and sends a single command, logging every
// reply. Used to find out what a model accepts over Bluetooth before building it into the app.
//
// Frame format and the legacy encrypted session follow goveemac (MIT, github.com/maxrross/goveemac),
// which credits Govee-Sync by Adil Rahmani (MIT) and mpalczew/govee-ble-segments (MIT).
//
// usage: GoveeBLEProbe <name-filter> <command> [args]
//   status                      query power (aa 01), brightness (aa 04), mode (aa 05)
//   power on|off
//   color rrggbb                manual colour (33 05 02 r g b)
//   segment <mask-hex> rrggbb   segment colour (33 05 15 01 r g b 0*5 mask-lo mask-hi)
//   raw <hex bytes...>          one frame, padded and checksummed
//   frames <hex> <hex>…         several frames in one connection, e.g. 330515 01ff0000…
//   scene <code> <base64>       scene upload (a3 …) then select (33 05 04)
import CommonCrypto
import CoreBluetooth
import Foundation

let serviceID = CBUUID(string: "00010203-0405-0607-0809-0a0b0c0d1910")
let controlID = CBUUID(string: "00010203-0405-0607-0809-0a0b0c0d2b11")
let notifyID = CBUUID(string: "00010203-0405-0607-0809-0a0b0c0d2b10")

let started = Date()
func log(_ message: String) {
    print(String(format: "[%6.2f] ", Date().timeIntervalSince(started)) + message)
    fflush(stdout)
}

func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined(separator: " ") }

func frame(_ bytes: [UInt8]) -> Data {
    var f = Array(bytes.prefix(19))
    f += [UInt8](repeating: 0, count: 19 - f.count)
    return Data(f + [f.reduce(0, ^)])
}

func sceneFrames(code: UInt16, param: Data) -> [Data] {
    let select = frame([0x33, 0x05, 0x04, UInt8(code & 0xFF), UInt8(code >> 8)])
    guard !param.isEmpty else { return [select] }
    var data: [UInt8] = [0xA3, 0x00, 0x01, 0x00, 0x02]
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
    data[lastLineMarker] = 0xFF
    data[3] = lines + 1
    return stride(from: 0, to: data.count, by: 19).map { frame(Array(data[$0..<min($0 + 19, data.count)])) }
        + [select]
}

/// AES-128-ECB over the first 16 bytes, RC4 over the last 4 (Govee's legacy session transport).
struct SessionCipher {
    static let auth = SessionCipher(key: Data("MakingLifeSmarte".utf8))
    let key: Data

    func encrypt(_ p: Data) -> Data? { transform(p, decrypt: false) }
    func decrypt(_ p: Data) -> Data? { transform(p, decrypt: true) }

    private func transform(_ packet: Data, decrypt: Bool) -> Data? {
        guard packet.count == 20, key.count == 16 else { return nil }
        var out = [UInt8](repeating: 0, count: 16)
        var moved = 0
        let status = key.withUnsafeBytes { k in
            packet.withUnsafeBytes { input in
                CCCrypt(CCOperation(decrypt ? kCCDecrypt : kCCEncrypt), CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionECBMode), k.baseAddress, 16, nil, input.baseAddress, 16, &out, 16, &moved)
            }
        }
        guard status == kCCSuccess else { return nil }
        let keyBytes = [UInt8](key)
        var s = Array(0..<256)
        var j = 0
        for i in 0..<256 {
            j = (j + s[i] + Int(keyBytes[i % 16])) & 255
            s.swapAt(i, j)
        }
        var i = 0
        j = 0
        let tail = packet.suffix(4).map { byte -> UInt8 in
            i = (i + 1) & 255
            j = (j + s[i]) & 255
            s.swapAt(i, j)
            return byte ^ UInt8(s[(s[i] + s[j]) & 255])
        }
        return Data(out) + Data(tail)
    }
}

final class Probe: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    let filter: String
    let commands: [Data]
    var central: CBCentralManager!
    var peripheral: CBPeripheral?
    var control: CBCharacteristic?
    var session: SessionCipher?
    var sentCommands = false
    var seen = Set<String>()
    var scanOnly: Bool { filter == "*" }

    init(filter: String, commands: [Data]) {
        self.filter = filter.lowercased()
        self.commands = commands
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        log("Bluetooth state \(central.state.rawValue) (5 = on, 3 = unauthorized)")
        guard central.state == .poweredOn else {
            if central.state == .unauthorized { finish("Bluetooth permission denied") }
            return
        }
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        after(scanOnly ? 25 : 30) {
            if self.scanOnly { self.finish("done") }
            if self.peripheral == nil { self.finish("No matching light found in 30 s") }
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover p: CBPeripheral,
                        advertisementData: [String: Any], rssi: NSNumber) {
        let name = p.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? ""
        let lower = name.lowercased()
        let maker = (advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data).map(hex) ?? ""
        let key = p.identifier.uuidString
        if scanOnly {
            if seen.insert(key).inserted { log("adv \(name.isEmpty ? "(no name)" : name) rssi \(rssi) mfr \(maker.prefix(23))") }
            return
        }
        if (lower.contains("govee") || lower.contains("ihoment") || lower.contains("gvh") || lower.contains("_h6")), seen.insert(name).inserted {
            log("seen \(name) rssi \(rssi)")
        }
        guard peripheral == nil, lower.contains(filter) else { return }
        log("connecting to \(name)")
        peripheral = p
        central.stopScan()
        p.delegate = self
        central.connect(p)
        after(10) { if self.control == nil { self.finish("Could not connect in 10 s") } }
    }

    func centralManager(_ central: CBCentralManager, didConnect p: CBPeripheral) {
        log("connected; discovering services")
        p.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        finish("connect failed: \(error?.localizedDescription ?? "unknown")")
    }

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        for s in p.services ?? [] {
            log("service \(s.uuid.uuidString)")
            p.discoverCharacteristics(nil, for: s)
        }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        for c in s.characteristics ?? [] {
            log("  characteristic \(c.uuid.uuidString) properties \(c.properties.rawValue)")
            if c.uuid == notifyID { p.setNotifyValue(true, for: c) }
            if c.uuid == controlID { control = c }
        }
    }

    func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor c: CBCharacteristic, error: Error?) {
        log("notifications \(c.isNotifying) \(error?.localizedDescription ?? "")")
        guard c.isNotifying else { return }
        query()
        after(1.5) {
            guard !self.sentCommands, self.session == nil else { return }
            log("no plain reply; trying encrypted session handshake")
            if let hello = SessionCipher.auth.encrypt(frame([0xE7, 0x01])) { self.writeWire(hello) }
            self.after(2) { if !self.sentCommands { self.sendCommands() } }
        }
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor c: CBCharacteristic, error: Error?) {
        guard var data = c.value else { return }
        if session == nil, data.count == 20, let hs = SessionCipher.auth.decrypt(data), hs[0] == 0xE7 {
            if hs[1] == 0x01, hs.reduce(0, ^) == 0 {
                session = SessionCipher(key: Data(hs[2..<18]))
                log("encrypted session established")
                if let done = SessionCipher.auth.encrypt(frame([0xE7, 0x02])) { writeWire(done) }
                after(0.2) { self.query() }
            }
            return
        }
        if let session, data.count == 20, let plain = session.decrypt(data), plain.reduce(0, ^) == 0 {
            data = plain
        }
        log("reply \(hex(data))")
        if data.first == 0xAA, !sentCommands { after(0.5) { self.sendCommands() } }
    }

    func query() {
        for cmd: UInt8 in [0x01, 0x04, 0x05] { write(frame([0xAA, cmd])) }
    }

    func sendCommands() {
        guard !sentCommands else { return }
        sentCommands = true
        for (i, command) in commands.enumerated() {
            after(Double(i) * 0.1) { self.write(command) }
        }
        after(Double(commands.count) * 0.1 + 1.5) {
            log("re-querying state")
            self.query()
            self.after(1.5) { self.finish("done") }
        }
    }

    func write(_ plain: Data) {
        log("send  \(hex(plain))\(session == nil ? "" : " (encrypted)")")
        writeWire(session?.encrypt(plain) ?? plain)
    }

    func writeWire(_ data: Data) {
        guard let peripheral, let control else { return }
        let type: CBCharacteristicWriteType = control.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        peripheral.writeValue(data, for: control, type: type)
    }

    func after(_ seconds: Double, _ body: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: body)
    }

    func finish(_ message: String) {
        log(message)
        if let peripheral { central.cancelPeripheralConnection(peripheral) }
        exit(message == "done" ? 0 : 1)
    }
}

func rgb(_ s: String) -> [UInt8]? {
    guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
    return [UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)]
}

let args = Array(CommandLine.arguments.dropFirst())
guard args.count >= 2 else {
    print("usage: GoveeBLEProbe <name-filter> status|power on|off|color rrggbb|segment mask rrggbb|raw hex…|scene code base64")
    exit(2)
}
var commands: [Data] = []
switch args[1] {
case "status": break
case "power" where args.count == 3: commands = [frame([0x33, 0x01, args[2] == "on" ? 1 : 0])]
case "color" where args.count == 3:
    guard let c = rgb(args[2]) else { exit(2) }
    commands = [frame([0x33, 0x05, 0x02] + c)]
case "segment" where args.count == 4:
    guard let mask = UInt32(args[2], radix: 16), let c = rgb(args[3]) else { exit(2) }
    commands = [frame([0x33, 0x05, 0x15, 0x01] + c
        + [0, 0, 0, 0, 0, UInt8(mask & 0xFF), UInt8(mask >> 8 & 0xFF), UInt8(mask >> 16 & 0xFF)])]
case "raw" where args.count >= 3:
    commands = [frame(args.dropFirst(2).compactMap { UInt8($0, radix: 16) })]
case "frames" where args.count >= 3:
    // Each argument is one frame as contiguous hex ("330515…"); padding and checksum are added.
    commands = args.dropFirst(2).map { word in
        frame(stride(from: 0, to: word.count, by: 2).compactMap { i -> UInt8? in
            let start = word.index(word.startIndex, offsetBy: i)
            return UInt8(word[start..<word.index(start, offsetBy: 2, limitedBy: word.endIndex)!], radix: 16)
        })
    }
case "scene" where args.count == 4:
    guard let code = UInt16(args[2]) else { exit(2) }
    commands = sceneFrames(code: code, param: Data(base64Encoded: args[3]) ?? Data())
default:
    print("unknown command")
    exit(2)
}
log("probe \(args.joined(separator: " "))")
let probe = Probe(filter: args[0], commands: commands)
RunLoop.main.run()

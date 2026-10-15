import CoreBluetooth
import Foundation

/// Sends Govee frames over Bluetooth for lights that ignore them on LAN (fork).
///
/// One link per light, opened on first use and kept alive with the status query the Govee app
/// sends, because these lights advertise only intermittently: reconnecting per command can wait
/// half a minute. A link closes after `idleTimeout` without commands so the Govee app can
/// connect again. Bluetooth permission is only requested once a light first needs it.
///
/// All CoreBluetooth callbacks arrive on the main queue.
final class GoveeBluetoothController: NSObject, ObservableObject {
    enum LinkState: Equatable {
        case searching
        case connecting
        case connected
        case unavailable(String)

        var title: String {
            switch self {
            case .searching: return "Looking for the light over Bluetooth…"
            case .connecting: return "Connecting over Bluetooth…"
            case .connected: return "Connected over Bluetooth"
            case .unavailable(let reason): return reason
            }
        }
    }

    /// Keyed by `LightDevice.id`.
    @Published private(set) var states: [String: LinkState] = [:]

    var idleTimeout: TimeInterval = 300
    private let keepAliveInterval: TimeInterval = 2
    private let frameGap: TimeInterval = 0.06

    private final class Link {
        let sku: String?
        let deviceID: String
        /// Nil until a scan finds the light's advert.
        var peripheral: CBPeripheral?
        var control: CBCharacteristic?
        var session: GoveeSessionCipher?
        var ready = false
        var pending: [[UInt8]] = []
        var lastUse = Date()

        init(sku: String?, deviceID: String) {
            self.sku = sku
            self.deviceID = deviceID
        }
    }

    private var central: CBCentralManager?
    private var links: [String: Link] = [:]
    private var keepAliveTimer: Timer?

    private let serviceID = CBUUID(string: GoveeBluetoothProtocol.serviceUUID)
    private let controlID = CBUUID(string: GoveeBluetoothProtocol.controlUUID)
    private let notifyID = CBUUID(string: GoveeBluetoothProtocol.notifyUUID)

    // MARK: Public API

    /// Whether this light's scenes and segments must go over Bluetooth.
    static func requiresBluetooth(_ device: LightDevice) -> Bool {
        device.brand == .govee && GoveeBluetoothProtocol.framesOnlyOverBluetooth.contains(device.sku ?? "")
    }

    /// Starts connecting ahead of a command, e.g. when the light's controls appear.
    func prepare(_ device: LightDevice) {
        guard device.brand == .govee else { return }
        link(for: device).lastUse = Date()
    }

    /// Queues `frames` for the light; they are written once the link is ready. A newer batch
    /// replaces one still waiting, so the light ends up in the last requested state.
    func send(_ frames: [[UInt8]], to device: LightDevice) {
        guard device.brand == .govee, !frames.isEmpty else { return }
        let link = link(for: device)
        link.lastUse = Date()
        if link.ready {
            write(frames, to: link)
        } else {
            link.pending = frames
        }
    }

    // MARK: Links

    private func link(for device: LightDevice) -> Link {
        if let link = links[device.id] { return link }
        let link = Link(sku: device.sku, deviceID: device.backendID)
        links[device.id] = link
        states[device.id] = .searching
        if central == nil {
            // The first use asks for Bluetooth permission; scanning starts once it's granted.
            central = CBCentralManager(delegate: self, queue: .main)
        } else {
            startScanIfNeeded()
        }
        startTimer()
        return link
    }

    private func startScanIfNeeded() {
        guard let central, central.state == .poweredOn, !central.isScanning,
              links.values.contains(where: { $0.peripheral == nil }) else { return }
        // Duplicates on: a light whose first advert lacks its name must still be matched later.
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }

    private func write(_ frames: [[UInt8]], to link: Link) {
        for (index, frame) in frames.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * frameGap) { [weak self, weak link] in
                guard let self, let link else { return }
                self.writeNow(frame, to: link)
            }
        }
    }

    private func writeNow(_ frame: [UInt8], to link: Link) {
        writeWire(link.session?.encrypt(frame) ?? frame, to: link)
    }

    private func writeWire(_ wire: [UInt8], to link: Link) {
        guard let control = link.control, let peripheral = link.peripheral else { return }
        let type: CBCharacteristicWriteType =
            control.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        peripheral.writeValue(Data(wire), for: control, type: type)
    }

    private func entry(for peripheral: CBPeripheral) -> (id: String, link: Link)? {
        links.first { $0.value.peripheral === peripheral }.map { ($0.key, $0.value) }
    }

    private func markReady(_ id: String, _ link: Link) {
        guard !link.ready else { return }
        link.ready = true
        states[id] = .connected
        if !link.pending.isEmpty {
            let frames = link.pending
            link.pending = []
            write(frames, to: link)
        }
    }

    private func startTimer() {
        guard keepAliveTimer == nil else { return }
        keepAliveTimer = Timer.scheduledTimer(withTimeInterval: keepAliveInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    /// Keep-alive for ready links, and closing links that went unused.
    private func tick() {
        let now = Date()
        for (id, link) in links {
            if now.timeIntervalSince(link.lastUse) > idleTimeout {
                close(id)
            } else if link.ready {
                writeNow(GoveeBluetoothProtocol.keepAlive, to: link)
            }
        }
        if links.isEmpty {
            keepAliveTimer?.invalidate()
            keepAliveTimer = nil
            central?.stopScan()
        }
    }

    private func close(_ id: String) {
        guard let link = links.removeValue(forKey: id) else { return }
        states[id] = nil
        if let peripheral = link.peripheral { central?.cancelPeripheralConnection(peripheral) }
    }
}

// MARK: - CBCentralManagerDelegate

extension GoveeBluetoothController: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let problem: String?
        switch central.state {
        case .poweredOn: problem = nil
        case .unauthorized:
            problem = "Bluetooth access is off. Allow LumenDesk in System Settings → Privacy & Security → Bluetooth."
        case .poweredOff: problem = "Bluetooth is turned off."
        case .unsupported: problem = "This Mac doesn't support Bluetooth LE."
        default: return
        }
        for (id, link) in links {
            if let problem {
                states[id] = .unavailable(problem)
            } else if let peripheral = link.peripheral {
                states[id] = .connecting
                // Links that dropped while Bluetooth was off.
                if peripheral.state == .disconnected { central.connect(peripheral) }
            } else {
                states[id] = .searching
            }
        }
        startScanIfNeeded()
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? ""
        guard !name.isEmpty,
              case let (id, link)? = links.first(where: { _, link in
                  link.peripheral == nil
                      && GoveeBluetoothProtocol.advertName(name, matchesSKU: link.sku, deviceID: link.deviceID)
              }) else { return }

        link.peripheral = peripheral
        states[id] = .connecting
        peripheral.delegate = self
        central.connect(peripheral)
        if !links.values.contains(where: { $0.peripheral == nil }) { central.stopScan() }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([serviceID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard entry(for: peripheral) != nil else { return }
        central.connect(peripheral)  // pends until the light advertises again
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        guard case let (id, link)? = entry(for: peripheral) else { return }
        link.ready = false
        link.session = nil
        link.control = nil
        states[id] = .connecting
        central.connect(peripheral)
    }
}

// MARK: - CBPeripheralDelegate

extension GoveeBluetoothController: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for service in peripheral.services ?? [] where service.uuid == serviceID {
            peripheral.discoverCharacteristics([controlID, notifyID], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let link = entry(for: peripheral)?.link else { return }
        for characteristic in service.characteristics ?? [] {
            if characteristic.uuid == controlID { link.control = characteristic }
            if characteristic.uuid == notifyID { peripheral.setNotifyValue(true, for: characteristic) }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard characteristic.isNotifying, let link = entry(for: peripheral)?.link else { return }
        for query in GoveeBluetoothProtocol.statusQueries { writeNow(query, to: link) }
        // Models with the legacy session ignore plain frames; open one if nothing answers.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self, weak link] in
            guard let self, let link, !link.ready, link.session == nil,
                  let hello = GoveeSessionCipher.handshake.encrypt(GoveeBluetoothProtocol.sessionHello) else { return }
            self.writeWire(hello, to: link)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard case let (id, link)? = entry(for: peripheral),
              var frame = characteristic.value.map({ Array($0) }) else { return }

        if link.session == nil, frame.count == 20,
           let reply = GoveeSessionCipher.handshake.decrypt(frame), reply[0] == 0xE7 {
            if reply[1] == 0x01, reply.reduce(0, ^) == 0,
               let session = GoveeSessionCipher(key: Array(reply[2..<18])) {
                link.session = session
                if let finish = GoveeSessionCipher.handshake.encrypt(GoveeBluetoothProtocol.sessionFinish) {
                    writeWire(finish, to: link)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self, weak link] in
                    guard let self, let link else { return }
                    for query in GoveeBluetoothProtocol.statusQueries { self.writeNow(query, to: link) }
                }
            }
            return
        }
        if let session = link.session {
            guard let plain = session.decrypt(frame), plain.reduce(0, ^) == 0 else { return }
            frame = plain
        }
        if GoveeBluetoothProtocol.parse(frame) != nil { markReady(id, link) }
    }
}

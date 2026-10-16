import CoreBluetooth
import Foundation

/// How LightManager reaches Govee lights that exist only over Bluetooth (fork).
protocol GoveeBluetoothLightTransport: AnyObject {
    func setPower(_ device: LightDevice, on: Bool)
    func setBrightness(_ device: LightDevice, percent: Int)
    func setColor(_ device: LightDevice, r: Int, g: Int, b: Int)
    func setKelvin(_ device: LightDevice, kelvin: Int)
    func refresh(_ device: LightDevice)
    /// Whether the light's link was closed while idle and hasn't reconnected yet. Its silence then
    /// says nothing about whether it's reachable.
    func isReleased(_ device: LightDevice) -> Bool
}

extension LightDevice {
    /// A Govee light added by Bluetooth pairing; its `backendID` is `ble:<advert name>` and its
    /// address `Bluetooth`. LAN lights can't look like this: their IDs are validated MAC-style
    /// strings and their address is the IP that answered.
    var isBluetoothOnly: Bool { brand == .govee && backendID.hasPrefix("ble:") && address == "Bluetooth" }
}

/// Govee lights over Bluetooth (fork).
///
/// Two jobs: scenes and segments for LAN lights whose firmware ignores them over Wi-Fi (H60A1),
/// and full control of lights that have no LAN API at all (H6008 bulbs).
///
/// It never adds or connects to a light on its own. Bluetooth-only lights are paired by the user
/// from a pairing scan (`startPairingScan`); otherwise it scans only to find lights it already
/// knows, and only connects to those.
///
/// One link per light, kept alive with the status query the Govee app sends, because these lights
/// advertise only intermittently: reconnecting per command can wait half a minute. Links for LAN
/// lights close after `idleTimeout` without commands so the Govee app can connect again; links for
/// Bluetooth-only lights stay open, since that is their only connection, unless
/// `bluetoothOnlyIdleTimeout` is set. A closed link reopens on the next command. Bluetooth
/// permission is requested the first time a light needs it or discovery starts.
///
/// All CoreBluetooth callbacks arrive on the main queue.
final class GoveeBluetoothController: NSObject, ObservableObject {
    enum LinkState: Equatable {
        case searching
        case connecting
        case connected
        /// Closed while idle so the Govee app can connect; reopens on the next command.
        case released
        case unavailable(String)

        var title: String {
            switch self {
            case .searching: return "Looking for the light over Bluetooth…"
            case .connecting: return "Connecting over Bluetooth…"
            case .connected: return "Connected over Bluetooth"
            case .released: return "Disconnected while idle so the Govee app can connect. Reconnects on the next command."
            case .unavailable(let reason): return reason
            }
        }
    }

    /// Keyed by `LightDevice.id`.
    @Published private(set) var states: [String: LinkState] = [:]

    /// A Govee light heard during a pairing scan.
    struct NearbyLight: Identifiable, Equatable {
        /// Advert name, such as `ihoment_H6008_1A2B`.
        let name: String
        let sku: String
        var rssi: Int
        /// The system's identifier for this peripheral, recorded at pairing.
        let identifier: UUID
        var id: String { name }
    }

    /// Govee lights heard since `startPairingScan`, strongest signal first.
    @Published private(set) var nearby: [NearbyLight] = []
    /// A status reply from a light, keyed by `LightDevice.id`.
    var onReply: ((_ deviceID: String, _ reply: GoveeBluetoothProtocol.Reply) -> Void)?
    /// Whether the user paired this advert name. Bluetooth-only lights that aren't are refused,
    /// whatever asks for them.
    var isPaired: (String) -> Bool = { _ in false }
    /// The system identifier of the peripheral paired under an advert name, if known. A light is
    /// only ever connected to that peripheral, so another device can't take over its name.
    var pairedPeripheral: (String) -> UUID? = { _ in nil }
    /// Called when a paired light is first connected without a stored identifier (lights paired
    /// before identifiers were recorded), so it can be saved.
    var onBindPeripheral: ((_ name: String, _ identifier: UUID) -> Void)?

    /// How long a LAN light's link stays open without commands.
    var idleTimeout: TimeInterval = 300
    /// How long a Bluetooth-only light's link stays open without commands; nil keeps it open for
    /// as long as the app runs. Turning this off reconnects the lights that were released.
    var bluetoothOnlyIdleTimeout: TimeInterval? {
        didSet {
            guard bluetoothOnlyIdleTimeout == nil else { return }
            let devices = Array(releasedDevices.values)
            for device in devices { prepare(device) }
        }
    }
    private let keepAliveInterval: TimeInterval = 2
    private let frameGap: TimeInterval = 0.06
    private let maxPendingFrames = 24

    private final class Link {
        /// Whether an advert name belongs to this light.
        let matches: (String) -> Bool
        /// For paired Bluetooth-only lights: the advert name and required peripheral.
        var pairedName: String?
        var requiredPeripheral: UUID?
        /// Bluetooth-only lights keep their link open for as long as the app runs, unless
        /// `bluetoothOnlyIdleTimeout` is set.
        let bluetoothOnly: Bool
        /// Nil until a scan finds the light's advert.
        var peripheral: CBPeripheral?
        var control: CBCharacteristic?
        var session: GoveeSessionCipher?
        var ready = false
        var pending: [[UInt8]] = []
        var lastUse = Date()
        /// Kept to reopen a released link when the idle setting is turned off.
        weak var device: LightDevice?

        init(bluetoothOnly: Bool, matches: @escaping (String) -> Bool) {
            self.bluetoothOnly = bluetoothOnly
            self.matches = matches
        }
    }

    private var central: CBCentralManager?
    private let makeCentral: (GoveeBluetoothController) -> CBCentralManager?
    private var links: [String: Link] = [:]
    /// Bluetooth-only lights whose link closed while idle, until they reconnect.
    private var releasedDevices: [String: LightDevice] = [:]
    private var keepAliveTimer: Timer?
    private var pairingScan = false
    /// Peripherals seen in adverts, by advert name, so a new link can connect without rescanning.
    private var seenPeripherals: [String: CBPeripheral] = [:]

    private let serviceID = CBUUID(string: GoveeBluetoothProtocol.serviceUUID)
    private let controlID = CBUUID(string: GoveeBluetoothProtocol.controlUUID)
    private let notifyID = CBUUID(string: GoveeBluetoothProtocol.notifyUUID)

    /// `makeCentral` exists for tests, which run without Bluetooth.
    init(makeCentral: @escaping (GoveeBluetoothController) -> CBCentralManager? = {
        CBCentralManager(delegate: $0, queue: .main)
    }) {
        self.makeCentral = makeCentral
        super.init()
    }

    // MARK: Public API

    /// Whether this light's scenes and segments must go over Bluetooth.
    static func requiresBluetooth(_ device: LightDevice) -> Bool {
        device.isBluetoothOnly
            || (device.brand == .govee && GoveeBluetoothProtocol.framesOnlyOverBluetooth.contains(device.sku ?? ""))
    }

    /// Lists nearby Govee lights in `nearby` until `stopPairingScan`. Nothing is connected.
    func startPairingScan() {
        pairingScan = true
        nearby = []
        ensureCentral()
        startScanIfNeeded()
    }

    func stopPairingScan() {
        pairingScan = false
        nearby = []
        if !needsScan { central?.stopScan() }
    }

    /// Disconnects and drops the light's link.
    func forget(_ device: LightDevice) {
        close(device.id)
        releasedDevices[device.id] = nil
        states[device.id] = nil
    }

    /// Whether the light has a link, open or opening.
    func hasLink(_ device: LightDevice) -> Bool {
        links[device.id] != nil
    }

    /// Whether an idle link should close. LAN lights' links close after `lanTimeout`;
    /// Bluetooth-only lights' links only when `bluetoothOnlyTimeout` is set.
    static func shouldRelease(bluetoothOnly: Bool, idleFor idle: TimeInterval,
                              lanTimeout: TimeInterval, bluetoothOnlyTimeout: TimeInterval?) -> Bool {
        guard let timeout = bluetoothOnly ? bluetoothOnlyTimeout : lanTimeout else { return false }
        return idle > timeout
    }

    /// Starts connecting ahead of a command, e.g. when the light's controls appear.
    func prepare(_ device: LightDevice) {
        guard device.brand == .govee else { return }
        link(for: device)?.lastUse = Date()
    }

    /// Queues `frames` for the light; they are written in order once the link is ready.
    func send(_ frames: [[UInt8]], to device: LightDevice) {
        guard device.brand == .govee, !frames.isEmpty, let link = link(for: device) else { return }
        link.lastUse = Date()
        if link.ready {
            write(frames, to: link)
        } else {
            link.pending = Array((link.pending + frames).suffix(maxPendingFrames))
        }
    }

    // MARK: Links

    private func ensureCentral() {
        // The first call asks for Bluetooth permission; scanning starts once it's granted.
        if central == nil { central = makeCentral(self) }
    }

    private func link(for device: LightDevice) -> Link? {
        if let link = links[device.id] { return link }
        let link: Link
        if device.isBluetoothOnly {
            let name = String(device.backendID.dropFirst("ble:".count))
            guard isPaired(name) else { return nil }
            link = Link(bluetoothOnly: true) { $0 == name }
            link.pairedName = name
            link.requiredPeripheral = pairedPeripheral(name)
        } else {
            let sku = device.sku, deviceID = device.backendID
            link = Link(bluetoothOnly: false) {
                GoveeBluetoothProtocol.advertName($0, matchesSKU: sku, deviceID: deviceID)
            }
        }
        link.device = device
        links[device.id] = link
        states[device.id] = .searching
        ensureCentral()
        if let peripheral = seenPeripherals.first(where: { link.matches($0.key) && accepts($0.value, for: link) })?.value {
            attach(peripheral, to: link, id: device.id)
        } else {
            startScanIfNeeded()
        }
        startTimer()
        return link
    }

    private func accepts(_ peripheral: CBPeripheral, for link: Link) -> Bool {
        link.requiredPeripheral.map { $0 == peripheral.identifier } ?? true
    }

    private func attach(_ peripheral: CBPeripheral, to link: Link, id: String) {
        if let name = link.pairedName, link.requiredPeripheral == nil {
            link.requiredPeripheral = peripheral.identifier
            onBindPeripheral?(name, peripheral.identifier)
        }
        link.peripheral = peripheral
        states[id] = .connecting
        peripheral.delegate = self
        if let central, central.state == .poweredOn { central.connect(peripheral) }
    }

    private var needsScan: Bool {
        pairingScan || links.values.contains(where: { $0.peripheral == nil })
    }

    private func startScanIfNeeded() {
        guard let central, central.state == .poweredOn, !central.isScanning, needsScan else { return }
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
        releasedDevices[id] = nil
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

    /// Keep-alive for ready links, and closing links that went unused (internal for tests).
    func tick(now: Date = Date()) {
        for (id, link) in links {
            if Self.shouldRelease(bluetoothOnly: link.bluetoothOnly, idleFor: now.timeIntervalSince(link.lastUse),
                                  lanTimeout: idleTimeout, bluetoothOnlyTimeout: bluetoothOnlyIdleTimeout) {
                if link.bluetoothOnly { release(id, device: link.device) } else { close(id) }
            } else if link.ready {
                writeNow(GoveeBluetoothProtocol.keepAlive, to: link)
            }
        }
        if links.isEmpty {
            keepAliveTimer?.invalidate()
            keepAliveTimer = nil
            if !needsScan { central?.stopScan() }
        }
    }

    private func close(_ id: String) {
        guard let link = links.removeValue(forKey: id) else { return }
        states[id] = nil
        if let peripheral = link.peripheral { central?.cancelPeripheralConnection(peripheral) }
    }

    /// Closes a Bluetooth-only light's idle link. The next command reopens it through
    /// `link(for:)`, which finds the peripheral in `seenPeripherals` and connects without a scan.
    private func release(_ id: String, device: LightDevice?) {
        close(id)
        guard let device else { return }
        releasedDevices[id] = device
        states[id] = .released
    }
}

// MARK: - Transport for Bluetooth-only lights

extension GoveeBluetoothController: GoveeBluetoothLightTransport {
    func setPower(_ device: LightDevice, on: Bool) {
        send([GoveeBluetoothProtocol.powerFrame(on: on)], to: device)
    }

    func setBrightness(_ device: LightDevice, percent: Int) {
        send([GoveeBluetoothProtocol.brightnessFrame(percent: percent)], to: device)
    }

    func setColor(_ device: LightDevice, r: Int, g: Int, b: Int) {
        send([GoveeBluetoothProtocol.colorFrame(r: r, g: g, b: b)], to: device)
    }

    func setKelvin(_ device: LightDevice, kelvin: Int) {
        send([GoveeBluetoothProtocol.whiteFrame(kelvin: kelvin)], to: device)
    }

    func isReleased(_ device: LightDevice) -> Bool {
        releasedDevices[device.id] != nil
    }

    func refresh(_ device: LightDevice) {
        // Polling mustn't reopen a released link; only commands do.
        guard releasedDevices[device.id] == nil || links[device.id] != nil,
              let link = link(for: device), link.ready else { return }
        for query in GoveeBluetoothProtocol.statusQueries { writeNow(query, to: link) }
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
                // Links found earlier, or that dropped while Bluetooth was off.
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
        guard !name.isEmpty, let advert = GoveeBluetoothProtocol.parseName(name) else { return }
        if seenPeripherals[name] == nil, seenPeripherals.count >= 64 {
            seenPeripherals.removeValue(forKey: seenPeripherals.keys.first!)
        }
        seenPeripherals[name] = peripheral

        if pairingScan {
            let rssi = RSSI.intValue
            if let index = nearby.firstIndex(where: { $0.name == name }) {
                // Skip small signal changes to avoid redrawing on every advert.
                if abs(nearby[index].rssi - rssi) >= 6, rssi < 0 { nearby[index].rssi = rssi }
            } else if nearby.count < 40 {
                nearby.append(NearbyLight(name: name, sku: advert.sku, rssi: rssi, identifier: peripheral.identifier))
            }
            nearby.sort { $0.rssi > $1.rssi }
        }
        if case let (id, link)? = links.first(where: {
            $0.value.peripheral == nil && $0.value.matches(name) && accepts(peripheral, for: $0.value)
        }) {
            attach(peripheral, to: link, id: id)
        }
        if !needsScan { central.stopScan() }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([serviceID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard entry(for: peripheral) != nil else { return }
        // Pends until the light advertises again; wait a little so a failing device can't spin us.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self, weak peripheral] in
            guard let self, let peripheral, self.entry(for: peripheral) != nil else { return }
            central.connect(peripheral)
        }
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
        guard let reply = GoveeBluetoothProtocol.parse(frame) else { return }
        markReady(id, link)
        onReply?(id, reply)
    }
}

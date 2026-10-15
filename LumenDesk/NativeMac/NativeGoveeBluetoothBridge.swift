#if os(macOS)
import Foundation

// Fork: connects GoveeBluetoothController to LightManager.
//
// Bluetooth-only lights are added only when the user pairs them; the paired list is the
// allowlist of lights the app will ever connect to on its own.

enum NativePairedBluetoothLights {
    private static let key = "Native.pairedGoveeBluetooth.v1"
    private static let peripheralsKey = "Native.pairedGoveeBluetoothPeripherals.v1"

    /// Advert name → model.
    static var all: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// Advert name → the peripheral's system identifier (this Mac's alias for the device).
    static var peripherals: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: peripheralsKey) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: peripheralsKey) }
    }
}

/// Settings → General: whether Bluetooth-only lights' links close when idle, so the Govee phone
/// app can connect to them. Off by default, since reconnecting can take half a minute.
enum NativeBluetoothIdleRelease {
    static let enabledKey = "Native.bluetoothIdleRelease.v1"
    static let minutesKey = "Native.bluetoothIdleReleaseMinutes.v1"
    static let minuteChoices = [1, 5, 15]
    static let defaultMinutes = 5

    static func timeout(enabled: Bool, minutes: Int) -> TimeInterval? {
        enabled ? TimeInterval(minuteChoices.contains(minutes) ? minutes : defaultMinutes) * 60 : nil
    }

    static func apply(to bluetooth: GoveeBluetoothController, defaults: UserDefaults = .standard) {
        let minutes = defaults.object(forKey: minutesKey) as? Int ?? defaultMinutes
        bluetooth.bluetoothOnlyIdleTimeout = timeout(enabled: defaults.bool(forKey: enabledKey), minutes: minutes)
    }
}

extension LightManager {
    /// Routes Bluetooth-only Govee lights through `bluetooth` and restores the paired ones.
    /// Safe to call more than once.
    func connectGoveeBluetooth(_ bluetooth: GoveeBluetoothController) {
        guard goveeBluetooth == nil else { return }
        goveeBluetooth = bluetooth
        NativeBluetoothIdleRelease.apply(to: bluetooth)
        bluetooth.isPaired = { NativePairedBluetoothLights.all[$0] != nil }
        bluetooth.pairedPeripheral = { NativePairedBluetoothLights.peripherals[$0].flatMap(UUID.init(uuidString:)) }
        bluetooth.onBindPeripheral = { name, identifier in
            NativePairedBluetoothLights.peripherals[name] = identifier.uuidString
        }

        bluetooth.onReply = { [weak self] deviceID, reply in
            Task { @MainActor in
                guard let self else { return }
                switch reply {
                case .power(let on):
                    self.bluetoothGoveeDidReply(deviceID: deviceID, power: on)
                case .brightness(let percent):
                    self.bluetoothGoveeDidReply(deviceID: deviceID, brightnessPercent: percent)
                case .mode(let mode):
                    if let state = GoveeBluetoothProtocol.colorState(fromMode: mode) {
                        self.bluetoothGoveeDidReply(deviceID: deviceID, rgb: (state.r, state.g, state.b),
                                                    kelvin: state.kelvin)
                    }
                }
            }
        }

        for (name, sku) in NativePairedBluetoothLights.all {
            addPairedBluetoothLight(name: name, sku: sku, bluetooth: bluetooth)
        }
    }

    /// Whether a nearby advert is a light already added, by pairing or over Wi-Fi.
    func isKnownBluetoothAdvert(_ name: String) -> Bool {
        devices.contains { device in
            device.brand == .govee
                && (device.backendID == "ble:\(name)"
                    || GoveeBluetoothProtocol.advertName(name, matchesSKU: device.sku, deviceID: device.backendID))
        }
    }

    func pairBluetoothLight(_ light: GoveeBluetoothController.NearbyLight, room roomID: UUID?,
                            bluetooth: GoveeBluetoothController) {
        NativePairedBluetoothLights.all[light.name] = light.sku
        NativePairedBluetoothLights.peripherals[light.name] = light.identifier.uuidString
        addPairedBluetoothLight(name: light.name, sku: light.sku, bluetooth: bluetooth)
        if let roomID, let device = devices.first(where: { $0.id == "govee:ble:\(light.name)" }) {
            nativeAssign(device, toRoom: roomID)
        }
        logActivity(.system, title: "Bluetooth light paired", detail: light.name)
    }

    func forgetBluetoothLight(_ device: LightDevice, bluetooth: GoveeBluetoothController) {
        guard device.isBluetoothOnly else { return }
        let name = String(device.backendID.dropFirst("ble:".count))
        NativePairedBluetoothLights.all[name] = nil
        NativePairedBluetoothLights.peripherals[name] = nil
        bluetooth.forget(device)
        removeBluetoothGovee(deviceID: device.id)
        logActivity(.system, title: "Bluetooth light forgotten", detail: device.label)
    }

    private func addPairedBluetoothLight(name: String, sku: String, bluetooth: GoveeBluetoothController) {
        addBluetoothGovee(advertName: name, sku: sku)
        // Connect right away so the light's state shows up.
        if let device = devices.first(where: { $0.id == "govee:ble:\(name)" }) {
            bluetooth.prepare(device)
        }
    }
}
#endif

#if os(macOS)
import Foundation

extension LightManager {
    /// Fork: starts the app's services without scanning; the network gate scans once the Mac is
    /// on a home network. Safe to call more than once.
    func startNative(bluetooth: GoveeBluetoothController, gate: NativeNetworkGate,
                     shortcuts: NativeShortcutCenter, macEvents: NativeMacEvents) {
        gate.attach(self)
        start(discover: false)
        connectGoveeBluetooth(bluetooth)
        shortcuts.attach(self)
        macEvents.attach(self, gate: gate)
    }
}
#endif

#if os(macOS)
/// Where LumenDesk's quick controls live (fork): Control Center (controls the user adds there,
/// macOS 26+) or LumenDesk's own menu bar icon. Only one is shown, Control Center by default.
enum NativeControlsLocation: String, CaseIterable, Identifiable {
    case controlCenter
    case menuBar

    static let storageKey = "Native.controlsLocation"

    static var isControlCenterAvailable: Bool {
        if #available(macOS 26, *) { return true }
        return false
    }

    static var defaultValue: Self { isControlCenterAvailable ? .controlCenter : .menuBar }

    var id: Self { self }
    var title: String { self == .controlCenter ? "Control Center" : "Menu Bar" }
}
#endif

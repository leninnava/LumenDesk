#if os(macOS)
import Foundation

extension LightManager {
    /// Fork: starts the app's services without scanning; the network gate scans once the Mac is
    /// on a home network. Safe to call more than once.
    func startNative(bluetooth: GoveeBluetoothController, gate: NativeNetworkGate,
                     shortcuts: NativeShortcutCenter) {
        gate.attach(self)
        start(discover: false)
        connectGoveeBluetooth(bluetooth)
        shortcuts.attach(self)
    }
}
#endif

import Foundation

/// The app's long-lived objects (fork), created once and shared by the SwiftUI scenes and the
/// App Intents.
///
/// App Intents for LumenDesk always perform in the app's process (they are defined in the app
/// target, and the control intents opt into the app process), so a process-wide instance is the
/// whole story: `LumenDeskApp` hands these objects to its scenes as `@StateObject`s, and intents
/// and entity queries reach the same `LightManager` through `AppServices.shared`. When the system
/// launches LumenDesk just to run an intent, `prepareForIntent` starts the same services the
/// windows start on appear.
@MainActor
final class AppServices {
    static let shared = AppServices()

    let manager: LightManager
    #if os(macOS)
    let goveeBluetooth: GoveeBluetoothController
    let goveeScenes: GoveeSceneStore
    let networkGate: NativeNetworkGate
    /// Publishes room/all-lights state for the Control Center controls and the desktop widget.
    let controlsBridge: NativeControlsBridge
    #endif

    private init() {
        manager = LightManager()
        #if os(macOS)
        goveeBluetooth = GoveeBluetoothController()
        goveeScenes = GoveeSceneStore()
        networkGate = NativeNetworkGate()
        controlsBridge = NativeControlsBridge(manager: manager)
        #endif
    }

    /// Whether the process is a unit-test host, where nothing should touch the App Group.
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// Starts discovery the way the windows do, then waits up to `timeout` for `isReady`.
    ///
    /// Lights aren't persisted; they're rediscovered on every launch. An intent that cold-launches
    /// the app would otherwise find no lights at all, so it waits briefly for the ones it needs.
    func prepareForIntent(timeout: Duration = .seconds(4),
                          until isReady: @MainActor (LightManager) -> Bool) async {
        #if os(macOS)
        manager.startNative(bluetooth: goveeBluetooth, gate: networkGate)
        #else
        if UserDefaults.standard.bool(forKey: "LumenDesk.hasOnboarded.v1") { manager.start() }
        #endif
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !isReady(manager), clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }
}

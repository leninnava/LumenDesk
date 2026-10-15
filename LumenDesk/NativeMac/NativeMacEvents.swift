#if os(macOS)
import AppKit
import Foundation
import IOKit.pwr_mgt

// Fork: turns lights off when the Mac sleeps or the screen locks, and back on afterwards
// (Settings → Automations). Time-based automations are upstream's room schedules.

/// Which lights an automation affects, stored as "all" or a room's UUID.
enum NativeAutomationScope {
    static let all = "all"

    /// A room that no longer exists falls back to all lights, which is what Settings then shows.
    static func scope(from stored: String, rooms: [Room]) -> LightScope {
        guard let id = UUID(uuidString: stored), rooms.contains(where: { $0.id == id }) else { return .all }
        return .room(id)
    }

    static func stored(_ scope: LightScope) -> String {
        switch scope {
        case .all: return all
        case .room(let id): return id.uuidString
        }
    }
}

/// Which lights the automations turned off, and whether anything still holds them off.
///
/// Lights come back only once every reason has ended: a Mac that wakes to a locked screen turns
/// them on when it's unlocked, not while nobody is there. A second trigger adds to the snapshot
/// rather than replacing it, so locking then sleeping doesn't forget what locking turned off.
struct NativeLightsSuspension: Equatable {
    enum Reason: Hashable {
        case sleep
        case lock
    }

    private(set) var active: Set<Reason> = []
    /// IDs of lights that were on and were turned off.
    private(set) var snapshot: Set<String> = []

    /// Starts `reason`. `turningOff` are the lights about to be turned off (those on in the
    /// trigger's scope; empty when the trigger isn't enabled but should still delay the restore).
    mutating func begin(_ reason: Reason, turningOff lights: Set<String>) {
        active.insert(reason)
        snapshot.formUnion(lights)
    }

    /// Ends `reason`. Returns the lights to turn back on once nothing holds them off; the
    /// snapshot is then cleared, whether or not they're restored.
    mutating func end(_ reason: Reason) -> Set<String> {
        active.remove(reason)
        guard active.isEmpty else { return [] }
        defer { snapshot = [] }
        return snapshot
    }
}

/// Settings keys for the automations.
enum NativeMacEventSettings {
    static let offOnSleepKey = "Native.automation.offOnSleep.v1"
    static let sleepScopeKey = "Native.automation.sleepScope.v1"
    static let offOnLockKey = "Native.automation.offOnLock.v1"
    static let lockScopeKey = "Native.automation.lockScope.v1"
    static let restoreKey = "Native.automation.restore.v1"
}

/// Watches sleep, wake, lock and unlock and applies the automations to the light manager.
///
/// Sleep: the light commands have to leave before the network goes down. LumenDesk registers for
/// IOKit's power notifications and holds the sleep for a few seconds while they're sent; if that
/// registration is refused, `NSWorkspace.willSleepNotification` still fires but macOS doesn't
/// wait, so some lights may miss the command. Bluetooth-only lights whose link is released or
/// reconnecting need longer than macOS allows.
///
/// Wake: lights come back once the Mac has been awake a few seconds and is on a network, since
/// Wi-Fi rejoins after the wake notification.
@MainActor
final class NativeMacEvents: ObservableObject {
    /// How long sleep is held while the off commands are sent. macOS allows up to 30 s.
    static let sleepHold: TimeInterval = 3
    /// How long after waking before lights are turned back on, for Wi-Fi to rejoin.
    static let wakeSettle: TimeInterval = 5
    /// How long to wait for a network after that before restoring anyway (Bluetooth lights).
    static let networkWait: TimeInterval = 30

    private(set) var suspension = NativeLightsSuspension()
    private weak var manager: LightManager?
    private weak var gate: NativeNetworkGate?
    private let defaults: UserDefaults
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var restoreTask: Task<Void, Never>?
    private var lastWake = Date.distantPast
    private var power: NativeSleepHold?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Starts watching. Safe to call more than once.
    func attach(_ manager: LightManager, gate: NativeNetworkGate) {
        guard self.manager == nil else { return }
        self.manager = manager
        self.gate = gate

        power = NativeSleepHold(hold: Self.sleepHold) { [weak self] in
            self?.begin(.sleep) ?? false
        }
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.willSleepNotification) { $0.begin(.sleep) }
        observe(workspace, NSWorkspace.didWakeNotification) { events in
            events.lastWake = Date()
            events.end(.sleep)
        }
        // Switching to another user leaves the Mac like locking it does.
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { $0.begin(.lock) }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { $0.end(.lock) }
        let distributed = DistributedNotificationCenter.default()
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) { $0.begin(.lock) }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) { $0.end(.lock) }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         _ handler: @escaping @MainActor (NativeMacEvents) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                handler(self)
            }
        }
        observers.append((center, token))
    }

    /// Returns whether any light was turned off.
    @discardableResult
    private func begin(_ reason: NativeLightsSuspension.Reason) -> Bool {
        guard let manager else { return false }
        restoreTask?.cancel()
        restoreTask = nil
        let enabledKey = reason == .sleep ? NativeMacEventSettings.offOnSleepKey : NativeMacEventSettings.offOnLockKey
        let scopeKey = reason == .sleep ? NativeMacEventSettings.sleepScopeKey : NativeMacEventSettings.lockScopeKey
        var lit: Set<String> = []
        if defaults.bool(forKey: enabledKey) {
            let scope = NativeAutomationScope.scope(from: defaults.string(forKey: scopeKey) ?? NativeAutomationScope.all,
                                                    rooms: manager.rooms)
            lit = Set(manager.devices(in: scope).filter(\.isOn).map(\.id))
        }
        suspension.begin(reason, turningOff: lit)
        if !lit.isEmpty {
            manager.setPower(deviceIDs: lit, on: false)
            manager.logActivity(.system, title: reason == .sleep ? "Lights off for sleep" : "Lights off for lock",
                                detail: "\(lit.count) light\(lit.count == 1 ? "" : "s")")
        }
        return !lit.isEmpty
    }

    private func end(_ reason: NativeLightsSuspension.Reason) {
        let lights = suspension.end(reason)
        let restore = defaults.object(forKey: NativeMacEventSettings.restoreKey) as? Bool ?? true
        guard !lights.isEmpty, restore else { return }
        restoreTask?.cancel()
        restoreTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let settle = self.lastWake.addingTimeInterval(Self.wakeSettle).timeIntervalSinceNow
            if settle > 0 { try? await Task.sleep(nanoseconds: UInt64(settle * 1_000_000_000)) }
            let deadline = Date().addingTimeInterval(Self.networkWait)
            while !Task.isCancelled, self.gate?.current == nil, Date() < deadline {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            guard !Task.isCancelled, let manager = self.manager else { return }
            let existing = Set(manager.devices.map(\.id)).intersection(lights)
            guard !existing.isEmpty else { return }
            manager.setPower(deviceIDs: existing, on: true)
            manager.logActivity(.system, title: "Lights back on", detail: "\(existing.count) light\(existing.count == 1 ? "" : "s")")
        }
    }
}

/// Holds system sleep briefly through IOKit's power notifications, so commands sent from
/// `onWillSleep` leave before the network goes down. Sleep isn't held when it sent none.
private final class NativeSleepHold {
    // IOKit's message constants are C macros Swift can't import (iokit_common_msg).
    private static let canSystemSleep: UInt32 = 0xE000_0270
    private static let systemWillSleep: UInt32 = 0xE000_0280

    private let hold: TimeInterval
    private let onWillSleep: () -> Bool
    private var rootPort: io_connect_t = 0
    private var notifyPort: IONotificationPortRef?
    private var notifier: io_object_t = 0

    init?(hold: TimeInterval, onWillSleep: @escaping () -> Bool) {
        self.hold = hold
        self.onWillSleep = onWillSleep
        let context = Unmanaged.passUnretained(self).toOpaque()
        rootPort = IORegisterForSystemPower(context, &notifyPort, { context, _, message, argument in
            guard let context else { return }
            Unmanaged<NativeSleepHold>.fromOpaque(context).takeUnretainedValue().handle(message, argument)
        }, &notifier)
        guard rootPort != 0, let notifyPort else { return nil }
        CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(notifyPort).takeUnretainedValue(),
                           .commonModes)
    }

    deinit {
        guard rootPort != 0 else { return }
        if let notifyPort {
            CFRunLoopRemoveSource(CFRunLoopGetMain(),
                                  IONotificationPortGetRunLoopSource(notifyPort).takeUnretainedValue(), .commonModes)
        }
        IODeregisterForSystemPower(&notifier)
        IOServiceClose(rootPort)
        if let notifyPort { IONotificationPortDestroy(notifyPort) }
    }

    /// Runs on the main run loop.
    private func handle(_ message: UInt32, _ argument: UnsafeMutableRawPointer?) {
        let notificationID = Int(bitPattern: argument)
        switch message {
        case Self.canSystemSleep:
            IOAllowPowerChange(rootPort, notificationID)
        case Self.systemWillSleep:
            guard onWillSleep() else {
                IOAllowPowerChange(rootPort, notificationID)
                return
            }
            let port = rootPort
            DispatchQueue.main.asyncAfter(deadline: .now() + hold) {
                IOAllowPowerChange(port, notificationID)
            }
        default:
            break
        }
    }
}
#endif

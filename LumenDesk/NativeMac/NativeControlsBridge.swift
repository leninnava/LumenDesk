#if os(macOS)
import AppIntents
import Combine
import Foundation
import WidgetKit

/// Fork: keeps the Control Center controls and the desktop widget in step with the lights.
///
/// The LumenDeskControls extension can't talk to lights or see `LightManager`; it draws whatever
/// the app last wrote to the App Group. This watches the manager and every light, and when the
/// room or all-lights state changes it writes a `ControlsSnapshot` and asks WidgetKit to reload
/// the controls and widgets. It also refreshes the App Shortcuts phrases when room or scene names
/// change (room, scene and light names are the phrases' parameters).
///
/// `isEnabled` is the hook for a future setting (menu bar vs Control Center); turning it off stops
/// publishing but leaves the last snapshot in place.
@MainActor
final class NativeControlsBridge {
    var isEnabled = true {
        didSet {
            guard isEnabled != oldValue else { return }
            if isEnabled { start() } else { stop() }
        }
    }

    private weak var manager: LightManager?
    private let store: ControlsStateStore
    private var managerObservers: Set<AnyCancellable> = []
    private var deviceObservers: [AnyCancellable] = []
    private var pending: Task<Void, Never>?
    private var lastPublished: ControlsSnapshot?
    private var lastShortcutNames: [String]?

    init(manager: LightManager, store: ControlsStateStore = .shared) {
        self.manager = manager
        self.store = store
    }

    /// Begins observing. Called once at launch; safe to call again.
    func start() {
        guard isEnabled, managerObservers.isEmpty, let manager else { return }
        manager.objectWillChange
            .sink { [weak self] _ in self?.schedulePublish() }
            .store(in: &managerObservers)
        // `devices` changes only when lights come and go; power lives on each LightDevice.
        manager.$devices
            .sink { [weak self] devices in self?.observe(devices) }
            .store(in: &managerObservers)
        schedulePublish()
    }

    func stop() {
        managerObservers.removeAll()
        deviceObservers.removeAll()
        pending?.cancel()
        pending = nil
    }

    /// Writes the snapshot now if it changed. Intents call this before returning, because the
    /// system reloads a control as soon as its intent's `perform()` finishes.
    func publishNow() {
        pending?.cancel()
        pending = nil
        guard isEnabled, let manager else { return }
        let snapshot = Self.snapshot(of: manager)
        refreshShortcutParameters(manager)
        if let lastPublished, lastPublished.hasSameContent(as: snapshot) { return }
        do {
            try store.save(snapshot)
            lastPublished = snapshot
        } catch {
            NSLog("LumenDesk: couldn't write the controls state: %@", error.localizedDescription)
            return
        }
        WidgetCenter.shared.reloadAllTimelines()
        if #available(macOS 26.0, *) {
            ControlCenter.shared.reloadAllControls()
        }
    }

    static func snapshot(of manager: LightManager, at date: Date = Date()) -> ControlsSnapshot {
        ControlsSnapshot.make(
            rooms: manager.rooms.map { (id: $0.id, name: $0.name, lightIDs: $0.lightIDs) },
            lights: manager.devices.map { (id: $0.id, isOn: $0.isOn) },
            at: date
        )
    }

    private func observe(_ devices: [LightDevice]) {
        deviceObservers = devices.map { device in
            device.objectWillChange.sink { [weak self] _ in self?.schedulePublish() }
        }
        schedulePublish()
    }

    /// Coalesces bursts (a scene touching ten lights, brightness drags) into one write.
    /// `objectWillChange` fires before the change lands, so the snapshot is taken afterwards.
    private func schedulePublish() {
        guard pending == nil else { return }
        pending = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self else { return }
            self.pending = nil
            self.publishNow()
        }
    }

    private func refreshShortcutParameters(_ manager: LightManager) {
        let names = manager.rooms.map(\.name) + ["|"] + manager.scenes.map(\.name)
            + ["|"] + manager.devices.map(\.label)
        guard names != lastShortcutNames else { return }
        lastShortcutNames = names
        LumenDeskShortcuts.updateAppShortcutParameters()
    }
}
#endif

import AppIntents
import Foundation

// Fork: Shortcuts, Siri and Spotlight actions. They are defined in the app target, so the system
// performs them in the app's process, where LightManager owns the light connections. If the app
// isn't running, the system launches it first.

enum PowerAction: String, AppEnum {
    case on, off, toggle

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Power")
    static let caseDisplayRepresentations: [PowerAction: DisplayRepresentation] = [
        .on: "on",
        .off: "off",
        .toggle: "toggle",
    ]

    /// The target state for lights that are currently `anyOn`. Toggle follows the app's
    /// "Toggle All Lights": anything on turns everything off.
    func resolved(anyOn: Bool) -> Bool {
        switch self {
        case .on: return true
        case .off: return false
        case .toggle: return !anyOn
        }
    }
}

/// The light commands behind every intent, on the main actor with the app's LightManager.
/// Commands go through `setPower(deviceIDs:on:)` and friends, which skip the confirmation alerts
/// the app shows for room and all-lights changes: a Shortcut or control can't answer an alert.
@MainActor
enum LightIntentActions {
    private static var services: AppServices { .shared }

    @discardableResult
    static func setLightPower(lightID: String, action: PowerAction) async throws -> (name: String, on: Bool) {
        await services.prepareForIntent { manager in manager.devices.contains { $0.id == lightID } }
        guard let device = services.manager.devices.first(where: { $0.id == lightID }) else {
            throw LightControlError.notFound("that light")
        }
        let on = action.resolved(anyOn: device.isOn)
        services.manager.setPower(deviceIDs: [device.id], on: on)
        publish()
        return (device.label, on)
    }

    @discardableResult
    static func setRoomPower(roomID: String, action: PowerAction) async throws -> (name: String, on: Bool) {
        let lights = try await roomLights(roomID: roomID)
        let on = action.resolved(anyOn: lights.lights.contains { $0.isOn })
        services.manager.setPower(deviceIDs: Set(lights.lights.map(\.id)), on: on)
        publish()
        return (lights.room.name, on)
    }

    static func setRoomPower(roomID: String, on: Bool) async throws {
        try await setRoomPower(roomID: roomID, action: on ? .on : .off)
    }

    @discardableResult
    static func setAllPower(action: PowerAction) async throws -> Bool {
        await services.prepareForIntent { !$0.devices.isEmpty }
        let lights = services.manager.devices
        guard !lights.isEmpty else { throw LightControlError.notFound("any lights") }
        let on = action.resolved(anyOn: lights.contains { $0.isOn })
        services.manager.setPower(deviceIDs: Set(lights.map(\.id)), on: on)
        publish()
        return on
    }

    static func setAllPower(on: Bool) async throws {
        try await setAllPower(action: on ? .on : .off)
    }

    /// Sets brightness (0–100) and turns on any of the lights that are off.
    static func setBrightness(deviceIDs: Set<String>, percent: Int) {
        let manager = services.manager
        let value = Double(min(100, max(1, percent))) / 100
        let off = manager.devices.filter { deviceIDs.contains($0.id) && !$0.isOn }.map(\.id)
        if !off.isEmpty { manager.setPower(deviceIDs: Set(off), on: true) }
        manager.setBrightness(deviceIDs: deviceIDs, value: value)
        publish()
    }

    static func roomLights(roomID: String) async throws -> (room: Room, lights: [LightDevice]) {
        guard let uuid = UUID(uuidString: roomID),
              let room = services.manager.rooms.first(where: { $0.id == uuid }) else {
            throw LightControlError.notFound("that room")
        }
        await services.prepareForIntent { !$0.devices(in: room).isEmpty }
        let lights = services.manager.devices(in: room)
        guard !lights.isEmpty else { throw LightControlError.notFound("any lights in \(room.name)") }
        return (room, lights)
    }

    static func applyScene(sceneID: String) async throws -> String {
        guard let uuid = UUID(uuidString: sceneID),
              let scene = services.manager.scenes.first(where: { $0.id == uuid }) else {
            throw LightControlError.notFound("that scene")
        }
        await services.prepareForIntent { manager in
            manager.devices.contains { scene.snapshots[$0.id] != nil }
        }
        guard services.manager.devices.contains(where: { scene.snapshots[$0.id] != nil }) else {
            throw LightControlError.notFound("the lights in \(scene.name)")
        }
        // Asking Siri or running a Shortcut is the review; the app's alert would block it.
        services.manager.applyScene(scene, allowTurningOff: true, reviewed: true)
        publish()
        return scene.name
    }

    /// Writes the controls snapshot before the intent returns, because the system reloads
    /// controls and widgets as soon as `perform()` finishes.
    private static func publish() {
        #if os(macOS)
        services.controlsBridge.publishNow()
        #endif
    }
}

// MARK: - Intents

struct LightPowerIntent: AppIntent {
    static let title: LocalizedStringResource = "Turn Light On or Off"
    static let description = IntentDescription("Turns a LumenDesk light on, off, or toggles it.")

    @Parameter(title: "Light")
    var light: LightEntity

    @Parameter(title: "Power", default: .toggle)
    var action: PowerAction

    static var parameterSummary: some ParameterSummary {
        Summary("Turn \(\.$light) \(\.$action)")
    }

    init() {}

    init(action: PowerAction) {
        self.action = action
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = try await LightIntentActions.setLightPower(lightID: light.id, action: action)
        return .result(dialog: "Turned \(result.name) \(result.on ? "on" : "off").")
    }
}

struct RoomPowerIntent: AppIntent {
    static let title: LocalizedStringResource = "Turn Room On or Off"
    static let description = IntentDescription("Turns every light in a LumenDesk room on, off, or toggles them.")

    @Parameter(title: "Room")
    var room: RoomEntity

    @Parameter(title: "Power", default: .toggle)
    var action: PowerAction

    static var parameterSummary: some ParameterSummary {
        Summary("Turn \(\.$room) \(\.$action)")
    }

    init() {}

    init(action: PowerAction) {
        self.action = action
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = try await LightIntentActions.setRoomPower(roomID: room.id, action: action)
        return .result(dialog: "Turned \(result.name) \(result.on ? "on" : "off").")
    }
}

struct AllLightsPowerIntent: AppIntent {
    static let title: LocalizedStringResource = "Turn All Lights On or Off"
    static let description = IntentDescription("Turns every light LumenDesk has found on, off, or toggles them.")

    @Parameter(title: "Power", default: .toggle)
    var action: PowerAction

    static var parameterSummary: some ParameterSummary {
        Summary("Turn all lights \(\.$action)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let on = try await LightIntentActions.setAllPower(action: action)
        return .result(dialog: "Turned all lights \(on ? "on" : "off").")
    }
}

struct SetLightBrightnessIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Light Brightness"
    static let description = IntentDescription("Sets a LumenDesk light's brightness, turning it on if needed.")

    @Parameter(title: "Light")
    var light: LightEntity

    @Parameter(title: "Brightness", default: 50, inclusiveRange: (1, 100))
    var brightness: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Set \(\.$light) to \(\.$brightness)%")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        await AppServices.shared.prepareForIntent { manager in manager.devices.contains { $0.id == light.id } }
        guard AppServices.shared.manager.devices.contains(where: { $0.id == light.id }) else {
            throw LightControlError.notFound(light.name)
        }
        LightIntentActions.setBrightness(deviceIDs: [light.id], percent: brightness)
        return .result(dialog: "Set \(light.name) to \(brightness)%.")
    }
}

struct SetRoomBrightnessIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Room Brightness"
    static let description = IntentDescription("Sets the brightness of every light in a LumenDesk room, turning them on if needed.")

    @Parameter(title: "Room")
    var room: RoomEntity

    @Parameter(title: "Brightness", default: 50, inclusiveRange: (1, 100))
    var brightness: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Set \(\.$room) to \(\.$brightness)%")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let target = try await LightIntentActions.roomLights(roomID: room.id)
        LightIntentActions.setBrightness(deviceIDs: Set(target.lights.map(\.id)), percent: brightness)
        return .result(dialog: "Set \(target.room.name) to \(brightness)%.")
    }
}

struct ApplySceneIntent: AppIntent {
    static let title: LocalizedStringResource = "Apply Scene"
    static let description = IntentDescription("Applies a saved LumenDesk scene.")

    @Parameter(title: "Scene")
    var scene: SceneEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Apply \(\.$scene)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let name = try await LightIntentActions.applyScene(sceneID: scene.id)
        return .result(dialog: "Applied \(name).")
    }
}

// MARK: - App Shortcuts

/// Phrases Siri and Spotlight offer without any setup. Every phrase names the app and uses at
/// most one parameter, as App Shortcuts require, so on and off get a shortcut each. Room, light
/// and scene names come from the entity queries; call `updateAppShortcutParameters()` when they
/// change (NativeControlsBridge does on macOS).
struct LumenDeskShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AllLightsPowerIntent(), phrases: [
            "Turn \(\.$action) all lights in \(.applicationName)",
            "Turn \(\.$action) the lights with \(.applicationName)",
            "Toggle the lights in \(.applicationName)",
        ])
        AppShortcut(intent: RoomPowerIntent(action: .on), phrases: [
            "Turn on \(\.$room) in \(.applicationName)",
            "Turn \(\.$room) on with \(.applicationName)",
        ])
        AppShortcut(intent: RoomPowerIntent(action: .off), phrases: [
            "Turn off \(\.$room) in \(.applicationName)",
            "Turn \(\.$room) off with \(.applicationName)",
        ])
        AppShortcut(intent: RoomPowerIntent(action: .toggle), phrases: [
            "Toggle \(\.$room) in \(.applicationName)",
        ])
        AppShortcut(intent: LightPowerIntent(action: .on), phrases: [
            "Turn on \(\.$light) in \(.applicationName)",
        ])
        AppShortcut(intent: LightPowerIntent(action: .off), phrases: [
            "Turn off \(\.$light) in \(.applicationName)",
        ])
        AppShortcut(intent: ApplySceneIntent(), phrases: [
            "Apply \(\.$scene) in \(.applicationName)",
            "Set \(.applicationName) to \(\.$scene)",
        ])
        AppShortcut(intent: SetRoomBrightnessIntent(), phrases: [
            "Set \(\.$room) brightness in \(.applicationName)",
            "Dim \(\.$room) in \(.applicationName)",
        ])
    }
}

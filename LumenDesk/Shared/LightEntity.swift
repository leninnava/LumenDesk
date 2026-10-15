import AppIntents
import Foundation

/// A LumenDesk light for Shortcuts, Siri, and the per-light control and widget (fork).
///
/// Compiled into the app and the LumenDeskControls extension, like `RoomEntity`. In the app the
/// query reads the live `LightManager`; in the extension it reads the snapshot the app last wrote
/// to the App Group.
struct LightEntity: AppEntity, Identifiable, Hashable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Light")
    static let defaultQuery = LightEntityQuery()

    /// `LightDevice.id`.
    let id: String
    let name: String
    let detail: String

    init(id: String, name: String, detail: String) {
        self.id = id
        self.name = name
        self.detail = detail
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(detail)")
    }
}

struct LightEntityQuery: EntityStringQuery {
    #if LUMENDESK_WIDGET_EXTENSION
    func entities(for identifiers: [String]) async throws -> [LightEntity] {
        let all = Self.allLights()
        return identifiers.compactMap { id in all.first { $0.id == id } }
    }

    func entities(matching string: String) async throws -> [LightEntity] {
        Self.allLights().filter { $0.name.localizedCaseInsensitiveContains(string) }
    }

    func suggestedEntities() async throws -> [LightEntity] {
        Self.allLights()
    }

    static func allLights() -> [LightEntity] {
        let snapshot = ControlsStateStore.shared.load()
        return snapshot.lights.map { light in
            LightEntity(id: light.id, name: light.name,
                        detail: light.roomID.flatMap { snapshot.room(id: $0)?.name } ?? "")
        }
    }
    #else
    @MainActor
    func entities(for identifiers: [String]) async throws -> [LightEntity] {
        // Lights are rediscovered on launch; give a cold-launched app a moment to find them.
        await AppServices.shared.prepareForIntent { manager in
            identifiers.allSatisfy { id in manager.devices.contains { $0.id == id } }
        }
        let all = Self.allLights()
        return identifiers.compactMap { id in all.first { $0.id == id } }
    }

    @MainActor
    func entities(matching string: String) async throws -> [LightEntity] {
        await AppServices.shared.prepareForIntent { !$0.devices.isEmpty }
        return Self.allLights().filter { $0.name.localizedCaseInsensitiveContains(string) }
    }

    @MainActor
    func suggestedEntities() async throws -> [LightEntity] {
        await AppServices.shared.prepareForIntent { !$0.devices.isEmpty }
        return Self.allLights()
    }

    @MainActor
    static func allLights() -> [LightEntity] {
        let manager = AppServices.shared.manager
        return manager.devices.map { device in
            LightEntity(device, room: manager.rooms.first { $0.lightIDs.contains(device.id) })
        }
    }
    #endif
}

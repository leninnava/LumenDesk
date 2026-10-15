import AppIntents
import Foundation

// Fork: lights and scenes as App Intents entities, backed by the running app's LightManager.
// Rooms are in Shared/RoomEntity.swift because the controls extension needs them too.

struct LightEntity: AppEntity, Identifiable, Hashable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Light")
    static let defaultQuery = LightEntityQuery()

    /// `LightDevice.id`.
    let id: String
    let name: String
    let detail: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(detail)")
    }

    @MainActor
    init(_ device: LightDevice, room: Room?) {
        id = device.id
        name = device.label
        detail = [room?.name, device.brand.displayName].compactMap { $0 }.joined(separator: " · ")
    }
}

struct LightEntityQuery: EntityStringQuery {
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
}

struct SceneEntity: AppEntity, Identifiable, Hashable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Scene")
    static let defaultQuery = SceneEntityQuery()

    /// The scene's UUID string.
    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct SceneEntityQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [SceneEntity] {
        let all = Self.allScenes()
        return identifiers.compactMap { id in all.first { $0.id == id } }
    }

    @MainActor
    func entities(matching string: String) async throws -> [SceneEntity] {
        Self.allScenes().filter { $0.name.localizedCaseInsensitiveContains(string) }
    }

    @MainActor
    func suggestedEntities() async throws -> [SceneEntity] {
        Self.allScenes()
    }

    @MainActor
    static func allScenes() -> [SceneEntity] {
        AppServices.shared.manager.scenes.map { SceneEntity(id: $0.id.uuidString, name: $0.name) }
    }
}

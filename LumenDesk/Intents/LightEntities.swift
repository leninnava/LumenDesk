import AppIntents
import Foundation

// Fork: lights and scenes as App Intents entities, backed by the running app's LightManager.
// Rooms and lights are in Shared/ because the controls extension needs them too.

extension LightEntity {
    @MainActor
    init(_ device: LightDevice, room: Room?) {
        self.init(id: device.id, name: device.label,
                  detail: [room?.name, device.brand.displayName].compactMap { $0 }.joined(separator: " · "))
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

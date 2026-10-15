import AppIntents
import Foundation

/// A LumenDesk room for Shortcuts, Siri and the room control (fork).
///
/// Compiled into the app and the LumenDeskControls extension so both agree on the type. In the
/// app the query reads the live `LightManager`; in the extension, which has no light connections,
/// it reads the snapshot the app last wrote to the App Group.
struct RoomEntity: AppEntity, Identifiable, Hashable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Room")
    static let defaultQuery = RoomEntityQuery()

    /// The room's UUID string.
    let id: String
    let name: String
    let lightCount: Int

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)",
                              subtitle: "\(lightCount) light\(lightCount == 1 ? "" : "s")")
    }
}

struct RoomEntityQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [RoomEntity] {
        let all = await RoomEntityQuery.allRooms()
        return identifiers.compactMap { id in all.first { $0.id == id } }
    }

    func entities(matching string: String) async throws -> [RoomEntity] {
        await RoomEntityQuery.allRooms().filter { $0.name.localizedCaseInsensitiveContains(string) }
    }

    func suggestedEntities() async throws -> [RoomEntity] {
        await RoomEntityQuery.allRooms()
    }

    #if LUMENDESK_WIDGET_EXTENSION
    static func allRooms() async -> [RoomEntity] {
        ControlsStateStore.shared.load().rooms.map {
            RoomEntity(id: $0.id, name: $0.name, lightCount: $0.lightCount)
        }
    }
    #else
    @MainActor
    static func allRooms() async -> [RoomEntity] {
        let manager = AppServices.shared.manager
        return manager.rooms.map {
            RoomEntity(id: $0.id.uuidString, name: $0.name, lightCount: $0.lightIDs.count)
        }
    }
    #endif
}

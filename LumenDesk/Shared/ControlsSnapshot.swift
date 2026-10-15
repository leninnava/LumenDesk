import Foundation

/// What the Control Center controls and desktop widget show (fork).
///
/// Compiled into the app and the LumenDeskControls extension. Only the app talks to lights, so it
/// writes this snapshot to the shared App Group container whenever a light or room changes; the
/// extension reads it to draw toggles. Values are derived from the lights LumenDesk has found, so
/// a room whose lights haven't answered yet reads as off with no lights.
struct ControlsSnapshot: Codable, Equatable {
    struct Room: Codable, Equatable, Identifiable {
        let id: String
        let name: String
        let lightCount: Int
        let onCount: Int

        /// A room counts as on when any of its lights is on, like the menu bar's room switch.
        var isOn: Bool { onCount > 0 }
    }

    /// One light, for the per-light control and the Room Lights widget.
    struct Light: Codable, Equatable, Identifiable {
        let id: String
        let name: String
        let roomID: String?
        let isOn: Bool
        /// 0–100.
        let brightness: Int
        let isReachable: Bool
    }

    var rooms: [Room]
    var lights: [Light]
    var lightCount: Int
    var onCount: Int
    var updatedAt: Date

    var anyOn: Bool { onCount > 0 }

    static let empty = ControlsSnapshot(rooms: [], lights: [], lightCount: 0, onCount: 0, updatedAt: .distantPast)

    func room(id: String) -> Room? { rooms.first { $0.id == id } }

    func light(id: String) -> Light? { lights.first { $0.id == id } }

    /// The room's lights, or every light when `roomID` is nil.
    func lights(inRoom roomID: String?) -> [Light] {
        guard let roomID else { return lights }
        return lights.filter { $0.roomID == roomID }
    }

    /// Builds the snapshot from plain values so it can be tested without a `LightManager`.
    ///
    /// - Parameters:
    ///   - rooms: rooms in display order, with the light IDs assigned to each.
    ///   - lights: every light found so far and whether it is on.
    static func make(rooms: [(id: UUID, name: String, lightIDs: [String])],
                     lights: [(id: String, name: String, isOn: Bool, brightness: Int, isReachable: Bool)],
                     at date: Date = Date()) -> ControlsSnapshot {
        var power: [String: Bool] = [:]
        for light in lights { power[light.id] = light.isOn }
        var roomOfLight: [String: String] = [:]
        for room in rooms { for id in room.lightIDs where roomOfLight[id] == nil { roomOfLight[id] = room.id.uuidString } }
        let snapshotRooms = rooms.map { room -> Room in
            let present = room.lightIDs.compactMap { power[$0] }
            return Room(id: room.id.uuidString, name: room.name,
                        lightCount: present.count, onCount: present.filter { $0 }.count)
        }
        let snapshotLights = lights.map {
            Light(id: $0.id, name: $0.name, roomID: roomOfLight[$0.id], isOn: $0.isOn,
                  brightness: min(100, max(0, $0.brightness)), isReachable: $0.isReachable)
        }
        return ControlsSnapshot(rooms: snapshotRooms, lights: snapshotLights, lightCount: power.count,
                                onCount: power.values.filter { $0 }.count, updatedAt: date)
    }

    /// Power-only form; names default to the IDs.
    static func make(rooms: [(id: UUID, name: String, lightIDs: [String])],
                     lights: [(id: String, isOn: Bool)],
                     at date: Date = Date()) -> ControlsSnapshot {
        make(rooms: rooms,
             lights: lights.map { (id: $0.id, name: $0.id, isOn: $0.isOn, brightness: 100, isReachable: true) },
             at: date)
    }

    func hasSameContent(as other: ControlsSnapshot) -> Bool {
        rooms == other.rooms && lights == other.lights && lightCount == other.lightCount && onCount == other.onCount
    }
}

/// Reads and writes `ControlsSnapshot` in the App Group container shared by the app and the
/// LumenDeskControls extension.
///
/// The group is `<team ID>.com.lumendesk.LumenDesk`: a team-prefixed macOS app group, which needs
/// no registration or provisioning profile. Both Info.plists carry it as `LumenDeskAppGroup`,
/// expanded from `$(DEVELOPMENT_TEAM)` at build time, so it always matches the signing team.
extension ControlsSnapshot {
    private enum CodingKeys: String, CodingKey {
        case rooms, lights, lightCount, onCount, updatedAt
    }

    /// Snapshots written before per-light entries existed decode with no lights.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rooms = try container.decode([Room].self, forKey: .rooms)
        lights = try container.decodeIfPresent([Light].self, forKey: .lights) ?? []
        lightCount = try container.decode(Int.self, forKey: .lightCount)
        onCount = try container.decode(Int.self, forKey: .onCount)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

struct ControlsStateStore {
    static let fileName = "controls-state.json"
    static let infoPlistKey = "LumenDeskAppGroup"

    let fileURL: URL?

    init(fileURL: URL?) {
        self.fileURL = fileURL
    }

    /// The store in the App Group container, or one that reads empty and drops writes when the
    /// group isn't configured (unsigned builds, iOS).
    static var shared: ControlsStateStore {
        ControlsStateStore(fileURL: containerURL()?.appendingPathComponent(fileName))
    }

    static var groupIdentifier: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: infoPlistKey) as? String,
              !value.isEmpty, !value.hasPrefix("$(") else { return nil }
        return value
    }

    private static func containerURL() -> URL? {
        guard let group = groupIdentifier else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
    }

    func load() -> ControlsSnapshot {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return .empty }
        return (try? Self.decoder.decode(ControlsSnapshot.self, from: data)) ?? .empty
    }

    func save(_ snapshot: ControlsSnapshot) throws {
        guard let fileURL else { return }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Self.encoder.encode(snapshot).write(to: fileURL, options: .atomic)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

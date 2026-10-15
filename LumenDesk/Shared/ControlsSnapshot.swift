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

    var rooms: [Room]
    var lightCount: Int
    var onCount: Int
    var updatedAt: Date

    var anyOn: Bool { onCount > 0 }

    static let empty = ControlsSnapshot(rooms: [], lightCount: 0, onCount: 0, updatedAt: .distantPast)

    func room(id: String) -> Room? { rooms.first { $0.id == id } }

    /// Builds the snapshot from plain values so it can be tested without a `LightManager`.
    ///
    /// - Parameters:
    ///   - rooms: rooms in display order, with the light IDs assigned to each.
    ///   - lights: every light found so far and whether it is on.
    static func make(rooms: [(id: UUID, name: String, lightIDs: [String])],
                     lights: [(id: String, isOn: Bool)],
                     at date: Date = Date()) -> ControlsSnapshot {
        var power: [String: Bool] = [:]
        for light in lights { power[light.id] = light.isOn }
        let snapshotRooms = rooms.map { room -> Room in
            let present = room.lightIDs.compactMap { power[$0] }
            return Room(id: room.id.uuidString, name: room.name,
                        lightCount: present.count, onCount: present.filter { $0 }.count)
        }
        return ControlsSnapshot(rooms: snapshotRooms, lightCount: power.count,
                                onCount: power.values.filter { $0 }.count, updatedAt: date)
    }

    /// Equal apart from the timestamp, so the app only writes (and reloads controls) on change.
    func hasSameContent(as other: ControlsSnapshot) -> Bool {
        rooms == other.rooms && lightCount == other.lightCount && onCount == other.onCount
    }
}

/// Reads and writes `ControlsSnapshot` in the App Group container shared by the app and the
/// LumenDeskControls extension.
///
/// The group is `<team ID>.com.lumendesk.LumenDesk`: a team-prefixed macOS app group, which needs
/// no registration or provisioning profile. Both Info.plists carry it as `LumenDeskAppGroup`,
/// expanded from `$(DEVELOPMENT_TEAM)` at build time, so it always matches the signing team.
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

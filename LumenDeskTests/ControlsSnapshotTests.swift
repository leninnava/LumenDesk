import XCTest
@testable import LumenDesk

final class ControlsSnapshotTests: XCTestCase {
    private let kitchen = UUID()
    private let office = UUID()

    func testRoomsCountOnlyLightsThatHaveBeenFound() {
        let snapshot = ControlsSnapshot.make(
            rooms: [(id: kitchen, name: "Kitchen", lightIDs: ["a", "b", "missing"]),
                    (id: office, name: "Office", lightIDs: ["c"])],
            lights: [(id: "a", isOn: true), (id: "b", isOn: false), (id: "c", isOn: false), (id: "d", isOn: true)]
        )

        XCTAssertEqual(snapshot.rooms.map(\.name), ["Kitchen", "Office"])
        XCTAssertEqual(snapshot.room(id: kitchen.uuidString)?.lightCount, 2)
        XCTAssertEqual(snapshot.room(id: kitchen.uuidString)?.isOn, true)
        XCTAssertEqual(snapshot.room(id: office.uuidString)?.isOn, false)
        XCTAssertEqual(snapshot.lightCount, 4)
        XCTAssertEqual(snapshot.onCount, 2)
        XCTAssertTrue(snapshot.anyOn)
    }

    func testRoomWithNoFoundLightsIsOff() {
        let snapshot = ControlsSnapshot.make(rooms: [(id: kitchen, name: "Kitchen", lightIDs: ["a"])], lights: [] as [(id: String, isOn: Bool)])

        XCTAssertEqual(snapshot.room(id: kitchen.uuidString)?.lightCount, 0)
        XCTAssertEqual(snapshot.room(id: kitchen.uuidString)?.isOn, false)
        XCTAssertFalse(snapshot.anyOn)
    }

    func testSameContentIgnoresTimestamp() {
        let rooms = [(id: kitchen, name: "Kitchen", lightIDs: ["a"])]
        let first = ControlsSnapshot.make(rooms: rooms, lights: [(id: "a", isOn: true)], at: Date(timeIntervalSince1970: 1))
        let later = ControlsSnapshot.make(rooms: rooms, lights: [(id: "a", isOn: true)], at: Date(timeIntervalSince1970: 2))
        let switchedOff = ControlsSnapshot.make(rooms: rooms, lights: [(id: "a", isOn: false)])

        XCTAssertTrue(first.hasSameContent(as: later))
        XCTAssertFalse(first.hasSameContent(as: switchedOff))
    }

    func testStoreRoundTripsThroughDisk() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ControlsStateStore(fileURL: directory.appendingPathComponent(ControlsStateStore.fileName))
        let snapshot = ControlsSnapshot.make(rooms: [(id: kitchen, name: "Kitchen", lightIDs: ["a"])],
                                             lights: [(id: "a", isOn: true)],
                                             at: Date(timeIntervalSince1970: 1_800_000_000))

        XCTAssertEqual(store.load(), .empty)
        try store.save(snapshot)
        XCTAssertEqual(store.load(), snapshot)
    }

    func testUnconfiguredStoreReadsEmptyAndIgnoresWrites() throws {
        let store = ControlsStateStore(fileURL: nil)
        try store.save(ControlsSnapshot.make(rooms: [], lights: [(id: "a", isOn: true)]))
        XCTAssertEqual(store.load(), .empty)
    }

    func testCorruptFileReadsEmpty() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(ControlsStateStore.fileName)
        try Data("not json".utf8).write(to: url)

        XCTAssertEqual(ControlsStateStore(fileURL: url).load(), .empty)
    }

    func testPowerActionToggleFollowsAnyLightOn() {
        XCTAssertFalse(PowerAction.toggle.resolved(anyOn: true))
        XCTAssertTrue(PowerAction.toggle.resolved(anyOn: false))
        XCTAssertTrue(PowerAction.on.resolved(anyOn: true))
        XCTAssertFalse(PowerAction.off.resolved(anyOn: false))
    }

    @MainActor
    func testRoomEntityQueryReturnsTheManagersRooms() async throws {
        let rooms = await RoomEntityQuery.allRooms()
        XCTAssertEqual(rooms.map(\.id), AppServices.shared.manager.rooms.map(\.id.uuidString))
        let missing = try await RoomEntityQuery().entities(for: [UUID().uuidString])
        XCTAssertTrue(missing.isEmpty)
    }

    func testLightsCarryNameRoomAndState() throws {
        let kitchen = UUID()
        let snapshot = ControlsSnapshot.make(
            rooms: [(id: kitchen, name: "Kitchen", lightIDs: ["a"])],
            lights: [(id: "a", name: "Ceiling", isOn: true, brightness: 60, isReachable: true),
                     (id: "b", name: "Lamp", isOn: false, brightness: 140, isReachable: false)])
        let ceiling = try XCTUnwrap(snapshot.light(id: "a"))
        XCTAssertEqual(ceiling.name, "Ceiling")
        XCTAssertEqual(ceiling.roomID, kitchen.uuidString)
        XCTAssertEqual(ceiling.brightness, 60)
        XCTAssertEqual(snapshot.light(id: "b")?.brightness, 100)
        XCTAssertNil(snapshot.light(id: "b")?.roomID)
        XCTAssertEqual(snapshot.lights(inRoom: kitchen.uuidString).map(\.id), ["a"])
        XCTAssertEqual(snapshot.lights(inRoom: nil).count, 2)
    }

    func testLightChangesCountAsNewContent() {
        let rooms: [(id: UUID, name: String, lightIDs: [String])] = []
        let before = ControlsSnapshot.make(rooms: rooms, lights: [(id: "a", name: "A", isOn: true, brightness: 50, isReachable: true)])
        let dimmed = ControlsSnapshot.make(rooms: rooms, lights: [(id: "a", name: "A", isOn: true, brightness: 20, isReachable: true)])
        XCTAssertFalse(before.hasSameContent(as: dimmed))
    }

    func testSnapshotsWrittenBeforeLightsExistedStillDecode() throws {
        let old = #"{"lightCount":1,"onCount":1,"rooms":[{"id":"r","lightCount":1,"name":"Office","onCount":1}],"updatedAt":"2026-10-15T20:00:00Z"}"#
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("controls-state.json")
        try Data(old.utf8).write(to: file)
        let snapshot = ControlsStateStore(fileURL: file).load()
        XCTAssertEqual(snapshot.rooms.first?.name, "Office")
        XCTAssertEqual(snapshot.lights, [])
        XCTAssertTrue(snapshot.anyOn)
    }
}

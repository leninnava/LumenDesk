import XCTest
@testable import LumenDesk

/// Fork: the restore snapshot behind the sleep and lock automations, and their scope setting.
final class NativeMacEventsTests: XCTestCase {
    func testSleepThenWakeRestoresWhatWasTurnedOff() {
        var state = NativeLightsSuspension()
        state.begin(.sleep, turningOff: ["a", "b"])
        XCTAssertEqual(state.end(.sleep), ["a", "b"])
        XCTAssertEqual(state, NativeLightsSuspension(), "the snapshot is used once")
    }

    func testWakingToALockedScreenWaitsForUnlock() {
        var state = NativeLightsSuspension()
        state.begin(.lock, turningOff: [])  // locking isn't set to turn lights off
        state.begin(.sleep, turningOff: ["a"])
        XCTAssertEqual(state.end(.sleep), [])
        XCTAssertEqual(state.end(.lock), ["a"])
    }

    func testSecondTriggerAddsToTheSnapshot() {
        var state = NativeLightsSuspension()
        state.begin(.lock, turningOff: ["a"])
        // Sleep finds only what's still on; what locking turned off must not be forgotten.
        state.begin(.sleep, turningOff: ["b"])
        XCTAssertEqual(state.end(.lock), [])
        XCTAssertEqual(state.end(.sleep), ["a", "b"])
    }

    func testRepeatedNotificationsDontDoubleCount() {
        var state = NativeLightsSuspension()
        // IOKit and NSWorkspace both report sleep.
        state.begin(.sleep, turningOff: ["a"])
        state.begin(.sleep, turningOff: [])
        XCTAssertEqual(state.end(.sleep), ["a"])
        XCTAssertEqual(state.end(.sleep), [])
    }

    func testEndWithoutBeginRestoresNothing() {
        var state = NativeLightsSuspension()
        XCTAssertEqual(state.end(.lock), [])
        XCTAssertEqual(state.end(.sleep), [])
    }

    func testLightsTurnedOffWhileOtherReasonEndedAreKeptForTheLaterOne() {
        var state = NativeLightsSuspension()
        state.begin(.sleep, turningOff: ["a"])
        XCTAssertEqual(state.end(.sleep), ["a"])
        state.begin(.lock, turningOff: ["b"])
        XCTAssertEqual(state.end(.lock), ["b"], "an earlier restore doesn't leak into the next one")
    }

    func testScopeFallsBackToAllLightsForMissingRooms() {
        let room = Room(name: "Office")
        XCTAssertEqual(NativeAutomationScope.scope(from: "all", rooms: [room]), .all)
        XCTAssertEqual(NativeAutomationScope.scope(from: room.id.uuidString, rooms: [room]), .room(room.id))
        XCTAssertEqual(NativeAutomationScope.scope(from: UUID().uuidString, rooms: [room]), .all)
        XCTAssertEqual(NativeAutomationScope.scope(from: "garbage", rooms: []), .all)
        XCTAssertEqual(NativeAutomationScope.stored(.room(room.id)), room.id.uuidString)
        XCTAssertEqual(NativeAutomationScope.stored(.all), "all")
    }
}

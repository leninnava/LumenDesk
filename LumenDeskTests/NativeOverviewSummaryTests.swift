#if os(macOS)
import XCTest
@testable import LumenDesk

final class NativeOverviewSummaryTests: XCTestCase {
    func testHeadlineDescribesHowManyLightsAreOn() {
        XCTAssertEqual(NativeOverviewSummary.headline(on: 0, total: 0), "No lights yet")
        XCTAssertEqual(NativeOverviewSummary.headline(on: 0, total: 5), "All lights are off")
        XCTAssertEqual(NativeOverviewSummary.headline(on: 3, total: 5), "3 of 5 lights are on")
        XCTAssertEqual(NativeOverviewSummary.headline(on: 5, total: 5), "All 5 lights are on")
    }

    func testHeadlineForASingleLight() {
        XCTAssertEqual(NativeOverviewSummary.headline(on: 1, total: 1), "Your light is on")
        XCTAssertEqual(NativeOverviewSummary.headline(on: 0, total: 1), "Your light is off")
    }

    func testNotRespondingNoteIsOmittedWhenEveryLightAnswers() {
        XCTAssertNil(NativeOverviewSummary.notRespondingNote(0))
        XCTAssertEqual(NativeOverviewSummary.notRespondingNote(1),
                       "1 light isn’t responding. Check that it’s switched on at the wall.")
        XCTAssertEqual(NativeOverviewSummary.notRespondingNote(2),
                       "2 lights aren’t responding. Check that they’re switched on at the wall.")
    }

    func testGroupStatus() {
        XCTAssertEqual(NativeOverviewSummary.groupStatus(on: 0, total: 0), "No lights yet")
        XCTAssertEqual(NativeOverviewSummary.groupStatus(on: 1, total: 1), "On")
        XCTAssertEqual(NativeOverviewSummary.groupStatus(on: 0, total: 1), "Off")
        XCTAssertEqual(NativeOverviewSummary.groupStatus(on: 2, total: 3), "2 of 3 on")
        XCTAssertEqual(NativeOverviewSummary.groupStatus(on: 0, total: 3), "0 of 3 on")
    }

    func testLightStatus() {
        XCTAssertEqual(NativeOverviewSummary.lightStatus(isOn: true, brightness: 0.6, isStale: false), "On · 60%")
        XCTAssertEqual(NativeOverviewSummary.lightStatus(isOn: false, brightness: 0.6, isStale: false), "Off")
        XCTAssertEqual(NativeOverviewSummary.lightStatus(isOn: true, brightness: 0.6, isStale: true), "Not responding")
        XCTAssertEqual(NativeOverviewSummary.lightStatus(isOn: true, brightness: 0.6, isStale: true, detailed: true),
                       "Not responding — check it’s powered")
    }

    func testPercentRoundsAndClamps() {
        XCTAssertEqual(NativeOverviewSummary.percent(0.624), "62%")
        XCTAssertEqual(NativeOverviewSummary.percent(0.006), "1%")
        XCTAssertEqual(NativeOverviewSummary.percent(1.4), "100%")
        XCTAssertEqual(NativeOverviewSummary.percent(-0.2), "0%")
    }

    func testLightCount() {
        XCTAssertEqual(NativeOverviewSummary.lightCount(1), "1 light")
        XCTAssertEqual(NativeOverviewSummary.lightCount(4), "4 lights")
    }
}
#endif

#if os(macOS)
import XCTest
@testable import LumenDesk

final class NativeScheduleDraftTests: XCTestCase {
    func testTimedEntryRoundTripsThroughDraft() {
        let id = UUID()
        let entry = ScheduleEntry(id: id, isEnabled: false, hour: 22, minute: 15, action: .dim25, weekdays: [2, 4])
        let draft = NativeScheduleDraft(entry: entry)

        XCTAssertEqual(draft.trigger, .time)
        XCTAssertEqual(draft.action, .dim25)
        XCTAssertEqual(draft.hour, 22)
        XCTAssertEqual(draft.minute, 15)
        XCTAssertEqual(draft.weekdays, [2, 4])
        XCTAssertEqual(draft.entry(id: id, isEnabled: false), entry)
    }

    func testSunriseAndSunsetMapToTheirActionsAndKeepOffset() {
        var draft = NativeScheduleDraft()
        draft.trigger = .sunrise
        draft.offsetMinutes = -30
        draft.action = .dim50 // ignored for sun-relative schedules
        XCTAssertEqual(draft.entry().action, .atSunrise)
        XCTAssertEqual(draft.entry().offsetMinutes, -30)

        draft.trigger = .sunset
        XCTAssertEqual(draft.entry().action, .atSunset)

        let back = NativeScheduleDraft(entry: draft.entry())
        XCTAssertEqual(back.trigger, .sunset)
        XCTAssertEqual(back.offsetMinutes, -30)
    }

    func testTimedScheduleDropsAnyLeftoverOffset() {
        var draft = NativeScheduleDraft()
        draft.trigger = .sunset
        draft.offsetMinutes = 45
        draft.trigger = .time
        XCTAssertEqual(draft.entry().offsetMinutes, 0)
        XCTAssertEqual(draft.entry().action, .turnOn)
    }

    func testEmptyWeekdaysInEntryMeanEveryDayInEditor() {
        let entry = ScheduleEntry(hour: 7, minute: 0, action: .turnOn, weekdays: [])
        XCTAssertEqual(NativeScheduleDraft(entry: entry).weekdays, Set(1...7))
    }

    func testValidation() {
        var draft = NativeScheduleDraft()
        XCTAssertNil(draft.validationMessage())
        XCTAssertNil(draft.validationMessage(adding: (count: 0, limit: 12)))

        draft.weekdays = []
        XCTAssertEqual(draft.validationMessage(), "Choose at least one day.")
        draft.weekdays = [1]

        XCTAssertNotNil(draft.validationMessage(adding: (count: 12, limit: 12)))
        XCTAssertNil(draft.validationMessage(adding: (count: 11, limit: 12)))

        draft.hour = 24
        XCTAssertEqual(draft.validationMessage(), "Choose a valid time.")
        draft.hour = 7

        draft.action = .atSunrise
        XCTAssertEqual(draft.validationMessage(), "Choose what the lights should do.")

        draft.trigger = .sunrise
        draft.offsetMinutes = 2000
        XCTAssertNotNil(draft.validationMessage())
        draft.offsetMinutes = 90
        XCTAssertNil(draft.validationMessage())
    }

    func testOffsetChoicesKeepANonStandardOffset() {
        var draft = NativeScheduleDraft()
        XCTAssertEqual(draft.offsetChoices, NativeScheduleDraft.standardOffsets)
        draft.offsetMinutes = -200
        XCTAssertEqual(draft.offsetChoices.first, -200)
        XCTAssertEqual(draft.offsetChoices.count, NativeScheduleDraft.standardOffsets.count + 1)
    }

    func testOffsetDescriptions() {
        XCTAssertEqual(NativeScheduleDraft.offsetDescription(0, trigger: .sunrise), "At sunrise")
        XCTAssertEqual(NativeScheduleDraft.offsetDescription(-30, trigger: .sunset), "30 min before sunset")
        XCTAssertEqual(NativeScheduleDraft.offsetDescription(60, trigger: .sunrise), "1 hr after sunrise")
        XCTAssertEqual(NativeScheduleDraft.offsetDescription(-75, trigger: .sunrise), "1 hr 15 min before sunrise")
    }

    func testSummaries() {
        let locale = Locale(identifier: "en_GB")
        XCTAssertEqual(
            NativeScheduleDraft.summary(for: ScheduleEntry(hour: 7, minute: 5, action: .turnOn), locale: locale),
            "Turn On at 07:05")
        XCTAssertEqual(
            NativeScheduleDraft.summary(for: ScheduleEntry(hour: 0, minute: 0, action: .atSunrise), locale: locale),
            "Turn On at sunrise")
        XCTAssertEqual(
            NativeScheduleDraft.summary(for: ScheduleEntry(hour: 0, minute: 0, offsetMinutes: -15, action: .atSunset),
                                        locale: locale),
            "Turn Off 15 min before sunset")
    }
}
#endif

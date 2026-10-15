#if os(macOS)
import Foundation

/// The schedule editor's working copy of a `ScheduleEntry`.
///
/// The engine models sunrise and sunset as actions (`atSunrise` turns lights on,
/// `atSunset` turns them off) rather than as a time source. The editor presents
/// "when" and "what" separately, so this maps between the two and keeps the
/// rules in one testable place.
struct NativeScheduleDraft: Equatable {
    enum Trigger: String, CaseIterable, Identifiable {
        case time
        case sunrise
        case sunset

        var id: Self { self }

        var title: String {
            switch self {
            case .time: return "At a Time"
            case .sunrise: return "At Sunrise"
            case .sunset: return "At Sunset"
            }
        }

        /// What a sunrise or sunset schedule does; the engine fixes it.
        var fixedActionTitle: String? {
            switch self {
            case .time: return nil
            case .sunrise: return "Turn On"
            case .sunset: return "Turn Off"
            }
        }
    }

    /// Actions a schedule at a set time can take.
    static let timedActions: [ScheduleAction] = [.turnOn, .turnOff, .dim10, .dim25, .dim50, .dim75]

    /// Offsets the editor offers for sunrise and sunset, in minutes.
    static let standardOffsets = [-120, -90, -60, -45, -30, -15, 0, 15, 30, 45, 60, 90, 120]

    var trigger: Trigger = .time
    var hour = 7
    var minute = 0
    var offsetMinutes = 0
    /// Used only when `trigger` is `.time`.
    var action: ScheduleAction = .turnOn
    /// Calendar weekday numbers, 1 = Sunday … 7 = Saturday.
    var weekdays: Set<Int> = Set(1...7)

    init() {}

    init(entry: ScheduleEntry) {
        let entry = entry.normalized()
        switch entry.action {
        case .atSunrise:
            trigger = .sunrise
            offsetMinutes = entry.offsetMinutes
        case .atSunset:
            trigger = .sunset
            offsetMinutes = entry.offsetMinutes
        default:
            trigger = .time
            action = entry.action
        }
        hour = entry.hour
        minute = entry.minute
        // An empty set means every day in the model; the editor shows that explicitly.
        weekdays = entry.weekdays.isEmpty ? Set(1...7) : entry.weekdays
    }

    /// The action stored in the entry.
    var resolvedAction: ScheduleAction {
        switch trigger {
        case .time: return action
        case .sunrise: return .atSunrise
        case .sunset: return .atSunset
        }
    }

    /// Builds the entry to save. Keeps `id` and `isEnabled` when editing an existing one.
    func entry(id: UUID = UUID(), isEnabled: Bool = true) -> ScheduleEntry {
        ScheduleEntry(id: id, isEnabled: isEnabled, hour: hour, minute: minute,
                      offsetMinutes: trigger == .time ? 0 : offsetMinutes,
                      action: resolvedAction, weekdays: weekdays)
    }

    /// Why the draft can't be saved, or nil. When adding, pass the room's schedule
    /// count and its limit (`LightManager.maximumSchedulesPerRoom`); nil when editing.
    func validationMessage(adding room: (count: Int, limit: Int)? = nil) -> String? {
        if let room, room.count >= room.limit {
            return "This room already has \(room.limit) schedules. Delete one first."
        }
        if weekdays.isEmpty { return "Choose at least one day." }
        if !weekdays.isSubset(of: Set(1...7)) { return "Choose valid days." }
        switch trigger {
        case .time:
            if !(0...23).contains(hour) || !(0...59).contains(minute) { return "Choose a valid time." }
            if !Self.timedActions.contains(action) { return "Choose what the lights should do." }
        case .sunrise, .sunset:
            if !ScheduleEntry.supportedOffsetMinutes.contains(offsetMinutes) {
                return "The offset must be within a day of \(trigger == .sunrise ? "sunrise" : "sunset")."
            }
        }
        return nil
    }

    /// The standard offsets plus the draft's own, if an older schedule used another value.
    var offsetChoices: [Int] {
        Self.standardOffsets.contains(offsetMinutes)
            ? Self.standardOffsets
            : (Self.standardOffsets + [offsetMinutes]).sorted()
    }

    // MARK: Formatting

    /// "At sunrise", "30 min before sunset", "1 hr 15 min after sunrise".
    static func offsetDescription(_ minutes: Int, trigger: Trigger) -> String {
        let event = trigger == .sunset ? "sunset" : "sunrise"
        guard minutes != 0 else { return "At \(event)" }
        let magnitude = abs(minutes)
        let hours = magnitude / 60
        let rest = magnitude % 60
        let amount: String
        switch (hours, rest) {
        case (0, _): amount = "\(rest) min"
        case (_, 0): amount = "\(hours) hr"
        default: amount = "\(hours) hr \(rest) min"
        }
        return "\(amount) \(minutes < 0 ? "before" : "after") \(event)"
    }

    /// One line for a schedule list row: "Turn On at 7:00 AM", "Turn Off 30 min before sunset".
    static func summary(for entry: ScheduleEntry, locale: Locale = .current) -> String {
        let draft = NativeScheduleDraft(entry: entry)
        switch draft.trigger {
        case .time:
            return "\(entry.action.displayName) at \(timeText(hour: draft.hour, minute: draft.minute, locale: locale))"
        case .sunrise, .sunset:
            let when = offsetDescription(draft.offsetMinutes, trigger: draft.trigger)
            let lowered = draft.offsetMinutes == 0 ? when.prefix(1).lowercased() + when.dropFirst() : when
            return "\(draft.trigger.fixedActionTitle ?? "") \(lowered)"
        }
    }

    /// A clock time in the locale's short style.
    static func timeText(hour: Int, minute: Int, locale: Locale = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let date = calendar.date(from: DateComponents(hour: hour, minute: minute)) ?? Date()
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
#endif

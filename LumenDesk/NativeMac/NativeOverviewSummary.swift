#if os(macOS)
import Foundation

/// Plain-language wording for the Overview page, kept free of SwiftUI so it can be tested.
enum NativeOverviewSummary {
    /// The page headline: "3 of 5 lights are on", "All lights are off", "No lights yet".
    static func headline(on: Int, total: Int) -> String {
        guard total > 0 else { return "No lights yet" }
        if total == 1 { return on > 0 ? "Your light is on" : "Your light is off" }
        if on <= 0 { return "All lights are off" }
        if on >= total { return "All \(total) lights are on" }
        return "\(on) of \(total) lights are on"
    }

    /// The line under the headline, or nil when there is nothing to warn about.
    static func notRespondingNote(_ count: Int) -> String? {
        guard count > 0 else { return nil }
        return count == 1
            ? "1 light isn’t responding. Check that it’s switched on at the wall."
            : "\(count) lights aren’t responding. Check that they’re switched on at the wall."
    }

    /// A room card's status: "2 of 3 on", "On", "Off", "No lights yet".
    static func groupStatus(on: Int, total: Int) -> String {
        guard total > 0 else { return "No lights yet" }
        if total == 1 { return on > 0 ? "On" : "Off" }
        return "\(on) of \(total) on"
    }

    /// A light's status: "On · 60%", "Off", or "Not responding" with an optional hint.
    static func lightStatus(isOn: Bool, brightness: Double, isStale: Bool, detailed: Bool = false) -> String {
        if isStale { return detailed ? "Not responding — check it’s powered" : "Not responding" }
        return isOn ? "On · \(percent(brightness))" : "Off"
    }

    /// "60%" for 0.6, clamped to 0–100.
    static func percent(_ brightness: Double) -> String {
        "\(Int((min(1, max(0, brightness)) * 100).rounded()))%"
    }

    /// "1 light" / "3 lights".
    static func lightCount(_ count: Int) -> String {
        count == 1 ? "1 light" : "\(count) lights"
    }
}
#endif

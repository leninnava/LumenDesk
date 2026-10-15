import AppIntents
import Foundation

// Fork: the intents behind the Control Center controls and the desktop widget's toggles.
//
// They are compiled into the app and the LumenDeskControls extension. A control or widget
// performs its intent in the widget extension unless the intent opts into the app's process
// (WidgetKit, "Adding interactivity to widgets and Live Activities"): conforming to
// `ForegroundContinuableIntent` does that on macOS 26, and `allowedExecutionTargets = .main` says
// it explicitly on macOS 27. Only the app owns the UDP sockets and Bluetooth connections, so the
// extension's copy of `perform()` never sends anything; it fails with `appRequired` if the system
// ever runs it there.

/// Why an intent couldn't change the lights. Shared by the Shortcuts intents and the controls.
enum LightControlError: Error, CustomLocalizedStringResourceConvertible {
    case appRequired
    /// What couldn't be found, as a phrase: "that light", "any lights in Kitchen".
    case notFound(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .appRequired:
            return "Open LumenDesk to control your lights."
        case .notFound(let what):
            return "LumenDesk can't find \(what). Check that this Mac is on your home network."
        }
    }

    /// The extension's `perform()`: it has no light connections, so it can only fail.
    static func failOutsideApp() throws {
        throw LightControlError.appRequired
    }
}

#if os(macOS)
/// Turns one room on or off. `roomID` is the room's UUID string.
@available(macOS 26.0, *)
struct RoomPowerControlIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Set Room Power"
    static let isDiscoverable = false

    @available(macOS 27.0, *)
    static var allowedExecutionTargets: IntentExecutionTargets { .main }

    @Parameter(title: "Room ID")
    var roomID: String

    @Parameter(title: "On")
    var value: Bool

    init() {}

    init(roomID: String, value: Bool) {
        self.roomID = roomID
        self.value = value
    }

    func perform() async throws -> some IntentResult {
        #if LUMENDESK_WIDGET_EXTENSION
        try LightControlError.failOutsideApp()
        #else
        try await LightIntentActions.setRoomPower(roomID: roomID, on: value)
        #endif
        return .result()
    }
}

/// Turns every light LumenDesk has found on or off, without the confirmation the app's own
/// "Toggle All Lights" command asks for.
@available(macOS 26.0, *)
struct LightPowerControlIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Set Light Power"
    static let isDiscoverable = false
    @available(macOS 27.0, *)
    static var allowedExecutionTargets: IntentExecutionTargets { .main }

    @Parameter(title: "Light ID")
    var lightID: String

    @Parameter(title: "On")
    var value: Bool

    init() {}

    init(lightID: String, value: Bool) {
        self.lightID = lightID
        self.value = value
    }

    func perform() async throws -> some IntentResult {
        #if LUMENDESK_WIDGET_EXTENSION
        try LightControlError.failOutsideApp()
        #else
        try await LightIntentActions.setLightPower(lightID: lightID, action: value ? .on : .off)
        #endif
        return .result()
    }
}

@available(macOS 26.0, *)
struct AllLightsPowerControlIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Set All Lights Power"
    static let isDiscoverable = false

    @available(macOS 27.0, *)
    static var allowedExecutionTargets: IntentExecutionTargets { .main }

    @Parameter(title: "On")
    var value: Bool

    init() {}

    init(value: Bool) {
        self.value = value
    }

    func perform() async throws -> some IntentResult {
        #if LUMENDESK_WIDGET_EXTENSION
        try LightControlError.failOutsideApp()
        #else
        try await LightIntentActions.setAllPower(on: value)
        #endif
        return .result()
    }
}

// `ForegroundContinuableIntent` is what routes these into the app's process on macOS 26. The SDK
// marks it unavailable in app extensions, so, as Apple's examples do, the conformance is declared
// for the app only; the extension's copy of the type doesn't have it. It is deprecated on macOS 26
// in favour of `supportedModes`, whose docs don't promise the same routing; declaring it in
// deprecated extensions keeps the build free of warnings.
@available(macOS, introduced: 26.0, deprecated: 26.0)
@available(macOSApplicationExtension, unavailable)
extension RoomPowerControlIntent: ForegroundContinuableIntent {}

@available(macOS, introduced: 26.0, deprecated: 26.0)
@available(macOSApplicationExtension, unavailable)
extension AllLightsPowerControlIntent: ForegroundContinuableIntent {}

@available(macOS, introduced: 26.0, deprecated: 26.0)
@available(macOSApplicationExtension, unavailable)
extension LightPowerControlIntent: ForegroundContinuableIntent {}
#endif

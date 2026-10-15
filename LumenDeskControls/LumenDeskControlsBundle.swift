import SwiftUI
import WidgetKit

/// Fork: LumenDesk's Control Center controls and desktop widget (macOS 26+).
///
/// The extension only draws. Every toggle runs an intent that the system performs in the app's
/// process (see Shared/ControlIntents.swift), and current values come from the snapshot the app
/// writes to the App Group (Shared/ControlsSnapshot.swift).
@main
struct LumenDeskControlsBundle: WidgetBundle {
    var body: some Widget {
        AllLightsControl()
        RoomPowerControl()
        LightPowerControl()
        RoomsWidget()
        RoomLightsWidget()
    }
}

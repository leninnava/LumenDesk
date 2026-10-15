import AppIntents
import SwiftUI
import WidgetKit

// MARK: - All Lights

struct AllLightsControl: ControlWidget {
    static let kind = "com.lumendesk.LumenDesk.Controls.allLights"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind, provider: Provider()) { isOn in
            ControlWidgetToggle(isOn: isOn, action: AllLightsPowerControlIntent()) {
                Label("All Lights", systemImage: isOn ? "lightbulb.2.fill" : "lightbulb.2")
            }
        }
        .displayName("All Lights")
        .description("Turn every light LumenDesk has found on or off.")
    }

    struct Provider: ControlValueProvider {
        var previewValue: Bool { false }

        func currentValue() async throws -> Bool {
            ControlsStateStore.shared.load().anyOn
        }
    }
}

// MARK: - One room

/// The room a room control was set up for. Picked when the control is added.
struct RoomControlConfiguration: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "Room"
    static let isDiscoverable = false

    @Parameter(title: "Room")
    var room: RoomEntity?

    init() {}
}

struct RoomPowerControl: ControlWidget {
    static let kind = "com.lumendesk.LumenDesk.Controls.room"

    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: Self.kind, provider: Provider()) { value in
            ControlWidgetToggle(isOn: value.isOn,
                                action: RoomPowerControlIntent(roomID: value.roomID, value: !value.isOn)) {
                Label(value.name, systemImage: value.isOn ? "lightbulb.fill" : "lightbulb")
            }
            .disabled(value.roomID.isEmpty)
        }
        .displayName("Room Lights")
        .description("Turn the lights in one room on or off.")
        .promptsForUserConfiguration()
    }

    struct Value {
        var roomID: String
        var name: String
        var isOn: Bool
    }

    struct Provider: AppIntentControlValueProvider {
        func previewValue(configuration: RoomControlConfiguration) -> Value {
            Value(roomID: configuration.room?.id ?? "", name: configuration.room?.name ?? "Room", isOn: false)
        }

        func currentValue(configuration: RoomControlConfiguration) async throws -> Value {
            guard let room = configuration.room else {
                return Value(roomID: "", name: "Choose a Room", isOn: false)
            }
            let state = ControlsStateStore.shared.load().room(id: room.id)
            return Value(roomID: room.id, name: state?.name ?? room.name, isOn: state?.isOn ?? false)
        }
    }
}

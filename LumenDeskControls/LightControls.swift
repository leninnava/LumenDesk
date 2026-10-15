import AppIntents
import SwiftUI
import WidgetKit

// Fork: per-light controls. Like the room control, the toggles run their intent in the app's
// process; the extension only draws from the snapshot the app writes to the App Group.

// MARK: - One light (Control Center)

/// The light a light control was set up for. Picked when the control is added.
struct LightControlConfiguration: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "Light"
    static let isDiscoverable = false

    @Parameter(title: "Light")
    var light: LightEntity?

    init() {}
}

struct LightPowerControl: ControlWidget {
    static let kind = "com.lumendesk.LumenDesk.Controls.light"

    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: Self.kind, provider: Provider()) { value in
            ControlWidgetToggle(isOn: value.isOn,
                                action: LightPowerControlIntent(lightID: value.lightID, value: !value.isOn)) {
                Label(value.name, systemImage: value.isOn ? "lightbulb.fill" : "lightbulb")
            }
            .disabled(value.lightID.isEmpty)
        }
        .displayName("Light")
        .description("Turn one light on or off.")
        .promptsForUserConfiguration()
    }

    struct Value {
        var lightID: String
        var name: String
        var isOn: Bool
    }

    struct Provider: AppIntentControlValueProvider {
        func previewValue(configuration: LightControlConfiguration) -> Value {
            Value(lightID: configuration.light?.id ?? "", name: configuration.light?.name ?? "Light", isOn: false)
        }

        func currentValue(configuration: LightControlConfiguration) async throws -> Value {
            guard let light = configuration.light else {
                return Value(lightID: "", name: "Choose a Light", isOn: false)
            }
            let state = ControlsStateStore.shared.load().light(id: light.id)
            return Value(lightID: light.id, name: state?.name ?? light.name, isOn: state?.isOn ?? false)
        }
    }
}

// MARK: - A room's lights (desktop widget)

/// The room a Room Lights widget shows; no room shows every light.
struct RoomLightsWidgetConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Room Lights"
    static let description = IntentDescription("Choose the room whose lights the widget shows.")

    @Parameter(title: "Room")
    var room: RoomEntity?

    init() {}
}

struct RoomLightsWidget: Widget {
    static let kind = "com.lumendesk.LumenDesk.Controls.roomLights"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: RoomLightsWidgetConfiguration.self,
                               provider: Provider()) { entry in
            RoomLightsWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Room Lights")
        .description("Switch each light in a room on and off.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }

    struct Entry: TimelineEntry {
        var date: Date
        var title: String
        var roomID: String?
        var snapshot: ControlsSnapshot
    }

    struct Provider: AppIntentTimelineProvider {
        func placeholder(in context: Context) -> Entry {
            let lights: [ControlsSnapshot.Light] = [
                .init(id: "a", name: "Ceiling Light", roomID: "r", isOn: true, brightness: 80, isReachable: true),
                .init(id: "b", name: "Desk Lamp", roomID: "r", isOn: false, brightness: 40, isReachable: true),
            ]
            return Entry(date: Date(), title: "Living Room", roomID: "r",
                         snapshot: ControlsSnapshot(rooms: [.init(id: "r", name: "Living Room", lightCount: 2, onCount: 1)],
                                                    lights: lights, lightCount: 2, onCount: 1, updatedAt: Date()))
        }

        func snapshot(for configuration: RoomLightsWidgetConfiguration, in context: Context) async -> Entry {
            context.isPreview ? placeholder(in: context) : current(configuration)
        }

        // The app reloads timelines whenever a light changes, so one entry and no refresh date.
        func timeline(for configuration: RoomLightsWidgetConfiguration, in context: Context) async -> Timeline<Entry> {
            Timeline(entries: [current(configuration)], policy: .never)
        }

        private func current(_ configuration: RoomLightsWidgetConfiguration) -> Entry {
            let snapshot = ControlsStateStore.shared.load()
            let roomID = configuration.room?.id
            let title = roomID.flatMap { snapshot.room(id: $0)?.name } ?? configuration.room?.name ?? "All Lights"
            return Entry(date: Date(), title: title, roomID: roomID, snapshot: snapshot)
        }
    }
}

struct RoomLightsWidgetView: View {
    var entry: RoomLightsWidget.Entry
    @Environment(\.widgetFamily) private var family

    private var lights: [ControlsSnapshot.Light] {
        let limit: Int
        switch family {
        case .systemSmall: limit = 3
        case .systemMedium: limit = 4
        default: limit = 9
        }
        return Array(entry.snapshot.lights(inRoom: entry.roomID).prefix(limit))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.title).font(.headline).lineLimit(1)
            if lights.isEmpty {
                Spacer(minLength: 0)
                Text(entry.roomID == nil ? "Open LumenDesk to find your lights." : "No lights in this room yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Divider()
                ForEach(lights) { light in
                    Toggle(isOn: light.isOn, intent: LightPowerControlIntent(lightID: light.id, value: !light.isOn)) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(light.name).lineLimit(1)
                            if family != .systemSmall {
                                Text(status(light)).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }

    private func status(_ light: ControlsSnapshot.Light) -> String {
        guard light.isReachable else { return "Not responding" }
        return light.isOn ? "On · \(light.brightness)%" : "Off"
    }
}

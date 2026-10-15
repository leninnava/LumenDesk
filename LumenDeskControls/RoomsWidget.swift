import AppIntents
import SwiftUI
import WidgetKit

/// A desktop widget listing rooms with a switch each. The switches run the same intent as the
/// room control, in the app's process.
struct RoomsWidget: Widget {
    static let kind = "com.lumendesk.LumenDesk.Controls.rooms"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: Provider()) { entry in
            RoomsWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Rooms")
        .description("Switch LumenDesk rooms on and off.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }

    struct Entry: TimelineEntry {
        var date: Date
        var snapshot: ControlsSnapshot
    }

    struct Provider: TimelineProvider {
        func placeholder(in context: Context) -> Entry {
            Entry(date: Date(), snapshot: ControlsSnapshot(
                rooms: [.init(id: "living", name: "Living Room", lightCount: 3, onCount: 2),
                        .init(id: "office", name: "Office", lightCount: 1, onCount: 0)],
                lightCount: 4, onCount: 2, updatedAt: Date()))
        }

        func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
            completion(context.isPreview ? placeholder(in: context) : current())
        }

        // The app reloads timelines whenever a room changes, so one entry and no refresh date.
        func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
            completion(Timeline(entries: [current()], policy: .never))
        }

        private func current() -> Entry {
            Entry(date: Date(), snapshot: ControlsStateStore.shared.load())
        }
    }
}

struct RoomsWidgetView: View {
    var entry: RoomsWidget.Entry
    @Environment(\.widgetFamily) private var family

    private var rooms: [ControlsSnapshot.Room] {
        Array(entry.snapshot.rooms.prefix(family == .systemSmall ? 3 : 4))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: entry.snapshot.anyOn, intent: AllLightsPowerControlIntent(value: !entry.snapshot.anyOn)) {
                Text("All Lights").font(.headline)
            }
            if rooms.isEmpty {
                Spacer(minLength: 0)
                Text("Open LumenDesk to set up rooms.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Divider()
                ForEach(rooms) { room in
                    Toggle(isOn: room.isOn, intent: RoomPowerControlIntent(roomID: room.id, value: !room.isOn)) {
                        Text(room.name).lineLimit(1)
                    }
                    .disabled(room.lightCount == 0)
                }
            }
            Spacer(minLength: 0)
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }
}

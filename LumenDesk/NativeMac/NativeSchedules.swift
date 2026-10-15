#if os(macOS)
import SwiftUI

/// Every room's schedules, grouped by room. Schedules belong to rooms in the engine,
/// so a room is needed before anything can be scheduled.
struct NativeSchedulesView: View {
    @EnvironmentObject private var manager: LightManager
    @State private var editing: NativeScheduleEditTarget?

    var body: some View {
        Form {
            if manager.rooms.isEmpty {
                Section {
                    Text("Schedules turn a room's lights on, off or to a set brightness at a time of day. Add a room first.")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(manager.rooms) { room in
                    roomSection(room)
                }
                Section {
                    LabeledContent("Sunrise",
                                   value: NativeScheduleDraft.timeText(hour: manager.sunriseHour, minute: manager.sunriseMinute))
                    LabeledContent("Sunset",
                                   value: NativeScheduleDraft.timeText(hour: manager.sunsetHour, minute: manager.sunsetMinute))
                } footer: {
                    Text("Sunrise and sunset are set by hand in Settings › General.")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Schedules")
        .toolbar {
            ToolbarItem {
                Button {
                    if let room = manager.rooms.first(where: canAdd) { editing = .add(roomID: room.id) }
                } label: {
                    Label("Add Schedule", systemImage: "calendar.badge.plus")
                }
                .help("Add a schedule")
                .disabled(!manager.rooms.contains(where: canAdd))
            }
        }
        .sheet(item: $editing) { target in
            NativeScheduleEditor(target: target)
        }
    }

    private func canAdd(_ room: Room) -> Bool {
        room.schedules.count < LightManager.maximumSchedulesPerRoom
    }

    private func roomSection(_ room: Room) -> some View {
        Section {
            if room.schedules.isEmpty {
                Text("No schedules").foregroundStyle(.secondary)
            }
            ForEach(room.schedules) { entry in
                NativeScheduleRow(entry: entry, room: room) {
                    editing = .edit(roomID: room.id, entry: entry)
                }
            }
            ForEach(manager.conflictWarnings(for: room.id), id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            HStack {
                Text(room.name)
                Spacer()
                Button("Add…") { editing = .add(roomID: room.id) }
                    .buttonStyle(.borderless)
                    .disabled(!canAdd(room))
                    .help(canAdd(room) ? "Add a schedule to \(room.name)"
                          : "A room holds up to \(LightManager.maximumSchedulesPerRoom) schedules")
            }
        }
    }
}

/// One schedule: what it does and when, its days, the next run, and an on/off switch.
private struct NativeScheduleRow: View {
    @EnvironmentObject private var manager: LightManager
    let entry: ScheduleEntry
    let room: Room
    let onEdit: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(NativeScheduleDraft.summary(for: entry))
                Text(entry.isEnabled ? "\(entry.daySummary) · \(manager.nextRunDescription(for: entry))" : entry.daySummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Edit…", action: onEdit)
                .buttonStyle(.borderless)
            Toggle("Enabled", isOn: Binding(
                get: { entry.isEnabled },
                set: { manager.setScheduleEnabled(entry.id, in: room.id, enabled: $0) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onEdit)
        .contextMenu {
            Button("Edit…", action: onEdit)
            Button("Run Now") { manager.testSchedule(entry, in: room) }
            Button("Duplicate") { manager.duplicateSchedule(entry, in: room.id) }
                .disabled(room.schedules.count >= LightManager.maximumSchedulesPerRoom)
            Divider()
            Button("Delete", role: .destructive) { manager.deleteSchedule(entry.id, from: room.id) }
        }
    }
}

/// What the editor sheet is for: a new schedule in a room, or an existing one.
enum NativeScheduleEditTarget: Identifiable {
    case add(roomID: UUID)
    case edit(roomID: UUID, entry: ScheduleEntry)

    var id: String {
        switch self {
        case .add(let roomID): return "add-\(roomID)"
        case .edit(_, let entry): return "edit-\(entry.id)"
        }
    }
}

/// Sheet for adding or editing a schedule.
private struct NativeScheduleEditor: View {
    @EnvironmentObject private var manager: LightManager
    @Environment(\.dismiss) private var dismiss
    let target: NativeScheduleEditTarget
    @State private var draft = NativeScheduleDraft()
    @State private var roomID: UUID?

    private var existing: ScheduleEntry? {
        if case .edit(_, let entry) = target { return entry }
        return nil
    }

    private var room: Room? { manager.rooms.first { $0.id == roomID } }

    private var validation: String? {
        guard let room else { return "Choose a room." }
        return draft.validationMessage(
            adding: existing == nil ? (room.schedules.count, LightManager.maximumSchedulesPerRoom) : nil)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    if existing == nil {
                        Picker("Room", selection: $roomID) {
                            ForEach(manager.rooms) { Text($0.name).tag(UUID?.some($0.id)) }
                        }
                    } else {
                        LabeledContent("Room", value: room?.name ?? "")
                    }
                    Picker("When", selection: $draft.trigger) {
                        ForEach(NativeScheduleDraft.Trigger.allCases) { Text($0.title).tag($0) }
                    }
                    switch draft.trigger {
                    case .time:
                        DatePicker("Time", selection: timeBinding, displayedComponents: .hourAndMinute)
                        Picker("Action", selection: $draft.action) {
                            ForEach(NativeScheduleDraft.timedActions, id: \.self) { Text($0.displayName).tag($0) }
                        }
                    case .sunrise, .sunset:
                        Picker("Offset", selection: $draft.offsetMinutes) {
                            ForEach(draft.offsetChoices, id: \.self) {
                                Text(NativeScheduleDraft.offsetDescription($0, trigger: draft.trigger)).tag($0)
                            }
                        }
                        LabeledContent("Action", value: draft.trigger.fixedActionTitle ?? "")
                    }
                } footer: {
                    if draft.trigger != .time {
                        Text("Sunrise schedules turn lights on and sunset schedules turn them off. Today's \(draft.trigger == .sunrise ? "sunrise" : "sunset") is set to \(solarTime) in Settings.")
                    }
                }
                Section("Days") {
                    NativeWeekdayPicker(weekdays: $draft.weekdays)
                }
            }
            .formStyle(.grouped)

            HStack {
                if let validation {
                    Text(validation).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(existing == nil ? "Add" : "Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(validation != nil)
            }
            .padding()
        }
        .frame(width: 440)
        .onAppear(perform: load)
    }

    private var solarTime: String {
        draft.trigger == .sunrise
            ? NativeScheduleDraft.timeText(hour: manager.sunriseHour, minute: manager.sunriseMinute)
            : NativeScheduleDraft.timeText(hour: manager.sunsetHour, minute: manager.sunsetMinute)
    }

    private var timeBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: draft.hour, minute: draft.minute, second: 0, of: Date()) ?? Date()
            },
            set: {
                let parts = Calendar.current.dateComponents([.hour, .minute], from: $0)
                draft.hour = parts.hour ?? draft.hour
                draft.minute = parts.minute ?? draft.minute
            })
    }

    private func load() {
        switch target {
        case .add(let id):
            roomID = id
        case .edit(let id, let entry):
            roomID = id
            draft = NativeScheduleDraft(entry: entry)
        }
    }

    private func save() {
        guard validation == nil, let roomID else { return }
        if let existing {
            manager.updateSchedule(draft.entry(id: existing.id, isEnabled: existing.isEnabled), in: roomID)
        } else if !manager.addSchedule(draft.entry(), to: roomID) {
            return
        }
        dismiss()
    }
}

/// Seven toggle buttons, in the locale's week order.
private struct NativeWeekdayPicker: View {
    @Binding var weekdays: Set<Int>

    private var orderedDays: [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { (first - 1 + $0) % 7 + 1 }
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(orderedDays, id: \.self) { day in
                Toggle(Calendar.current.shortWeekdaySymbols[day - 1], isOn: Binding(
                    get: { weekdays.contains(day) },
                    set: { on in
                        if on { weekdays.insert(day) } else { weekdays.remove(day) }
                    }))
                .toggleStyle(.button)
                .accessibilityLabel(Calendar.current.weekdaySymbols[day - 1])
            }
        }
        HStack {
            Button("Every Day") { weekdays = Set(1...7) }
            Button("Weekdays") { weekdays = Set(2...6) }
            Button("Weekends") { weekdays = [1, 7] }
        }
        .buttonStyle(.link)
    }
}
#endif

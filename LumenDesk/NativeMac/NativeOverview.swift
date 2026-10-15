#if os(macOS)
import SwiftUI

/// The landing page: how many lights are on, one-click control of everything, each room and
/// each loose light, saved scenes, and a way to add lights. The detailed controls stay on
/// All Lights and the room pages.
struct NativeOverviewView: View {
    @EnvironmentObject private var manager: LightManager
    @EnvironmentObject private var networkGate: NativeNetworkGate
    @Binding var selection: NativeSidebarItem?
    /// Opens the Add Light sheet, optionally with a room chosen.
    let onAddLight: (UUID?) -> Void
    let onAddRoom: () -> Void

    private var onCount: Int { manager.devices.filter(\.isOn).count }
    private var notRespondingCount: Int { manager.devices.filter(\.isStale).count }
    private var unassigned: [LightDevice] {
        manager.devices.filter { manager.room(forLightID: $0.id) == nil }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                if manager.devices.isEmpty {
                    NativeOverviewEmptyState(onAddLight: { onAddLight(nil) })
                } else {
                    roomsSection
                    lightsSection
                    scenesSection
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Overview")
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(NativeOverviewSummary.headline(on: onCount, total: manager.devices.count))
                    .font(.largeTitle.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                if let note = NativeOverviewSummary.notRespondingNote(notRespondingCount) {
                    Label(note, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                } else if manager.devices.isEmpty {
                    Text(manager.isScanning ? "Looking for lights on this network…" : "Add your first light to get started.")
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 10) {
                if !manager.devices.isEmpty {
                    // Applied directly (undo still works): this page is for immediate action.
                    Button {
                        manager.setPower(deviceIDs: Set(manager.devices.map(\.id)), on: true)
                    } label: {
                        Label("Turn All On", systemImage: "lightbulb.fill").frame(minWidth: 110)
                    }
                    .help("Switch every light on")
                    .disabled(onCount == manager.devices.count)

                    Button {
                        manager.setPower(deviceIDs: Set(manager.devices.map(\.id)), on: false)
                    } label: {
                        Label("Turn All Off", systemImage: "lightbulb").frame(minWidth: 110)
                    }
                    .help("Switch every light off")
                    .disabled(onCount == 0)
                }
                Button {
                    onAddLight(nil)
                } label: {
                    Label("Add Light…", systemImage: "plus").frame(minWidth: 110)
                }
                .help("Find lights on this network or nearby over Bluetooth")
            }
            .controlSize(.large)
        }
    }

    // MARK: Rooms

    @ViewBuilder private var roomsSection: some View {
        NativeOverviewSection(
            title: "Rooms",
            caption: manager.rooms.isEmpty
                ? "Group lights into rooms to switch them together."
                : "Switch a whole room at once, or click its name for colour, themes and effects."
        ) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 14)], alignment: .leading, spacing: 14) {
                ForEach(manager.rooms) { room in
                    NativeOverviewRoomCard(
                        room: room,
                        lights: manager.devices(in: room),
                        onOpen: { selection = .room(room.id) },
                        onAddLight: { onAddLight(room.id) }
                    )
                }
                NativeOverviewAddCard(title: "Add Room", caption: "Name a room, then add lights to it",
                                      systemImage: "square.split.bottomrightquarter", minHeight: 150,
                                      action: onAddRoom)
            }
        }
    }

    // MARK: Lights

    @ViewBuilder private var lightsSection: some View {
        let lights = manager.rooms.isEmpty ? manager.devices : unassigned
        NativeOverviewSection(
            title: manager.rooms.isEmpty ? "Lights" : (lights.isEmpty ? "Add Lights" : "Lights Not in a Room"),
            caption: lights.isEmpty
                ? "Every light is in a room."
                : "Click a light to turn it on or off. Choose Details for colour and more."
        ) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], alignment: .leading, spacing: 12) {
                ForEach(lights) { light in
                    NativeLightTile(device: light, explained: true) { selection = .light(light.id) }
                }
                NativeOverviewAddCard(title: "Add Light", caption: "Wi-Fi or Bluetooth",
                                      systemImage: "plus", minHeight: 96) { onAddLight(nil) }
            }
        }
    }

    // MARK: Scenes

    @ViewBuilder private var scenesSection: some View {
        NativeOverviewSection(
            title: "Scenes",
            caption: manager.scenes.isEmpty
                ? "A scene remembers how your lights look so you can bring it back with one click."
                : "Bring back a saved look with one click.",
            accessory: {
                Button(manager.scenes.isEmpty ? "Save a Scene…" : "All Scenes") { selection = .scenes }
                    .help(manager.scenes.isEmpty
                        ? "Open Scenes to save how your lights look now"
                        : "Open Scenes to rename, delete or save scenes")
            }
        ) {
            if !manager.scenes.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], alignment: .leading, spacing: 12) {
                    ForEach(manager.scenes) { scene in
                        NativeOverviewSceneCard(scene: scene)
                    }
                }
            }
        }
    }
}

/// A titled block of the Overview, with a caption saying what the controls in it do.
private struct NativeOverviewSection<Accessory: View, Content: View>: View {
    let title: String
    let caption: String
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var content: () -> Content

    init(title: String, caption: String,
         @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() },
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.caption = caption
        self.accessory = accessory
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
                    Text(caption).foregroundStyle(.secondary)
                }
                Spacer()
                accessory()
            }
            content()
        }
    }
}

/// The rounded card background used across the Overview.
private struct NativeOverviewCardBackground: ViewModifier {
    var tint: Color?

    func body(content: Content) -> some View {
        content
            .background(tint.map { $0.opacity(0.18) } ?? Color.primary.opacity(0.05),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08)))
    }
}

/// A room: its name (click to open), how many lights are on, one power button and brightness.
private struct NativeOverviewRoomCard: View {
    @EnvironmentObject private var manager: LightManager
    let room: Room
    let lights: [LightDevice]
    let onOpen: () -> Void
    let onAddLight: () -> Void

    private var onCount: Int { lights.filter(\.isOn).count }
    private var anyOn: Bool { onCount > 0 }
    private var status: String { NativeOverviewSummary.groupStatus(on: onCount, total: lights.count) }
    /// Tint from the first light that's on, so a lit room reads at a glance.
    private var tint: Color? { lights.first(where: { $0.isOn && !$0.isStale })?.color }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Button(action: onOpen) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(room.name).font(.title3.weight(.semibold)).lineLimit(1)
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        Text(status).foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open \(room.name) for colour, themes and effects")
                .accessibilityLabel("\(room.name), \(status)")
                .accessibilityHint("Opens the room")
                Spacer(minLength: 8)
                if !lights.isEmpty {
                    Button {
                        manager.setPower(deviceIDs: Set(lights.map(\.id)), on: !anyOn)
                    } label: {
                        Label(anyOn ? "Turn Off" : "Turn On", systemImage: "power")
                    }
                    .controlSize(.large)
                    .help(anyOn ? "Switch off every light in \(room.name)" : "Switch on every light in \(room.name)")
                    .accessibilityLabel(anyOn ? "Turn off \(room.name)" : "Turn on \(room.name)")
                }
            }

            if lights.isEmpty {
                Spacer(minLength: 0)
                Text("Add a light to control this room from here.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Add Light…", action: onAddLight)
                    .help("Find a light and put it in \(room.name)")
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    NativeGroupBrightnessSlider(lights: lights, showsPercent: true)
                        .labelsHidden()
                    Text("Brightness for every light in this room")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .help("Drag to dim or brighten every light in \(room.name)")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .modifier(NativeOverviewCardBackground(tint: tint))
        .accessibilityElement(children: .contain)
    }
}

/// A dashed "add" card at the end of a grid.
private struct NativeOverviewAddCard: View {
    let title: String
    let caption: String
    let systemImage: String
    let minHeight: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage).font(.title2)
                Text(title).font(.body.weight(.medium))
                Text(caption).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .foregroundStyle(Color.accentColor)
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .padding(12)
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(caption)
        .accessibilityLabel(title)
        .accessibilityHint(caption)
    }
}

/// A saved scene with an Apply button. Applying goes through the same confirmation as Scenes.
private struct NativeOverviewSceneCard: View {
    @EnvironmentObject private var manager: LightManager
    let scene: LightingScene

    var body: some View {
        let preview = manager.scenePreview(scene)
        let available = preview.affected.count - preview.unreachable.count
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(scene.name).font(.body.weight(.medium)).lineLimit(1)
                Text(available < scene.snapshots.count
                     ? "\(available) of \(NativeOverviewSummary.lightCount(scene.snapshots.count)) available"
                     : NativeOverviewSummary.lightCount(scene.snapshots.count))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Apply") { manager.applyScene(scene) }
                .disabled(available == 0)
                .help(available == 0
                    ? "None of this scene’s lights are available"
                    : "Set the lights back to how they looked in “\(scene.name)”")
                .accessibilityLabel("Apply \(scene.name)")
        }
        .padding(12)
        .modifier(NativeOverviewCardBackground())
    }
}

/// Shown when no lights are known yet: how Wi-Fi lights are found, and how to add Bluetooth ones.
private struct NativeOverviewEmptyState: View {
    @EnvironmentObject private var manager: LightManager
    @EnvironmentObject private var networkGate: NativeNetworkGate
    let onAddLight: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            step(systemImage: "wifi", title: "Wi-Fi lights are found automatically",
                 text: "LIFX lights, and Govee lights with LAN Control turned on in the Govee Home app, appear here on their own once they’re on and connected to the same network as this Mac.") {
                if !networkGate.isHome {
                    Text("LumenDesk is paused on this network. If this is your home network, click This Is My Home Network so it can search here.")
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("This Is My Home Network") { networkGate.rememberCurrent() }
                            .disabled(networkGate.current == nil)
                            .help("Remember this network so LumenDesk finds lights here on its own")
                        Button("Scan Once") { manager.scan() }
                            .disabled(manager.isScanning)
                            .help("Search this network for lights one time")
                    }
                } else {
                    HStack(spacing: 8) {
                        Button("Scan Now") { manager.scan() }
                            .disabled(manager.isScanning)
                            .help("Search this network for lights again (⌘R)")
                        if manager.isScanning {
                            ProgressView().controlSize(.small)
                            Text("Searching…").foregroundStyle(.secondary)
                        }
                    }
                }
            }
            step(systemImage: "dot.radiowaves.left.and.right", title: "Bluetooth lights are added by hand",
                 text: "Govee lights without Wi-Fi control connect over Bluetooth. Turn the light on, keep it near this Mac, and choose Add Light.") {
                Button("Add Light…", action: onAddLight)
                    .controlSize(.large)
                    .help("Find lights on this network or nearby over Bluetooth")
            }
        }
        .frame(maxWidth: 640, alignment: .leading)
    }

    private func step<Actions: View>(systemImage: String, title: String, text: String,
                                     @ViewBuilder actions: () -> Actions) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.headline)
                Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                actions()
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .modifier(NativeOverviewCardBackground())
    }
}
#endif

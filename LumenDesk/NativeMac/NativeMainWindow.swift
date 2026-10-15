#if os(macOS)
import SwiftUI

enum NativeSidebarItem: Hashable {
    case overview
    case all
    case scenes
    case music
    case schedules
    case room(UUID)
    case light(String)
}

/// The main window: rooms and lights in a source list, controls in the detail pane.
struct NativeMainWindow: View {
    @EnvironmentObject private var manager: LightManager
    @EnvironmentObject private var bluetooth: GoveeBluetoothController
    @EnvironmentObject private var networkGate: NativeNetworkGate
    @State private var selection: NativeSidebarItem? = .overview
    @AppStorage(NativeDeviceLayout.storageKey) private var layout: NativeDeviceLayout = .tiles
    @State private var addingRoom = false
    @State private var renamingRoom: Room?
    @State private var renamingLight: LightDevice?
    /// The open Add Light sheet and the room it starts with.
    @State private var addingLight: NativeAddLightRequest?

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    Label("Overview", systemImage: "house").tag(NativeSidebarItem.overview)
                    Label("All Lights", systemImage: "lightbulb.2").tag(NativeSidebarItem.all)
                    Label("Scenes", systemImage: "photo.on.rectangle").tag(NativeSidebarItem.scenes)
                    Label("Music", systemImage: "music.note").tag(NativeSidebarItem.music)
                    Label("Schedules", systemImage: "clock").tag(NativeSidebarItem.schedules)
                }
                Section("Rooms") {
                    ForEach(manager.rooms) { room in
                        Label(room.name, systemImage: "square.split.bottomrightquarter")
                            .tag(NativeSidebarItem.room(room.id))
                            .contextMenu {
                                Button("Rename…") { renamingRoom = room }
                                Button("Delete Room", role: .destructive) {
                                    if selection == .room(room.id) { selection = .overview }
                                    manager.deleteRoom(room.id)
                                }
                            }
                    }
                }
                Section("Lights") {
                    ForEach(manager.devices) { device in
                        NativeSidebarLightRow(device: device)
                            .tag(NativeSidebarItem.light(device.id))
                            .contextMenu { Button("Rename…") { renamingLight = device } }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
            .safeAreaInset(edge: .bottom) {
                Button {
                    addingRoom = true
                } label: {
                    Label("Add Room", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
            }
        } detail: {
            detail
                .safeAreaInset(edge: .top) { pausedBanner }
                .safeAreaInset(edge: .bottom) { errorBanner }
        }
        .toolbar {
            ToolbarItem {
                Picker("Show Lights As", selection: $layout) {
                    ForEach(NativeDeviceLayout.allCases) { option in
                        Label(option.title, systemImage: option.symbol).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .help("Show lights as tiles or a list")
            }
            ToolbarItem {
                Button {
                    // Default to the room being viewed.
                    if case .room(let roomID) = selection {
                        addingLight = NativeAddLightRequest(roomID: roomID)
                    } else {
                        addingLight = NativeAddLightRequest()
                    }
                } label: {
                    Label("Add Light", systemImage: "plus")
                }
                .help("Add a light")
            }
            ToolbarItem {
                Button {
                    manager.scan()
                } label: {
                    Label("Scan for Lights", systemImage: "arrow.clockwise")
                }
                .help("Scan for lights (⌘R)")
                .disabled(manager.isScanning)
            }
            ToolbarItem {
                NativeSettingsButton()
            }
        }
        .navigationSubtitle(manager.isScanning ? "Scanning…" : "")
        .managedActionConfirmations(manager)
        .sheet(item: $addingLight) { request in
            NativeAddLightSheet(roomID: request.roomID)
        }
        .nativeRenameLightAlert(renamingLight, isPresented: Binding(
            get: { renamingLight != nil }, set: { if !$0 { renamingLight = nil } }), manager: manager)
        .nativeRoomNameAlert(isPresented: $addingRoom, title: "New Room", confirmTitle: "Create") { name in
            manager.createRoom(name: name)
            if let room = manager.rooms.last(where: { $0.name == name }) { selection = .room(room.id) }
        }
        .nativeRoomNameAlert(
            isPresented: Binding(get: { renamingRoom != nil }, set: { if !$0 { renamingRoom = nil } }),
            title: "Rename Room", initialName: renamingRoom?.name ?? "", confirmTitle: "Rename"
        ) { name in
            if let room = renamingRoom { manager.renameRoom(room.id, to: name) }
        }
        .onAppear {
            AppServices.shared.startNative()
        }
    }

    @ViewBuilder private var detail: some View {
        switch selection {
        case .light(let id):
            if let device = manager.devices.first(where: { $0.id == id }) {
                NativeLightDetailView(device: device).id(id)
            } else {
                placeholder
            }
        case .room(let id):
            if let room = manager.rooms.first(where: { $0.id == id }) {
                NativeGroupDetailView(title: room.name, scope: .room(id), lights: manager.devices(in: room),
                                      selection: $selection)
            } else {
                placeholder
            }
        case .scenes:
            NativeSceneLibraryView()
        case .music:
            NativeMusicView()
        case .schedules:
            NativeSchedulesView()
        case .all:
            NativeGroupDetailView(title: "All Lights", scope: .all, lights: manager.devices, selection: $selection)
        case .overview, nil:
            NativeOverviewView(
                selection: $selection,
                onAddLight: { addingLight = NativeAddLightRequest(roomID: $0) },
                onAddRoom: { addingRoom = true }
            )
        }
    }

    private var placeholder: some View {
        Text("Select a light or room").foregroundStyle(.secondary)
    }

    @ViewBuilder private var pausedBanner: some View {
        if !networkGate.isHome {
            HStack {
                Image(systemName: "pause.circle").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Paused on this network")
                    Text("LumenDesk only searches for lights on its own on your home networks.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Scan Once") { manager.scan() }
                Button("This Is My Home Network") { networkGate.rememberCurrent() }
                    .disabled(networkGate.current == nil)
            }
            .padding(10)
            .background(.bar)
        }
    }

    @ViewBuilder private var errorBanner: some View {
        if let error = manager.commandError {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(error).lineLimit(2)
                Spacer()
                if let undo = manager.commandErrorUndo {
                    Button("Undo") {
                        undo()
                        manager.commandError = nil
                        manager.commandErrorUndo = nil
                    }
                }
                Button("Dismiss") { manager.commandError = nil }
            }
            .padding(10)
            .background(.bar)
        }
    }
}

/// A request to show the Add Light sheet, starting with `roomID` chosen.
private struct NativeAddLightRequest: Identifiable {
    let id = UUID()
    var roomID: UUID?
}

/// Toolbar gear that opens Settings (⌘, keeps working through the app menu).
private struct NativeSettingsButton: View {
    var body: some View {
        if #available(macOS 14.0, *) {
            SettingsLink {
                Label("Settings", systemImage: "gearshape")
            }
            .help("Open Settings: general, network, shortcuts and automations (⌘,)")
        } else {
            Button {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .help("Open Settings: general, network, shortcuts and automations (⌘,)")
        }
    }
}

private struct NativeSidebarLightRow: View {
    @ObservedObject var device: LightDevice

    var body: some View {
        Label {
            Text(device.label)
        } icon: {
            NativeStatusIcon(device: device)
        }
    }
}
#endif

#if os(macOS)
enum NativeScenes {
    static let mainWindowID = "main"
}
#endif

#if os(macOS)
import SwiftUI

enum NativeSidebarItem: Hashable {
    case all
    case room(UUID)
    case light(String)
}

/// The main window: rooms and lights in a source list, controls in the detail pane.
struct NativeMainWindow: View {
    @EnvironmentObject private var manager: LightManager
    @State private var selection: NativeSidebarItem? = .all
    @AppStorage(NativeDeviceLayout.storageKey) private var layout: NativeDeviceLayout = .tiles
    @State private var addingRoom = false
    @State private var renamingRoom: Room?

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    Label("All Lights", systemImage: "lightbulb.2").tag(NativeSidebarItem.all)
                }
                Section("Rooms") {
                    ForEach(manager.rooms) { room in
                        Label(room.name, systemImage: "square.split.bottomrightquarter")
                            .tag(NativeSidebarItem.room(room.id))
                            .contextMenu {
                                Button("Rename…") { renamingRoom = room }
                                Button("Delete Room", role: .destructive) {
                                    if selection == .room(room.id) { selection = .all }
                                    manager.deleteRoom(room.id)
                                }
                            }
                    }
                }
                Section("Lights") {
                    ForEach(manager.devices) { device in
                        NativeSidebarLightRow(device: device).tag(NativeSidebarItem.light(device.id))
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
                    manager.scan()
                } label: {
                    Label("Scan for Lights", systemImage: "arrow.clockwise")
                }
                .help("Scan for lights (⌘R)")
                .disabled(manager.isScanning)
            }
        }
        .navigationSubtitle(manager.isScanning ? "Scanning…" : "")
        .managedActionConfirmations(manager)
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
        .onAppear { manager.start() }
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
        case .all, nil:
            NativeGroupDetailView(title: "All Lights", scope: .all, lights: manager.devices, selection: $selection)
        }
    }

    private var placeholder: some View {
        Text("Select a light or room").foregroundStyle(.secondary)
    }

    @ViewBuilder private var errorBanner: some View {
        if let error = manager.commandError {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(error).lineLimit(2)
                Spacer()
                Button("Dismiss") { manager.commandError = nil }
            }
            .padding(10)
            .background(.bar)
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

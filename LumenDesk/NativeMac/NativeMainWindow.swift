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

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    Label("All Lights", systemImage: "lightbulb.2").tag(NativeSidebarItem.all)
                }
                if !manager.rooms.isEmpty {
                    Section("Rooms") {
                        ForEach(manager.rooms) { room in
                            Label(room.name, systemImage: "square.split.bottomrightquarter")
                                .tag(NativeSidebarItem.room(room.id))
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
        } detail: {
            detail
                .safeAreaInset(edge: .bottom) { errorBanner }
        }
        .toolbar {
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

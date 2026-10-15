#if os(macOS)
import SwiftUI

/// Adds lights: ones found on this network that aren't in a room yet, and nearby Bluetooth
/// lights. Opening the sheet runs one network scan and a Bluetooth scan that stops when it
/// closes; nothing over Bluetooth is connected until the user clicks Add.
struct NativeAddLightSheet: View {
    @EnvironmentObject private var manager: LightManager
    @EnvironmentObject private var bluetooth: GoveeBluetoothController
    @Environment(\.dismiss) private var dismiss
    /// Room new lights go into; they're named after it.
    @State var roomID: UUID?
    @State private var showingSupported = false

    private var networkLights: [LightDevice] {
        manager.devices.filter { !$0.isBluetoothOnly && manager.room(forLightID: $0.id) == nil }
    }

    private var nearbyLights: [GoveeBluetoothController.NearbyLight] {
        bluetooth.nearby.filter { !manager.isKnownBluetoothAdvert($0.name) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Add Light").font(.title2.weight(.semibold))
                Spacer()
                Button {
                    showingSupported.toggle()
                } label: {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.borderless)
                .help("Supported lights")
                .popover(isPresented: $showingSupported, arrowEdge: .bottom) { NativeSupportedLights() }
            }
            Text("Turn the light on and keep it near this Mac. Lights on this network and nearby lights appear below.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker("Add to room", selection: $roomID) {
                Text("No Room").tag(UUID?.none)
                ForEach(manager.rooms) { room in
                    Text(room.name).tag(UUID?.some(room.id))
                }
            }

            List {
                Section("On this network") {
                    if networkLights.isEmpty {
                        searching(manager.isScanning ? "Searching this network…" : "No new lights on this network")
                    }
                    ForEach(networkLights) { light in
                        row(title: light.label, detail: "Wi-Fi · \(light.address)") {
                            manager.nativeAssign(light, toRoom: roomID)
                        }
                        .disabled(roomID == nil)
                    }
                }
                Section("Nearby") {
                    if nearbyLights.isEmpty {
                        searching("Searching for nearby lights…")
                    }
                    ForEach(nearbyLights) { light in
                        row(title: "\(light.sku) \(String(light.name.suffix(4)))",
                            detail: "Bluetooth · \(signal(light.rssi)) signal") {
                            manager.pairBluetoothLight(light, room: roomID, bluetooth: bluetooth)
                        }
                    }
                }
            }
            .frame(minHeight: 260)

            HStack {
                if roomID == nil, !networkLights.isEmpty {
                    Text("Choose a room to add lights on this network.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 500)
        .onAppear {
            manager.scan()
            bluetooth.startPairingScan()
        }
        .onDisappear { bluetooth.stopPairingScan() }
    }

    private func row(title: String, detail: String, add: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: "lightbulb").foregroundStyle(.secondary)
            VStack(alignment: .leading) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Add", action: add)
        }
    }

    private func searching(_ text: String) -> some View {
        HStack(spacing: 8) {
            if text.hasPrefix("Searching") { ProgressView().controlSize(.small) }
            Text(text).foregroundStyle(.secondary)
        }
    }

    private func signal(_ rssi: Int) -> String {
        switch rssi {
        case -65...0: return "strong"
        case -80 ..< -65: return "good"
        default: return "weak"
        }
    }
}

/// The supported-devices note behind the ⓘ button.
private struct NativeSupportedLights: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Supported lights").font(.headline)
            Label("LIFX bulbs and strips, over Wi-Fi", systemImage: "wifi")
            Label("Govee lights with LAN Control turned on in the Govee Home app, over Wi-Fi", systemImage: "wifi")
            Label("Govee lights without Wi-Fi control, over Bluetooth", systemImage: "dot.radiowaves.left.and.right")
        }
        .font(.callout)
        .padding(14)
        .frame(width: 340, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}
#endif

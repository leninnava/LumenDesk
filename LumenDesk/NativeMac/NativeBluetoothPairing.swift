#if os(macOS)
import SwiftUI

/// Lists nearby Govee lights so the user can add Bluetooth-only ones. Scanning runs only while
/// this sheet is open, and nothing is connected until the user clicks Add.
struct NativeBluetoothPairingSheet: View {
    @EnvironmentObject private var manager: LightManager
    @EnvironmentObject private var bluetooth: GoveeBluetoothController
    @Environment(\.dismiss) private var dismiss
    /// Room new lights go into; they're named after it.
    @State var roomID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Bluetooth Light").font(.title2.weight(.semibold))
            Text("For Govee lights without Wi-Fi control. Keep the light on and near this Mac. LumenDesk only connects to lights you add here.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker("Add to room", selection: $roomID) {
                Text("No Room").tag(UUID?.none)
                ForEach(manager.rooms) { room in
                    Text(room.name).tag(UUID?.some(room.id))
                }
            }

            List {
                if bluetooth.nearby.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Looking for Govee lights…").foregroundStyle(.secondary)
                    }
                }
                ForEach(bluetooth.nearby) { light in
                    HStack {
                        Image(systemName: "lightbulb").foregroundStyle(.secondary)
                        VStack(alignment: .leading) {
                            Text("\(light.sku) \(String(light.name.suffix(4)))")
                            Text("\(light.name) · \(signal(light.rssi)) signal")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if manager.isKnownBluetoothAdvert(light.name) {
                            Text("Added").foregroundStyle(.secondary)
                        } else {
                            Button("Add") { manager.pairBluetoothLight(light, room: roomID, bluetooth: bluetooth) }
                        }
                    }
                }
            }
            .frame(minHeight: 220)

            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear { bluetooth.startPairingScan() }
        .onDisappear { bluetooth.stopPairingScan() }
    }

    private func signal(_ rssi: Int) -> String {
        switch rssi {
        case -65...0: return "Strong"
        case -80 ..< -65: return "Good"
        default: return "Weak"
        }
    }
}
#endif

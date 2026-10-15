#if os(macOS)
import SwiftUI

struct NativeSettingsView: View {
    var body: some View {
        TabView {
            NativeGeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            NativeNetworkSettings()
                .tabItem { Label("Network", systemImage: "network") }
        }
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct NativeGeneralSettings: View {
    @EnvironmentObject private var manager: LightManager
    @EnvironmentObject private var bluetooth: GoveeBluetoothController
    @AppStorage(NativeDeviceLayout.storageKey) private var layout: NativeDeviceLayout = .tiles
    @AppStorage(NativeBluetoothIdleRelease.enabledKey) private var releaseBluetooth = false
    @AppStorage(NativeBluetoothIdleRelease.minutesKey) private var releaseMinutes = NativeBluetoothIdleRelease.defaultMinutes

    var body: some View {
        Form {
            NativeLaunchAtLoginSection()
            Section {
                Picker("Show lights as", selection: $layout) {
                    ForEach(NativeDeviceLayout.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("Applies to the main window and the menu bar.")
            }
            Section {
                DatePicker("Sunrise", selection: time(
                    hour: manager.sunriseHour, minute: manager.sunriseMinute,
                    set: manager.setSunriseTime), displayedComponents: .hourAndMinute)
                DatePicker("Sunset", selection: time(
                    hour: manager.sunsetHour, minute: manager.sunsetMinute,
                    set: manager.setSunsetTime), displayedComponents: .hourAndMinute)
            } footer: {
                Text("Used by room schedules that run at sunrise or sunset.")
            }
            Section {
                Toggle("Release Bluetooth lights when idle", isOn: $releaseBluetooth)
                Picker("After", selection: $releaseMinutes) {
                    ForEach(NativeBluetoothIdleRelease.minuteChoices, id: \.self) { minutes in
                        Text(minutes == 1 ? "1 minute" : "\(minutes) minutes").tag(minutes)
                    }
                }
                .disabled(!releaseBluetooth)
            } footer: {
                Text("Disconnects lights that only work over Bluetooth after this long without a command, so the Govee app can connect to them. The next command reconnects, which can take up to half a minute.")
            }
            .onChange(of: releaseBluetooth) { _ in NativeBluetoothIdleRelease.apply(to: bluetooth) }
            .onChange(of: releaseMinutes) { _ in NativeBluetoothIdleRelease.apply(to: bluetooth) }
        }
        .formStyle(.grouped)
    }

    private func time(hour: Int, minute: Int, set: @escaping (Int, Int) -> Void) -> Binding<Date> {
        Binding(
            get: { Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date() },
            set: {
                let parts = Calendar.current.dateComponents([.hour, .minute], from: $0)
                set(parts.hour ?? hour, parts.minute ?? minute)
            })
    }
}

private struct NativeNetworkSettings: View {
    @EnvironmentObject private var manager: LightManager
    @EnvironmentObject private var networkGate: NativeNetworkGate

    var body: some View {
        Form {
            Section {
                LabeledContent("This network") {
                    Text(networkGate.current?.title ?? "Not connected")
                }
                ForEach(networkGate.homes) { network in
                    LabeledContent(network.title) {
                        Button("Remove") { networkGate.forget(network) }
                    }
                }
                HStack {
                    Spacer()
                    Button("Add This Network") { networkGate.rememberCurrent() }
                        .disabled(networkGate.current == nil || networkGate.isHome)
                }
            } header: {
                Text("Home networks")
            } footer: {
                Text("On other networks LumenDesk doesn't search for or contact lights on its own. Networks are recognised by their address range, router address and the router's hardware address. A network saved before LumenDesk read that address takes it the next time you're on it.")
            }
            Section {
                LabeledContent("Lights found", value: "\(manager.devices.count)")
                LabeledContent("Last scan") {
                    if let date = manager.lastScanDate {
                        Text(date, style: .relative) + Text(" ago")
                    } else {
                        Text("Never")
                    }
                }
                LabeledContent("Scanning on") {
                    Text(manager.scanInterfaces.isEmpty ? "—" : manager.scanInterfaces.joined(separator: ", "))
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Spacer()
                    Button("Scan Now") { manager.scan() }.disabled(manager.isScanning)
                }
            } footer: {
                Text("Govee lights need LAN Control turned on in the Govee Home app.")
            }
        }
        .formStyle(.grouped)
    }
}
#endif

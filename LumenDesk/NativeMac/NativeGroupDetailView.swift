#if os(macOS)
import SwiftUI

/// Controls for every light, or every light in a room.
struct NativeGroupDetailView: View {
    @EnvironmentObject private var manager: LightManager
    let title: String
    let scope: LightScope
    let lights: [LightDevice]
    @Binding var selection: NativeSidebarItem?
    @AppStorage(NativeDeviceLayout.storageKey) private var layout: NativeDeviceLayout = .tiles

    private var ids: Set<String> { Set(lights.map(\.id)) }

    var body: some View {
        Form {
            if lights.isEmpty {
                Section {
                    Text(scope == .all
                        ? "No lights found yet. LumenDesk keeps scanning your network; you can also scan now with ⌘R."
                        : "This room has no lights yet.")
                        .foregroundStyle(.secondary)
                    if case .room(let roomID) = scope { NativeAddLightsMenu(roomID: roomID) }
                }
            } else {
                Section {
                    Toggle(isOn: Binding(
                        get: { manager.aggregatePowerState(for: lights) == .on },
                        set: { manager.setPower(deviceIDs: ids, on: $0) }
                    )) {
                        Text(title).font(.title3.weight(.semibold))
                        Text(manager.aggregatePowerState(for: lights).title)
                    }
                    .toggleStyle(.switch)

                    NativeGroupBrightnessSlider(lights: lights)

                    NativeColorPicker(title: "Color", color: lights.first?.color ?? .white) {
                        manager.setColor(deviceIDs: ids, color: $0)
                    }

                    NativeKelvinSlider(kelvin: lights.first?.kelvin ?? 4000, range: 2500...9000) {
                        manager.setKelvin(deviceIDs: ids, kelvin: $0)
                    }

                    LabeledContent("Theme") {
                        Menu("Apply") {
                            ForEach(LightingTheme.Category.allCases, id: \.self) { category in
                                Menu(category.rawValue) {
                                    ForEach(LightingCatalog.themes.filter { $0.category == category }) { theme in
                                        Button(theme.name) { manager.applyTheme(theme, deviceIDs: ids, in: scope) }
                                    }
                                }
                            }
                        }
                        .fixedSize()
                    }
                }

                Section {
                    NativeLightCollection(lights: lights, layout: layout) { selection = .light($0.id) }
                        .padding(.vertical, 4)
                } header: {
                    HStack {
                        Text("Lights")
                        Spacer()
                        if case .room(let roomID) = scope {
                            NativeAddLightsMenu(roomID: roomID)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(title)
    }
}

/// One light as a row: status, name, a power switch and optionally brightness. Clicking the name opens it.
struct NativeLightRow: View {
    @EnvironmentObject private var manager: LightManager
    @ObservedObject var device: LightDevice
    var showsBrightness = false
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                NativeStatusIcon(device: device)
                Button(action: onOpen) {
                    VStack(alignment: .leading) {
                        Text(device.label)
                        Text(nativeStatusText(device)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                Spacer()
                Toggle("Power", isOn: Binding(get: { device.isOn }, set: { manager.setPower(device, on: $0) }))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(showsBrightness ? .small : .regular)
            }
            if showsBrightness, device.isOn {
                NativeBrightnessSlider(device: device, showsLabel: false).controlSize(.small)
            }
        }
        .contextMenu { NativeRoomMenu(device: device) }
    }
}

/// "Add Lights" menu listing lights that aren't in this room.
struct NativeAddLightsMenu: View {
    @EnvironmentObject private var manager: LightManager
    let roomID: UUID

    var body: some View {
        let others = manager.devices.filter { manager.room(forLightID: $0.id)?.id != roomID }
        Menu("Add Lights") {
            ForEach(others) { light in
                Button {
                    manager.nativeAssign(light, toRoom: roomID)
                } label: {
                    if let current = manager.room(forLightID: light.id) {
                        Text("\(light.label) (from \(current.name))")
                    } else {
                        Text(light.label)
                    }
                }
            }
        }
        .disabled(others.isEmpty)
        .fixedSize()
    }
}
#endif

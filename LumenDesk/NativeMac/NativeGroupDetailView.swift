#if os(macOS)
import SwiftUI

/// Controls for every light, or every light in a room.
struct NativeGroupDetailView: View {
    @EnvironmentObject private var manager: LightManager
    let title: String
    let scope: LightScope
    let lights: [LightDevice]
    @Binding var selection: NativeSidebarItem?

    private var ids: Set<String> { Set(lights.map(\.id)) }

    var body: some View {
        Form {
            if lights.isEmpty {
                Section {
                    Text(scope == .all
                        ? "No lights found yet. LumenDesk keeps scanning your network; you can also scan now with ⌘R."
                        : "This room has no lights yet.")
                        .foregroundStyle(.secondary)
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

                Section("Lights") {
                    ForEach(lights) { light in
                        NativeLightRow(device: light) { selection = .light(light.id) }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(title)
    }
}

/// One light inside a group: status, name, and a power switch. Clicking the name opens it.
struct NativeLightRow: View {
    @EnvironmentObject private var manager: LightManager
    @ObservedObject var device: LightDevice
    let onOpen: () -> Void

    var body: some View {
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
        }
    }
}
#endif

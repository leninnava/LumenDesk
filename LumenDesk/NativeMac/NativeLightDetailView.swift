#if os(macOS)
import SwiftUI

/// Controls for one light, as a grouped macOS form.
struct NativeLightDetailView: View {
    @EnvironmentObject private var manager: LightManager
    @ObservedObject var device: LightDevice

    @State private var name = ""

    private enum Mode: String, CaseIterable, Identifiable {
        case color = "Color"
        case white = "White"
        var id: Self { self }
    }

    private var mode: Binding<Mode> {
        Binding(
            get: { manager.isWhiteMode(device.id) ? .white : .color },
            set: { newMode in
                switch newMode {
                case .white:
                    manager.setWhiteMode(device.id, white: true)
                    manager.setKelvin(device, kelvin: device.kelvin)
                case .color:
                    manager.setWhiteMode(device.id, white: false)
                    manager.setColor(device, color: device.color)
                }
            })
    }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(get: { device.isOn }, set: { manager.setPower(device, on: $0) })) {
                    Label {
                        Text(device.label).font(.title3.weight(.semibold))
                        Text(subtitle)
                    } icon: {
                        NativeStatusIcon(device: device).font(.title2)
                    }
                }
                .toggleStyle(.switch)

                if device.isStale {
                    LabeledContent("Not responding") {
                        Button("Retry") { manager.retry(device) }
                    }
                    .foregroundStyle(.orange)
                }

                NativeBrightnessSlider(device: device)
            }

            Section("Color") {
                Picker("Mode", selection: mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                if mode.wrappedValue == .color {
                    NativeColorPicker(title: "Color", color: device.color) {
                        manager.setColor(device, color: $0)
                    }
                } else {
                    NativeKelvinSlider(kelvin: device.kelvin, range: device.kelvinRange) {
                        manager.setKelvin(device, kelvin: $0)
                    }
                    .id(device.id)
                }
            }

            if device.brand == .govee {
                NativeGoveeScenesSection(device: device)
                if let count = manager.nativeSegmentCount(for: device) {
                    NativeGoveeSegmentsSection(device: device, count: count)
                }
            }

            Section("Device") {
                TextField("Name", text: $name)
                    .onSubmit { manager.setCustomName(device.id, name: name) }
                LabeledContent("Brand", value: device.brand.rawValue.capitalized)
                if let sku = device.sku { LabeledContent("Model", value: sku) }
                LabeledContent("Address", value: device.address)
                LabeledContent("Last seen") {
                    Text(device.lastSeen, style: .relative) + Text(" ago")
                }
                Button("Identify") { manager.identify(device) }
            }

            Section {
                DisclosureGroup("Diagnostics") {
                    ForEach(manager.diagnostics(for: device)) { item in
                        LabeledContent(item.title, value: item.value)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(device.label)
        .onAppear { name = device.label }
        .onChange(of: device.id) { _ in name = device.label }
    }

    private var subtitle: String {
        [device.brand.rawValue.capitalized, device.sku, nativeStatusText(device)]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}
#endif

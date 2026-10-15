#if os(macOS)
import SwiftUI

// Building blocks for the native macOS interface (fork). They route through
// LightManager's existing command paths, so queueing, undo and staleness
// handling stay identical to the original UI.

/// Light bulb glyph tinted with the light's colour, or slashed when it stopped answering.
struct NativeStatusIcon: View {
    @ObservedObject var device: LightDevice

    var body: some View {
        Image(systemName: device.isStale ? "lightbulb.slash" : (device.isOn ? "lightbulb.fill" : "lightbulb"))
            .foregroundStyle(device.isStale ? Color.secondary : (device.isOn ? device.color : Color.secondary))
            .frame(width: 18)
            .accessibilityLabel(device.isStale ? "Not responding" : (device.isOn ? "On" : "Off"))
    }
}

/// "On · 62%", "Off", or "Not responding" (with a hint to check power when `detailed`).
func nativeStatusText(_ device: LightDevice, detailed: Bool = false) -> String {
    NativeOverviewSummary.lightStatus(isOn: device.isOn, brightness: device.brightness,
                                      isStale: device.isStale, detailed: detailed)
}

/// Previews brightness while dragging (the engine debounces sends) and commits on release.
struct NativeBrightnessSlider: View {
    @EnvironmentObject private var manager: LightManager
    @ObservedObject var device: LightDevice
    var showsLabel = true

    var body: some View {
        Slider(
            value: Binding(
                get: { device.brightness },
                set: { manager.previewBrightness(device, value: $0) }),
            in: 0.01...1,
            label: { Text("Brightness") },
            minimumValueLabel: { Image(systemName: "sun.min").foregroundStyle(.secondary) },
            maximumValueLabel: { Image(systemName: "sun.max").foregroundStyle(.secondary) },
            onEditingChanged: { editing in
                if !editing { manager.commitBrightness(device, value: device.brightness) }
            }
        )
        .labelsHidden(!showsLabel)
    }
}

/// Brightness for several lights at once; sends a single command when the drag ends.
struct NativeGroupBrightnessSlider: View {
    @EnvironmentObject private var manager: LightManager
    let lights: [LightDevice]
    /// Explains what the slider changes, under its label.
    var caption: String?
    /// Shows the value as a percentage after the slider, updating while dragging.
    var showsPercent = false
    @State private var value: Double = 1

    private var average: Double {
        lights.isEmpty ? 1 : lights.map(\.brightness).reduce(0, +) / Double(lights.count)
    }

    var body: some View {
        HStack {
            Slider(
                value: $value,
                in: 0.01...1,
                label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Brightness")
                        if let caption {
                            Text(caption).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                },
                minimumValueLabel: { Image(systemName: "sun.min").foregroundStyle(.secondary) },
                maximumValueLabel: { Image(systemName: "sun.max").foregroundStyle(.secondary) },
                onEditingChanged: { editing in
                    if !editing { manager.setBrightness(deviceIDs: Set(lights.map(\.id)), value: value) }
                }
            )
            .accessibilityValue(NativeOverviewSummary.percent(value))
            if showsPercent {
                Text(NativeOverviewSummary.percent(value))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 38, alignment: .trailing)
                    .accessibilityHidden(true)
            }
        }
        .onAppear { value = average }
        .onChange(of: lights.map(\.id)) { _ in value = average }
        .onChange(of: average) { new in value = new }
    }
}

/// The system colour well. The colour panel reports every drag step, so changes
/// are sent once they settle instead of flooding the light.
struct NativeColorPicker: View {
    let title: String
    /// Explains what picking a colour changes, under the title.
    var caption: String?
    let color: Color
    let onCommit: (Color) -> Void

    @State private var draft: Color = .white
    @State private var pending: Task<Void, Never>?

    var body: some View {
        ColorPicker(selection: $draft, supportsOpacity: false) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let caption {
                    Text(caption).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
            .onAppear { draft = color }
            .onChange(of: color) { external in
                if external.rgbDistance(to: draft) > 0.01 { draft = external }
            }
            .onChange(of: draft) { new in
                guard new.rgbDistance(to: color) > 0.01 else { return }
                pending?.cancel()
                pending = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 150_000_000)
                    guard !Task.isCancelled else { return }
                    onCommit(new)
                }
            }
    }
}

/// White temperature from warm to cool; sends when the drag ends.
struct NativeKelvinSlider: View {
    let kelvin: Int
    /// Explains what the slider changes, under its label.
    var caption: String?
    let range: ClosedRange<Double>
    let onCommit: (Int) -> Void
    @State private var value: Double = 4000

    var body: some View {
        LabeledContent {
            Slider(
                value: $value,
                in: range,
                step: 100,
                label: { Text("White temperature") },
                minimumValueLabel: { Text("Warm").font(.caption).foregroundStyle(.secondary) },
                maximumValueLabel: { Text("Cool").font(.caption).foregroundStyle(.secondary) },
                onEditingChanged: { editing in
                    if !editing { onCommit(Int(value)) }
                }
            )
            .labelsHidden()
        } label: {
            Text("Temperature")
            Text("\(Int(value)) K").monospacedDigit()
            if let caption {
                Text(caption).font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear { value = min(max(Double(kelvin), range.lowerBound), range.upperBound) }
    }
}

private extension View {
    @ViewBuilder func labelsHidden(_ hidden: Bool) -> some View {
        if hidden { labelsHidden() } else { self }
    }
}
#endif

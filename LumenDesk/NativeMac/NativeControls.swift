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

/// "On · 62%", "Off", or "Not responding".
func nativeStatusText(_ device: LightDevice) -> String {
    if device.isStale { return "Not responding" }
    return device.isOn ? "On · \(Int((device.brightness * 100).rounded()))%" : "Off"
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
    @State private var value: Double = 1

    private var average: Double {
        lights.isEmpty ? 1 : lights.map(\.brightness).reduce(0, +) / Double(lights.count)
    }

    var body: some View {
        Slider(
            value: $value,
            in: 0.01...1,
            label: { Text("Brightness") },
            minimumValueLabel: { Image(systemName: "sun.min").foregroundStyle(.secondary) },
            maximumValueLabel: { Image(systemName: "sun.max").foregroundStyle(.secondary) },
            onEditingChanged: { editing in
                if !editing { manager.setBrightness(deviceIDs: Set(lights.map(\.id)), value: value) }
            }
        )
        .onAppear { value = average }
        .onChange(of: lights.map(\.id)) { _ in value = average }
    }
}

/// The system colour well. The colour panel reports every drag step, so changes
/// are sent once they settle instead of flooding the light.
struct NativeColorPicker: View {
    let title: String
    let color: Color
    let onCommit: (Color) -> Void

    @State private var draft: Color = .white
    @State private var pending: Task<Void, Never>?

    var body: some View {
        ColorPicker(title, selection: $draft, supportsOpacity: false)
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

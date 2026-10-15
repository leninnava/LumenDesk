#if os(macOS)
import SwiftUI

/// How lights are shown in the window and the menu bar. Tiles are the default.
enum NativeDeviceLayout: String, CaseIterable, Identifiable {
    case tiles
    case list

    static let storageKey = "Native.deviceLayout"

    var id: Self { self }
    var title: String { self == .tiles ? "Tiles" : "List" }
    var symbol: String { self == .tiles ? "square.grid.2x2" : "list.bullet" }
}

/// A light as a tile: click to switch it on or off. Tinted with the light's colour when on.
struct NativeLightTile: View {
    @EnvironmentObject private var manager: LightManager
    @ObservedObject var device: LightDevice
    var compact = false
    var onOpen: (() -> Void)?
    @State private var renaming = false

    var body: some View {
        Button {
            manager.setPower(device, on: !device.isOn)
        } label: {
            VStack(alignment: .leading, spacing: compact ? 4 : 8) {
                Image(systemName: device.isStale ? "lightbulb.slash" : (device.isOn ? "lightbulb.fill" : "lightbulb"))
                    .font(compact ? .title3 : .title2)
                    .foregroundStyle(iconColor)
                Spacer(minLength: 0)
                Text(device.label)
                    .font(compact ? .callout.weight(.medium) : .body.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(nativeStatusText(device))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: compact ? 70 : 96, alignment: .topLeading)
            .padding(compact ? 10 : 12)
            .background(background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08)))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(device.isOn ? "Turn off \(device.label)" : "Turn on \(device.label)")
        .accessibilityLabel("\(device.label), \(nativeStatusText(device))")
        .contextMenu {
            if let onOpen {
                Button("Open", action: onOpen)
                // Alerts can't be shown from the menu bar panel, so renaming is window-only.
                Button("Rename…") { renaming = true }
            }
            NativeRoomMenu(device: device)
            Button("Identify") { manager.identify(device) }
        }
        .nativeRenameLightAlert(device, isPresented: $renaming, manager: manager)
        .overlay(alignment: .topTrailing) {
            if let onOpen {
                Button(action: onOpen) {
                    Image(systemName: "info.circle").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(8)
                .help("Show \(device.label)")
            }
        }
    }

    private var iconColor: Color {
        if device.isStale { return .secondary }
        return device.isOn ? device.color : .secondary
    }

    private var background: Color {
        guard device.isOn, !device.isStale else { return Color.primary.opacity(0.05) }
        return device.color.opacity(0.22)
    }
}

/// A set of lights in the chosen layout.
struct NativeLightCollection: View {
    let lights: [LightDevice]
    let layout: NativeDeviceLayout
    var compact = false
    var onOpen: ((LightDevice) -> Void)?

    var body: some View {
        switch layout {
        case .tiles where compact:
            // The menu bar panel sizes itself to its content; a lazy grid there can measure as
            // empty, so use plain rows of two.
            VStack(spacing: 8) {
                ForEach(Array(stride(from: 0, to: lights.count, by: 2)), id: \.self) { start in
                    HStack(spacing: 8) {
                        ForEach(lights[start..<min(start + 2, lights.count)]) { light in
                            NativeLightTile(device: light, compact: true)
                        }
                        if start + 1 >= lights.count { Color.clear.frame(maxWidth: .infinity) }
                    }
                }
            }
        case .tiles:
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                ForEach(lights) { light in
                    NativeLightTile(device: light, onOpen: onOpen.map { open in { open(light) } })
                }
            }
        case .list:
            VStack(spacing: 8) {
                ForEach(lights) { light in
                    NativeLightRow(device: light, showsBrightness: compact) { onOpen?(light) }
                }
            }
        }
    }
}
#endif

#if os(macOS)
import SwiftUI

// Govee scenes and segments (fork). Frames go over Bluetooth for models that ignore them on
// LAN (see GoveeBluetoothProtocol.framesOnlyOverBluetooth), otherwise over LAN `ptReal`.

extension LightManager {
    /// Number of independently colourable segments, if known for this model.
    func nativeSegmentCount(for device: LightDevice) -> Int? {
        guard device.brand == .govee, let sku = device.sku else { return nil }
        if let count = GoveeBluetoothProtocol.bluetoothSegmentCounts[sku] { return count }
        guard let profile = segmentProfile(for: device), profile.recognized else { return nil }
        return profile.defaultSegmentCount
    }
}

@MainActor
private func sendGoveeFrames(_ frames: [[UInt8]], to device: LightDevice,
                             manager: LightManager, bluetooth: GoveeBluetoothController) {
    if GoveeBluetoothController.requiresBluetooth(device) {
        bluetooth.send(frames, to: device)
    } else {
        manager.sendGoveeFrames(device, frames: frames)
    }
}

/// Bluetooth link status, for lights that need it.
private struct NativeBluetoothStatus: View {
    @EnvironmentObject private var bluetooth: GoveeBluetoothController
    @ObservedObject var device: LightDevice

    var body: some View {
        if GoveeBluetoothController.requiresBluetooth(device) {
            let state = bluetooth.states[device.id]
            Label(state?.title ?? "Uses Bluetooth for scenes and segments",
                  systemImage: state == .connected ? "dot.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right")
                .foregroundStyle(state.map { if case .unavailable = $0 { return Color.orange } else { return Color.secondary } }
                                 ?? Color.secondary)
        }
    }
}

struct NativeGoveeScenesSection: View {
    @EnvironmentObject private var manager: LightManager
    @EnvironmentObject private var bluetooth: GoveeBluetoothController
    @EnvironmentObject private var sceneStore: GoveeSceneStore
    @ObservedObject var device: LightDevice
    @State private var lastScene: String?

    var body: some View {
        Section {
            switch device.sku.flatMap({ sceneStore.status[$0] }) {
            case .loaded(let scenes)?:
                LabeledContent("Scene") {
                    Menu(lastScene ?? "Choose…") {
                        ForEach(categories(scenes), id: \.self) { category in
                            Menu(category) {
                                ForEach(scenes.filter { $0.category == category }) { scene in
                                    Button(scene.name) { apply(scene) }
                                }
                            }
                        }
                    }
                    .fixedSize()
                }
            case .failed(let message)?:
                LabeledContent {
                    Button("Retry") { device.sku.map(sceneStore.load) }
                } label: {
                    Text(message).foregroundStyle(.secondary)
                }
            case .loading?, nil:
                LabeledContent("Scene") { ProgressView().controlSize(.small) }
            }
        } header: {
            Text("Scenes")
        } footer: {
            NativeBluetoothStatus(device: device)
        }
        .onAppear {
            if let sku = device.sku { sceneStore.load(sku: sku) }
            if GoveeBluetoothController.requiresBluetooth(device) { bluetooth.prepare(device) }
        }
    }

    /// Categories in catalogue order.
    private func categories(_ scenes: [GoveeScene]) -> [String] {
        var seen = Set<String>()
        return scenes.map(\.category).filter { seen.insert($0).inserted }
    }

    private func apply(_ scene: GoveeScene) {
        lastScene = scene.name
        sendGoveeFrames(scene.frames, to: device, manager: manager, bluetooth: bluetooth)
        manager.logActivity(.command, title: "Scene applied", detail: "\(device.label): \(scene.name)")
    }
}

struct NativeGoveeSegmentsSection: View {
    @EnvironmentObject private var manager: LightManager
    @EnvironmentObject private var bluetooth: GoveeBluetoothController
    @ObservedObject var device: LightDevice
    let count: Int

    @State private var selected: Set<Int> = []
    /// What we last sent; the light doesn't report segment colours.
    @State private var colors: [Int: Color] = [:]
    @State private var color: Color = .red

    var body: some View {
        Section {
            NativeSegmentRing(count: count, selected: $selected, colors: colors)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)

            HStack {
                Button("Select All") { selected = Set(0..<count) }
                Button("Select None") { selected = [] }
                Spacer()
                Text(selected.isEmpty ? "Click segments to select them" : "\(selected.count) selected")
                    .foregroundStyle(.secondary)
            }

            HStack {
                ColorPicker("Color", selection: $color, supportsOpacity: false)
                Spacer()
                Button("Apply to Selected", action: apply)
                    .disabled(selected.isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        } header: {
            Text(GoveeBluetoothProtocol.bluetoothSegmentCounts[device.sku ?? ""] != nil ? "Ring" : "Segments")
        } footer: {
            NativeBluetoothStatus(device: device)
        }
    }
}

extension NativeGoveeSegmentsSection {
    private func apply() {
        guard !selected.isEmpty else { return }
        let rgb = color.rgbComponents
        let frame = GoveeBluetoothProtocol.segmentColorFrame(
            (Int(rgb.r * 255), Int(rgb.g * 255), Int(rgb.b * 255)), segments: selected.sorted())
        sendGoveeFrames([frame], to: device, manager: manager, bluetooth: bluetooth)
        for index in selected { colors[index] = color }
    }
}

/// Segments drawn as dots around a circle; click to toggle selection.
private struct NativeSegmentRing: View {
    let count: Int
    @Binding var selected: Set<Int>
    let colors: [Int: Color]

    private let diameter: CGFloat = 170
    private let dot: CGFloat = 22

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
                .frame(width: diameter - dot, height: diameter - dot)
            ForEach(0..<count, id: \.self) { index in
                let angle = Double(index) / Double(count) * 2 * .pi - .pi / 2
                Button {
                    if selected.contains(index) { selected.remove(index) } else { selected.insert(index) }
                } label: {
                    Circle()
                        .fill(colors[index] ?? Color.secondary.opacity(0.25))
                        .frame(width: dot, height: dot)
                        .overlay(Circle().strokeBorder(selected.contains(index) ? Color.accentColor : .clear,
                                                       lineWidth: 3))
                        .overlay(Text("\(index + 1)").font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary).opacity(colors[index] == nil ? 1 : 0))
                }
                .buttonStyle(.plain)
                .help("Segment \(index + 1)")
                .offset(x: cos(angle) * (diameter - dot) / 2, y: sin(angle) * (diameter - dot) / 2)
            }
        }
        .frame(width: diameter, height: diameter)
    }
}
#endif

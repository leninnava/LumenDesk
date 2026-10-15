#if os(macOS)
import SwiftUI

/// Saved scenes: apply, rename, delete, and save the current lights as a new one.
///
/// Apply and Delete go through the engine's own confirmations, which say which
/// lights a scene touches and offer undo afterwards.
struct NativeSceneLibraryView: View {
    @EnvironmentObject private var manager: LightManager
    @State private var capturing = false
    @State private var renaming: LightingScene?

    var body: some View {
        Form {
            if let result = manager.lastSceneResult, !result.failedIDs.isEmpty {
                Section {
                    HStack {
                        Label("\(result.failedIDs.count) light\(result.failedIDs.count == 1 ? "" : "s") in “\(result.sceneName)” didn’t respond.",
                              systemImage: "exclamationmark.triangle")
                        Spacer()
                        Button("Retry") { manager.retryLastSceneFailures() }
                    }
                }
            }
            Section {
                if manager.scenes.isEmpty {
                    Text("A scene remembers each light’s power, colour and brightness so you can bring the look back later.")
                        .foregroundStyle(.secondary)
                }
                ForEach(manager.scenes) { scene in
                    NativeSceneRow(scene: scene) { renaming = scene }
                }
            } header: {
                HStack {
                    Text("Scenes")
                    Spacer()
                    Button("Save Current Lights as Scene…") { capturing = true }
                        .buttonStyle(.borderless)
                        .disabled(manager.devices.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Scenes")
        .sheet(isPresented: $capturing) { NativeCaptureSceneSheet() }
        .nativeRoomNameAlert(
            isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } }),
            title: "Rename Scene", placeholder: "Scene name",
            initialName: renaming?.name ?? "", confirmTitle: "Rename"
        ) { name in
            if let scene = renaming { manager.renameScene(scene.id, to: name) }
        }
    }
}

/// One scene: name, which lights it covers, and how many are reachable now.
private struct NativeSceneRow: View {
    @EnvironmentObject private var manager: LightManager
    let scene: LightingScene
    let onRename: () -> Void

    var body: some View {
        let preview = manager.scenePreview(scene)
        let available = preview.affected.count - preview.unreachable.count
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(scene.name)
                Text(manager.sceneScopeSummary(scene).description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if available < scene.snapshots.count {
                    Text("\(available) of \(scene.snapshots.count) lights available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Apply") { manager.applyScene(scene) }
                .disabled(available == 0)
                .help(available == 0 ? "None of this scene’s lights are available" : "Apply “\(scene.name)”")
            Menu {
                Button("Apply Without Turning Lights Off") {
                    manager.applyScene(scene, allowTurningOff: false)
                }
                .disabled(available == 0)
                Button("Rename…", action: onRename)
                Divider()
                Button("Delete", role: .destructive) { manager.deleteScene(scene.id) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("More")
        }
        .contextMenu {
            Button("Apply") { manager.applyScene(scene) }.disabled(available == 0)
            Button("Rename…", action: onRename)
            Divider()
            Button("Delete", role: .destructive) { manager.deleteScene(scene.id) }
        }
    }
}

/// Names a new scene and picks which lights it captures.
private struct NativeCaptureSceneSheet: View {
    @EnvironmentObject private var manager: LightManager
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var scope: LightScope = .all

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var lightCount: Int { manager.devices(in: scope).count }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Name", text: $name, prompt: Text("Evening"))
                Picker("Lights", selection: $scope) {
                    Text("All Lights").tag(LightScope.all)
                    ForEach(manager.rooms) { Text($0.name).tag(LightScope.room($0.id)) }
                }
                LabeledContent("Captures", value: "\(lightCount) light\(lightCount == 1 ? "" : "s")")
            }
            .formStyle(.grouped)
            HStack {
                if let message = manager.duplicateSceneNameMessage(trimmed) {
                    Text(message).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    manager.captureScene(name: trimmed, scope: scope)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmed.isEmpty || lightCount == 0 || manager.duplicateSceneNameMessage(trimmed) != nil)
            }
            .padding()
        }
        .frame(width: 400)
    }
}
#endif

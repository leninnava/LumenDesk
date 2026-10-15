#if os(macOS)
import SwiftUI

/// Music Mode: lights follow the audio playing on this Mac.
///
/// Only the essentials: where, which preset and palette, a few levels, the
/// no-flash switch, and the audio source's permission state. Fixture roles,
/// timing calibration and the other sources (file, MIDI clock) stay with the
/// saved configuration and aren't edited here.
struct NativeMusicView: View {
    @EnvironmentObject private var manager: LightManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scope: LightScope = .all
    @State private var confirmingFlashes = false

    private static let musicEffectID = "music-pulse"

    private var configuration: MusicModeConfiguration { manager.musicModeConfiguration }
    private var isRunning: Bool { manager.activeEffects[scope] == Self.musicEffectID }

    /// The lights the show would drive, after the scope's saved exclusions and "Off" roles.
    private var includedCount: Int {
        let fixtures = manager.musicFixtureDescriptors(in: scope)
        return manager.fixtureTopology(for: scope).includedFixtures(fixtures)
            .filter { $0.resolvedRole != .off }.count
    }

    /// Other places a show is running.
    private var otherShows: [LightScope] {
        manager.activeEffects.filter { $0.value == Self.musicEffectID && $0.key != scope }.map(\.key)
            .sorted { manager.scopeDisplayName($0) < manager.scopeDisplayName($1) }
    }

    var body: some View {
        Form {
            Section {
                Picker("Lights", selection: $scope) {
                    Text("All Lights").tag(LightScope.all)
                    ForEach(manager.rooms) { Text($0.name).tag(LightScope.room($0.id)) }
                }
                LabeledContent {
                    if isRunning {
                        Button("Stop") { manager.stopEffect(scope: scope) }
                    } else {
                        Button("Start") {
                            manager.startMusicMode(configuration: configuration, scope: scope,
                                                   reducedMotion: reduceMotion)
                        }
                        .keyboardShortcut(.defaultAction)
                        .disabled(includedCount == 0)
                    }
                } label: {
                    Text(isRunning ? "Playing" : "Stopped")
                    Text(includedCount == 0
                         ? "No lights to play on"
                         : "\(includedCount) light\(includedCount == 1 ? "" : "s") · \(configuration.preset.displayName)")
                }
                ForEach(otherShows, id: \.self) { other in
                    LabeledContent {
                        Button("Stop") { manager.stopEffect(scope: other) }
                    } label: {
                        Text("Also playing")
                        Text(manager.scopeDisplayName(other))
                    }
                }
            } footer: {
                Text(configuration.restorePreviousState
                     ? "Stopping returns the lights to how they were before the show."
                     : "Stopping leaves the lights as the show last set them.")
            }

            NativeMusicAudioSection(controller: manager.musicModeController, isRunning: isRunning)

            Section("Show") {
                Picker("Preset", selection: Binding(
                    get: { configuration.preset },
                    set: { manager.applyMusicModePreset($0) }
                )) {
                    ForEach(MusicModePreset.allCases) { Text($0.displayName).tag($0) }
                }
                Text(configuration.preset.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Colours", selection: paletteBinding) {
                    ForEach(MusicModeConfiguration.builtInPalettes) { Text($0.name).tag($0.id) }
                    ForEach(LightingTheme.Category.allCases, id: \.self) { category in
                        Section(category.rawValue) {
                            ForEach(LightingCatalog.themes.filter { $0.category == category }) {
                                Text($0.name).tag($0.id)
                            }
                        }
                    }
                    if configuration.paletteIdentity == "custom" {
                        Divider()
                        Text("Custom").tag("custom")
                    }
                }

                slider("Brightness", \.masterBrightness)
                slider("Intensity", \.effectIntensity)
                slider("Beat sensitivity", \.beatSensitivity)
            }

            Section {
                Toggle("No-flash mode", isOn: Binding(
                    get: { configuration.photosensitivitySafeMode },
                    set: { enabled in
                        if enabled {
                            update(\.photosensitivitySafeMode, true)
                        } else {
                            confirmingFlashes = true
                        }
                    }))
                Toggle("Restore lights when stopped", isOn: Binding(
                    get: { configuration.restorePreviousState },
                    set: { value in
                        // Restoring is about the room, not the show, so it keeps the preset.
                        var changed = configuration
                        changed.restorePreviousState = value
                        manager.setMusicModeConfiguration(changed)
                    }))
            } footer: {
                Text(reduceMotion
                     ? "Reduce Motion is on, so flashes stay off whatever this says."
                     : "No-flash mode is on by default. Flashing light can trigger seizures and migraines in some people.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Music")
        .onChange(of: manager.rooms.map(\.id)) { ids in
            if case .room(let id) = scope, !ids.contains(id) { scope = .all }
        }
        .alert("Allow flashes?", isPresented: $confirmingFlashes) {
            Button("Keep No-Flash Mode", role: .cancel) {}
            Button("Allow Flashes", role: .destructive) { update(\.photosensitivitySafeMode, false) }
        } message: {
            Text("Music Mode still never flashes more than 3 times a second, but flashing can affect people with photosensitivity.")
        }
    }

    // MARK: Editing

    /// Picking a palette changes the colours only (see `selectPalette`).
    private var paletteBinding: Binding<String> {
        Binding(
            get: { configuration.paletteIdentity },
            set: { identity in
                guard identity != "custom" else { return }
                var changed = configuration
                changed.selectPalette(identity)
                manager.setMusicModeConfiguration(changed)
            })
    }

    /// Changing a show setting turns the preset into Custom, as the full editor does.
    private func update<Value>(_ keyPath: WritableKeyPath<MusicModeConfiguration, Value>, _ value: Value) {
        var changed = configuration
        changed[keyPath: keyPath] = value
        changed.preset = .custom
        manager.setMusicModeConfiguration(changed)
    }

    /// Drags reach a running show live; the release saves.
    private func slider(_ title: String, _ keyPath: WritableKeyPath<MusicModeConfiguration, Double>) -> some View {
        LabeledContent {
            Slider(
                value: Binding(
                    get: { configuration[keyPath: keyPath] },
                    set: { value in
                        var changed = configuration
                        changed[keyPath: keyPath] = value
                        changed.preset = .custom
                        manager.previewMusicModeConfiguration(changed)
                    }),
                in: 0...1,
                label: { Text(title) },
                onEditingChanged: { editing in
                    if !editing { manager.setMusicModeConfiguration(manager.musicModeConfiguration) }
                })
            .labelsHidden()
        } label: {
            Text(title)
            Text("\(Int((configuration[keyPath: keyPath] * 100).rounded()))%").monospacedDigit()
        }
    }
}

/// The audio source and its permission. On the Mac, Music Mode listens to system
/// audio through ScreenCaptureKit, which needs Screen & System Audio Recording.
private struct NativeMusicAudioSection: View {
    @ObservedObject var controller: AudioReactiveSessionController
    let isRunning: Bool

    private static let screenRecordingPane =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"

    var body: some View {
        Section {
            LabeledContent("Source") {
                Text(controller.sourceStatus == .idle ? "System audio" : controller.sourceStatus.displayName)
            }
            if isRunning {
                LabeledContent("Input") {
                    Label(controller.isAudioPlaying ? "Hearing audio" : controller.inputHealth.displayName,
                          systemImage: controller.isAudioPlaying ? "waveform" : "speaker.slash")
                }
            }
            switch controller.sourceStatus {
            case .permissionDenied:
                LabeledContent {
                    Button("Open Privacy Settings") { PlatformOpener.openSettings(macPane: Self.screenRecordingPane) }
                } label: {
                    Label("Permission needed", systemImage: "lock")
                    Text("Allow LumenDesk under Screen & System Audio Recording, then press Start again.")
                }
            case .unavailable:
                Label(isRunning ? "Audio capture was interrupted." : "Audio capture is unavailable. Press Start to try again.",
                      systemImage: "exclamationmark.triangle")
            default:
                EmptyView()
            }
            if isRunning, controller.canRestartSystemAudio, !controller.isAudioPlaying {
                LabeledContent {
                    Button("Restart Audio") { controller.restartSystemAudio() }
                        .disabled(controller.sourceStatus == .requestingPermission)
                } label: {
                    Text("Nothing heard")
                    Text("Play something on this Mac. If music is playing and nothing is heard, restart the audio.")
                }
            }
        } header: {
            Text("Audio")
        } footer: {
            Text("LumenDesk listens to whatever is playing on this Mac. macOS asks for Screen & System Audio Recording permission the first time, because that permission is how apps hear system audio.")
        }
    }
}
#endif

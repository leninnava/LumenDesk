#if os(macOS)
import SwiftUI

/// Animated effects for every light or one room. The engine runs one effect per
/// scope; starting one takes its lights over from any other running effect, and
/// stopping restores the lights to how they were before.
struct NativeEffectsSection: View {
    @EnvironmentObject private var manager: LightManager
    let scope: LightScope
    let lights: [LightDevice]

    /// Music Mode is an effect to the engine but has its own screen.
    private static let musicEffectID = "music-pulse"

    private var calmEffects: [LightingEffect] {
        LightingCatalog.effects.filter { $0.id != Self.musicEffectID && !$0.isHighEnergy }
    }

    private var livelyEffects: [LightingEffect] {
        LightingCatalog.effects.filter { $0.id != Self.musicEffectID && $0.isHighEnergy }
    }

    private var runningID: String? { manager.activeEffects[scope] }

    /// Effects started elsewhere (All Lights, or another scope) that animate lights shown here.
    private var otherRuns: [(scope: LightScope, name: String)] {
        var seen = Set<LightScope>()
        return lights.compactMap { manager.animatingEffect(for: $0.id) }
            .filter { $0.scope != scope && seen.insert($0.scope).inserted }
    }

    var body: some View {
        Section {
            if let runningID {
                LabeledContent {
                    Button("Stop") { manager.stopEffect(scope: scope) }
                } label: {
                    Label(runningID == Self.musicEffectID ? "Music Mode" : effectName(runningID),
                          systemImage: effectIcon(runningID))
                    Text(runningID == Self.musicEffectID ? "Running · change it in Music" : "Running")
                }
            }
            ForEach(otherRuns, id: \.scope) { run in
                LabeledContent {
                    Button("Stop") { manager.stopEffect(scope: run.scope) }
                } label: {
                    Text(run.name)
                    Text("Running on \(manager.scopeDisplayName(run.scope))")
                }
            }
            LabeledContent(runningID == nil ? "Effect" : "Switch to") {
                Menu("Start") {
                    Section {
                        ForEach(calmEffects) { effectButton($0) }
                    }
                    Section("Lively") {
                        ForEach(livelyEffects) { effectButton($0) }
                    }
                }
                .fixedSize()
            }
        } header: {
            Text("Effects")
        } footer: {
            Text("Stopping an effect returns the lights to how they were before it started.")
        }
    }

    private func effectButton(_ effect: LightingEffect) -> some View {
        Button {
            manager.startEffect(effect, scope: scope)
        } label: {
            Label(effect.name, systemImage: effect.icon)
        }
        .help(effect.summary)
    }

    private func effectName(_ id: String) -> String {
        LightingCatalog.effects.first { $0.id == id }?.name ?? id
    }

    private func effectIcon(_ id: String) -> String {
        LightingCatalog.effects.first { $0.id == id }?.icon ?? "sparkles"
    }
}
#endif

#if os(macOS)
import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Settings → Shortcuts: one recorder per action, plus one per room.
struct NativeShortcutsSettings: View {
    @EnvironmentObject private var manager: LightManager
    @EnvironmentObject private var shortcuts: NativeShortcutCenter

    var body: some View {
        Form {
            Section {
                ForEach(NativeShortcutAction.general, id: \.self) { row($0) }
            } footer: {
                Text("Brighten and dim change the lights that are on by 10%.")
            }
            Section {
                if manager.rooms.isEmpty {
                    Text("Rooms you create can each have a shortcut.").foregroundStyle(.secondary)
                }
                ForEach(manager.rooms) { row(.toggleRoom($0.id)) }
            } header: {
                Text("Rooms")
            } footer: {
                Text("Shortcuts work in every app. Click one, then press the keys, including ⌘, ⌥ or ⌃. Esc cancels; Delete clears.")
            }
        }
        .formStyle(.grouped)
    }

    private func row(_ action: NativeShortcutAction) -> some View {
        LabeledContent(shortcuts.title(for: action)) {
            HStack(spacing: 6) {
                if shortcuts.unavailable.contains(action) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .help("Another app is using this shortcut. Record a different one.")
                }
                NativeShortcutRecorder(combo: shortcuts.shortcuts[action]) { shortcuts.set($0, for: action) }
            }
        }
    }
}

/// Records a key combination: click, press the keys; Esc cancels and Delete clears.
struct NativeShortcutRecorder: View {
    let combo: NativeKeyCombo?
    /// Returns why the combination was refused, if it was.
    let onChange: (NativeKeyCombo?) -> String?

    @EnvironmentObject private var center: NativeShortcutCenter
    @State private var recording = false
    @State private var monitor: Any?
    @State private var problem: String?

    var body: some View {
        Button {
            recording ? stop() : start()
        } label: {
            Text(recording ? "Type Shortcut…" : combo?.title ?? "Record Shortcut")
                .foregroundStyle(recording || combo == nil ? Color.secondary : Color.primary)
                .frame(minWidth: 110)
        }
        .help(combo == nil ? "Click, then press the keys" : "Click to change; Delete clears")
        .popover(isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
            Text(problem ?? "").padding(10).frame(maxWidth: 260)
        }
        .onDisappear { stop() }
    }

    private func start() {
        problem = nil
        recording = true
        center.setPaused(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        guard recording else { return }
        recording = false
        center.setPaused(false)
    }

    private func handle(_ event: NSEvent) {
        let plain = event.modifierFlags.isDisjoint(with: NativeKeyCombo.relevantModifiers)
        switch Int(event.keyCode) {
        case kVK_Escape where plain:
            stop()
        case kVK_Delete where plain, kVK_ForwardDelete where plain:
            stop()
            _ = onChange(nil)
        default:
            let candidate = NativeKeyCombo(event: event)
            if let reason = candidate.problem {
                // Keep recording so the user can try again.
                NSSound.beep()
                problem = reason
                return
            }
            stop()
            problem = onChange(candidate)
        }
    }
}
#endif

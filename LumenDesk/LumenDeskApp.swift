import SwiftUI
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#endif

@main
struct LumenDeskApp: App {
    // Fork: the objects live in AppServices so App Intents (Shortcuts, Siri, Control Center)
    // reach the same LightManager as the windows.
    @StateObject private var manager: LightManager
    #if os(macOS)
    @StateObject private var goveeBluetooth: GoveeBluetoothController
    @StateObject private var goveeScenes: GoveeSceneStore
    @StateObject private var networkGate: NativeNetworkGate
    @StateObject private var shortcuts: NativeShortcutCenter
    @StateObject private var macEvents: NativeMacEvents
    #endif

    init() {
        let services = AppServices.shared
        _manager = StateObject(wrappedValue: services.manager)
        #if os(macOS)
        _goveeBluetooth = StateObject(wrappedValue: services.goveeBluetooth)
        _goveeScenes = StateObject(wrappedValue: services.goveeScenes)
        _networkGate = StateObject(wrappedValue: services.networkGate)
        _shortcuts = StateObject(wrappedValue: services.shortcuts)
        _macEvents = StateObject(wrappedValue: services.macEvents)
        if !AppServices.isRunningTests { services.controlsBridge.start() }
        #endif
    }

    var body: some Scene {
        #if os(macOS)
        macScenes
        #else
        WindowGroup {
            RootView()
                .environmentObject(manager)
                .preferredColorScheme(.dark)
        }
        #endif
    }

    #if os(macOS)
    // Fork: native macOS window, settings and menu bar extra (see NativeMac/).
    // The original views remain for iOS.
    @SceneBuilder private var macScenes: some Scene {
        Window("LumenDesk", id: NativeScenes.mainWindowID) {
            NativeMainWindow()
                .environmentObject(manager)
                .environmentObject(goveeBluetooth)
                .environmentObject(goveeScenes)
                .environmentObject(networkGate)
                .environmentObject(shortcuts)
                .environmentObject(macEvents)
                .frame(minWidth: 640, minHeight: 460)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Scan for Lights") {
                    manager.start(discover: false)
                    manager.scan()
                }
                    .keyboardShortcut("r", modifiers: .command)
                Button("Toggle All Lights") {
                    manager.setAllPower(on: !manager.devices.contains(where: { $0.isOn }))
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                Divider()
                Button("Cancel Queued Light Commands") { manager.cancelQueuedCommands() }
                    .keyboardShortcut(".", modifiers: .command)
                    .disabled(manager.commandPendingIDs.isEmpty)
            }
            CommandGroup(after: .importExport) {
                Button("Export Configuration\u{2026}") { exportConfiguration() }
                Button("Import Configuration\u{2026}") { importConfiguration() }
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Undo Light Change") { manager.undo() }
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(!manager.canUndo)
                Button("Redo Light Change") { manager.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(!manager.canRedo)
            }
        }

        Settings {
            NativeSettingsView()
                .environmentObject(manager)
                .environmentObject(goveeBluetooth)
                .environmentObject(networkGate)
                .environmentObject(shortcuts)
                .environmentObject(macEvents)
        }

        MenuBarExtra {
            NativeMenuBarView()
                .environmentObject(manager)
                .environmentObject(goveeBluetooth)
                .environmentObject(goveeScenes)
                .environmentObject(networkGate)
                .environmentObject(shortcuts)
                .environmentObject(macEvents)
        } label: {
            NativeMenuBarLabel(manager: manager)
                // The label exists from launch, even when the main window doesn't open (a login
                // launch with the window closed last time), so shortcuts and automations work.
                .onAppear {
                    AppServices.shared.startNative()
                }
        }
        .menuBarExtraStyle(.window)
    }

    // MARK: - Export / Import

    private func exportConfiguration() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "LumenDesk-Configuration.json"
        panel.title = "Export LumenDesk Configuration"
        // Dismissing the panel is a cancel, not a failure.
        guard panel.runModal() == .OK, let url = panel.url else { return }
        manager.exportConfiguration(to: url)
    }

    private func importConfiguration() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Import LumenDesk Configuration"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let data = try? Data(contentsOf: url) else {
            manager.publishError("Import failed \u{2014} could not read \u{201C}\(url.lastPathComponent)\u{201D}.")
            return
        }

        manager.requestConfigurationImport(data, fileName: url.lastPathComponent)
    }
    #endif
}

// MARK: - Root

/// Decides between the first-run guided setup and the main app. The
/// `hasOnboarded` flag is persisted, so the walkthrough only ever appears on a
/// fresh install (or after the user resets it).
struct RootView: View {
    @EnvironmentObject var manager: LightManager
    @AppStorage("LumenDesk.hasOnboarded.v1") private var hasOnboarded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if hasOnboarded {
                LumenDeskShellView()
                    .transition(.opacity)
            } else {
                OnboardingView(onFinish: { hasOnboarded = true })
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: hasOnboarded)
        .managedActionConfirmations(manager)
        .onAppear { startReturningWorkspace() }
        .onChange(of: hasOnboarded) { _ in startReturningWorkspace() }
        .onChange(of: manager.isDemoMode) { _ in startReturningWorkspace() }
    }

    private func startReturningWorkspace() {
        // First-run network access begins only after Prepare explains it.
        // Exploring the demo does not initialize live discovery services.
        if hasOnboarded { manager.start() }
    }
}

private struct ConfirmationPresentationModifier: ViewModifier {
    @ObservedObject var coordinator: ConfirmationCoordinator

    func body(content: Content) -> some View {
        content.alert(item: Binding(
            get: { coordinator.pendingRequest },
            set: { if $0 == nil { coordinator.dismissPendingRequest() } }
        )) { request in
            Alert(
                title: Text(request.title),
                message: Text(request.message),
                primaryButton: request.isDestructive
                    ? .destructive(Text(request.confirmTitle), action: coordinator.confirmPendingRequest)
                    : .default(Text(request.confirmTitle), action: coordinator.confirmPendingRequest),
                secondaryButton: .cancel(coordinator.cancelPendingRequest)
            )
        }
    }
}

extension View {
    func managedActionConfirmations(_ manager: LightManager) -> some View {
        modifier(ConfirmationPresentationModifier(coordinator: manager.confirmationCoordinator))
    }
}

#if os(macOS)
import AppKit
import ServiceManagement
import SwiftUI

/// Fork: opening LumenDesk at login, through `SMAppService.mainApp`.
///
/// The system owns the setting (the user can also change it in System Settings → General →
/// Login Items), so this reads the status back instead of storing a preference.
@MainActor
final class NativeLaunchAtLogin: ObservableObject {
    @Published private(set) var status: SMAppService.Status = SMAppService.mainApp.status
    @Published private(set) var failure: String?

    /// On, or waiting for the user to allow it in System Settings.
    var isOn: Bool { status == .enabled || status == .requiresApproval }

    func refresh() {
        status = SMAppService.mainApp.status
    }

    func setEnabled(_ enabled: Bool) {
        failure = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            failure = error.localizedDescription
        }
        refresh()
    }
}

/// Settings → General: the "Open at login" switch and what the system said about it.
struct NativeLaunchAtLoginSection: View {
    @StateObject private var launch = NativeLaunchAtLogin()

    var body: some View {
        Section {
            Toggle("Open LumenDesk at login", isOn: Binding(get: { launch.isOn }, set: launch.setEnabled))
        } footer: {
            footer
        }
        .onAppear { launch.refresh() }
        // The user may have changed it in System Settings meanwhile.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            launch.refresh()
        }
    }

    @ViewBuilder private var footer: some View {
        if let failure = launch.failure {
            Text("Couldn't change this: \(failure)")
        } else {
            switch launch.status {
            case .requiresApproval:
                HStack(alignment: .firstTextBaseline) {
                    Text("Allow LumenDesk in System Settings → General → Login Items.")
                    Spacer()
                    Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                }
            case .notFound:
                Text("macOS can't find this copy of LumenDesk. Install it in Applications (Tools/install.sh) and turn this on from there.")
            default:
                Text("Starts LumenDesk when you log in, so shortcuts and automations work right away.")
            }
        }
    }
}
#endif

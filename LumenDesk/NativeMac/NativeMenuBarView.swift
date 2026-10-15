#if os(macOS)
import SwiftUI

/// Menu bar icon: a template image, so macOS tints it for light/dark menu bars.
struct NativeMenuBarLabel: View {
    @ObservedObject var manager: LightManager

    var body: some View {
        Image(systemName: manager.devices.contains(where: { $0.isOn }) ? "lightbulb.2.fill" : "lightbulb.2")
    }
}

/// The menu bar panel: every light with a switch and brightness, plus the usual app items.
struct NativeMenuBarView: View {
    @EnvironmentObject private var manager: LightManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Lights").font(.headline)
                Spacer()
                if !manager.devices.isEmpty {
                    Toggle("All Lights", isOn: Binding(
                        get: { manager.devices.contains(where: { $0.isOn }) },
                        set: { manager.setAllPower(on: $0) }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            if manager.devices.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(manager.isScanning ? "Scanning…" : "No lights found").foregroundStyle(.secondary)
                    Button("Scan Now") { manager.scan() }.disabled(manager.isScanning)
                }
                .padding(14)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(manager.devices) { NativeMenuLightRow(device: $0) }
                    }
                    .padding(14)
                }
                .frame(maxHeight: 420)
                .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            VStack(alignment: .leading, spacing: 0) {
                NativeMenuItem("Open LumenDesk") {
                    openWindow(id: NativeScenes.mainWindowID)
                    NSApp.activate(ignoringOtherApps: true)
                }
                if #available(macOS 14.0, *) {
                    SettingsLink {
                        NativeMenuItemLabel(title: "Settings…")
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(TapGesture().onEnded { NSApp.activate(ignoringOtherApps: true) })
                } else {
                    NativeMenuItem("Settings…") {
                        NSApp.activate(ignoringOtherApps: true)
                        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    }
                }
                Divider().padding(.vertical, 4)
                NativeMenuItem("Quit LumenDesk") { NSApp.terminate(nil) }
            }
            .padding(6)
        }
        .frame(width: 300)
        .onAppear { manager.start() }
    }
}

private struct NativeMenuLightRow: View {
    @EnvironmentObject private var manager: LightManager
    @ObservedObject var device: LightDevice

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                NativeStatusIcon(device: device)
                VStack(alignment: .leading, spacing: 0) {
                    Text(device.label)
                    Text(nativeStatusText(device)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Power", isOn: Binding(get: { device.isOn }, set: { manager.setPower(device, on: $0) }))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
            }
            if device.isOn {
                NativeBrightnessSlider(device: device, showsLabel: false)
                    .controlSize(.small)
            }
        }
    }
}

/// A full-width menu-style button with the standard hover highlight.
private struct NativeMenuItem: View {
    let title: String
    let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            NativeMenuItemLabel(title: title)
        }
        .buttonStyle(.plain)
    }
}

/// Menu-item text with the accent-colour hover highlight.
private struct NativeMenuItemLabel: View {
    let title: String
    @State private var hovering = false

    var body: some View {
        Text(title)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(hovering ? Color.white : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(hovering ? Color.accentColor : Color.clear))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
    }
}
#endif

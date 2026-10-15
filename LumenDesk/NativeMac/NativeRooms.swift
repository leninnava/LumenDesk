#if os(macOS)
import SwiftUI

/// "Room ▸" submenu for moving a light between rooms.
struct NativeRoomMenu: View {
    @EnvironmentObject private var manager: LightManager
    @ObservedObject var device: LightDevice

    var body: some View {
        Menu("Room") {
            Picker("Room", selection: Binding(
                get: { manager.room(forLightID: device.id)?.id },
                set: { manager.assign(lightID: device.id, toRoom: $0) }
            )) {
                Text("No Room").tag(UUID?.none)
                ForEach(manager.rooms) { room in
                    Text(room.name).tag(UUID?.some(room.id))
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
    }
}

/// Asks for a name; used for creating and renaming rooms and renaming lights.
struct NativeRoomNameAlert: ViewModifier {
    @Binding var isPresented: Bool
    let title: String
    var placeholder = "Room name"
    let initialName: String
    let confirmTitle: String
    let onConfirm: (String) -> Void
    @State private var name = ""

    func body(content: Content) -> some View {
        content
            .alert(title, isPresented: $isPresented) {
                TextField(placeholder, text: $name)
                Button(confirmTitle) {
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { onConfirm(trimmed) }
                }
                Button("Cancel", role: .cancel) {}
            }
            .onChange(of: isPresented) { presented in
                if presented { name = initialName }
            }
    }
}

extension View {
    func nativeRoomNameAlert(isPresented: Binding<Bool>, title: String, placeholder: String = "Room name",
                             initialName: String = "", confirmTitle: String,
                             onConfirm: @escaping (String) -> Void) -> some View {
        modifier(NativeRoomNameAlert(isPresented: isPresented, title: title, placeholder: placeholder,
                                     initialName: initialName, confirmTitle: confirmTitle, onConfirm: onConfirm))
    }

    /// "Rename…" prompt for a light.
    func nativeRenameLightAlert(_ device: LightDevice?, isPresented: Binding<Bool>,
                                manager: LightManager) -> some View {
        nativeRoomNameAlert(isPresented: isPresented, title: "Rename Light", placeholder: "Light name",
                            initialName: device?.label ?? "", confirmTitle: "Rename") { name in
            if let device { manager.setCustomName(device.id, name: name) }
        }
    }
}
#endif

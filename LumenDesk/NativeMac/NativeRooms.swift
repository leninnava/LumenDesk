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

/// Asks for a room name; used for both creating and renaming.
struct NativeRoomNameAlert: ViewModifier {
    @Binding var isPresented: Bool
    let title: String
    let initialName: String
    let confirmTitle: String
    let onConfirm: (String) -> Void
    @State private var name = ""

    func body(content: Content) -> some View {
        content
            .alert(title, isPresented: $isPresented) {
                TextField("Room name", text: $name)
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
    func nativeRoomNameAlert(isPresented: Binding<Bool>, title: String, initialName: String = "",
                             confirmTitle: String, onConfirm: @escaping (String) -> Void) -> some View {
        modifier(NativeRoomNameAlert(isPresented: isPresented, title: title, initialName: initialName,
                                     confirmTitle: confirmTitle, onConfirm: onConfirm))
    }
}
#endif

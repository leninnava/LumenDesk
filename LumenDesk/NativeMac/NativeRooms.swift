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
                set: { manager.nativeAssign(device, toRoom: $0) }
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

extension LightManager {
    /// What kind of fixture a model is, for automatic names.
    static func nativeFixtureKind(sku: String?) -> String {
        switch sku {
        case "H6008": return "Bulb"
        case "H60A1": return "Ceiling Light"
        default: return "Light"
        }
    }

    /// Moves a light to a room and, unless the user named it, names it after the room:
    /// "Living Room Bulb", then "Living Room Bulb 2", and so on.
    func nativeAssign(_ device: LightDevice, toRoom roomID: UUID?) {
        assign(lightID: device.id, toRoom: roomID)
        guard device.customName == nil, let room = rooms.first(where: { $0.id == roomID }) else { return }
        let base = "\(room.name) \(Self.nativeFixtureKind(sku: device.sku))"
        let taken = Set(devices.filter { $0.id != device.id }.map(\.label))
        var name = base
        var number = 2
        while taken.contains(name) {
            name = "\(base) \(number)"
            number += 1
        }
        setCustomName(device.id, name: name)
    }
}
#endif

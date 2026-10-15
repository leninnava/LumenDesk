#if os(macOS)
import AppKit
import Carbon.HIToolbox
import Combine
import Foundation

// Fork: system-wide keyboard shortcuts (Settings → Shortcuts).
//
// Registered with Carbon's `RegisterEventHotKey`, which works in the App Sandbox and needs no
// Accessibility permission: the system delivers only the registered combinations, never other
// keystrokes. A combination another app registered first can't be taken; the row says so.

/// Tags LumenDesk's hot keys ('LDsk').
private let nativeHotKeySignature: OSType = 0x4C_44_73_6B

/// A key plus modifiers, as recorded in Settings.
struct NativeKeyCombo: Codable, Equatable {
    /// Virtual key code (`kVK_…`), independent of the keyboard layout.
    let keyCode: UInt32
    /// `NSEvent.ModifierFlags` raw value, limited to ⌘ ⌥ ⌃ ⇧.
    let modifiers: UInt
    /// What the key shows, captured when recorded ("L", "F5", "←").
    let key: String

    static let relevantModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    init(keyCode: UInt32, modifiers: NSEvent.ModifierFlags, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection(Self.relevantModifiers).rawValue
        self.key = key
    }

    init(event: NSEvent) {
        let code = UInt32(event.keyCode)
        let typed = event.characters(byApplyingModifiers: [])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.init(keyCode: code, modifiers: event.modifierFlags,
                  key: Self.specialKeyNames[Int(code)] ?? (typed.isEmpty ? "Key \(code)" : typed.uppercased()))
    }

    var modifierFlags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    /// "⌃⌥⌘L", in the order macOS menus use.
    var title: String {
        let flags = modifierFlags
        var text = ""
        if flags.contains(.control) { text += "⌃" }
        if flags.contains(.option) { text += "⌥" }
        if flags.contains(.shift) { text += "⇧" }
        if flags.contains(.command) { text += "⌘" }
        return text + key
    }

    /// Same physical keys, whatever was displayed when each was recorded.
    func sameKeys(as other: NativeKeyCombo) -> Bool {
        keyCode == other.keyCode && modifiers == other.modifiers
    }

    /// Why this combination can't be a global shortcut, or nil if it can.
    var problem: String? {
        let flags = modifierFlags
        if flags.isDisjoint(with: [.command, .option, .control]) {
            return "Use ⌘, ⌥ or ⌃ so the shortcut doesn't take a key from other apps."
        }
        if flags == .command {
            return "⌘ alone would take this shortcut from every app. Add ⌥, ⌃ or ⇧."
        }
        return nil
    }

    /// Carbon's modifier mask for `RegisterEventHotKey`.
    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var mask: UInt32 = 0
        if flags.contains(.command) { mask |= UInt32(cmdKey) }
        if flags.contains(.option) { mask |= UInt32(optionKey) }
        if flags.contains(.control) { mask |= UInt32(controlKey) }
        if flags.contains(.shift) { mask |= UInt32(shiftKey) }
        return mask
    }

    private static let specialKeyNames: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Home: "↖", kVK_End: "↘",
        kVK_PageUp: "⇞", kVK_PageDown: "⇟", kVK_LeftArrow: "←", kVK_RightArrow: "→",
        kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_ANSI_KeypadEnter: "⌤",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17",
        kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
    ]
}

/// What a shortcut does.
enum NativeShortcutAction: Hashable {
    case toggleAll
    case brightnessUp
    case brightnessDown
    case toggleRoom(UUID)

    static let general: [NativeShortcutAction] = [.toggleAll, .brightnessUp, .brightnessDown]

    var storageKey: String {
        switch self {
        case .toggleAll: return "toggleAll"
        case .brightnessUp: return "brightnessUp"
        case .brightnessDown: return "brightnessDown"
        case .toggleRoom(let id): return "room:\(id.uuidString)"
        }
    }

    init?(storageKey: String) {
        switch storageKey {
        case "toggleAll": self = .toggleAll
        case "brightnessUp": self = .brightnessUp
        case "brightnessDown": self = .brightnessDown
        default:
            guard storageKey.hasPrefix("room:"),
                  let id = UUID(uuidString: String(storageKey.dropFirst("room:".count))) else { return nil }
            self = .toggleRoom(id)
        }
    }
}

/// Shortcuts in UserDefaults, as JSON keyed by `NativeShortcutAction.storageKey`.
enum NativeShortcutStore {
    static let key = "Native.shortcuts.v1"

    static func load(from defaults: UserDefaults = .standard) -> [NativeShortcutAction: NativeKeyCombo] {
        guard let data = defaults.data(forKey: key),
              let stored = try? JSONDecoder().decode([String: NativeKeyCombo].self, from: data) else { return [:] }
        var shortcuts: [NativeShortcutAction: NativeKeyCombo] = [:]
        for (key, combo) in stored {
            // Skip entries a newer or hand-edited copy wrote that this one can't use.
            guard let action = NativeShortcutAction(storageKey: key), combo.problem == nil else { continue }
            shortcuts[action] = combo
        }
        return shortcuts
    }

    static func save(_ shortcuts: [NativeShortcutAction: NativeKeyCombo], to defaults: UserDefaults = .standard) {
        let stored = Dictionary(uniqueKeysWithValues: shortcuts.map { ($0.key.storageKey, $0.value) })
        if let data = try? JSONEncoder().encode(stored) { defaults.set(data, forKey: key) }
    }
}

/// Owns the registered hot keys and runs their actions on the light manager.
@MainActor
final class NativeShortcutCenter: ObservableObject {
    @Published private(set) var shortcuts: [NativeShortcutAction: NativeKeyCombo]
    /// Shortcuts the system refused, usually because another app registered them first.
    @Published private(set) var unavailable: Set<NativeShortcutAction> = []

    /// Brightness step for the brighten and dim shortcuts.
    static let brightnessStep = 0.1

    private weak var manager: LightManager?
    private var registered: [UInt32: (action: NativeShortcutAction, ref: EventHotKeyRef)] = [:]
    private var nextID: UInt32 = 1
    private var handler: EventHandlerRef?
    private var roomsObserver: AnyCancellable?
    private var paused = false
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        shortcuts = NativeShortcutStore.load(from: defaults)
    }

    /// Starts listening and registers the saved shortcuts. Safe to call more than once.
    func attach(_ manager: LightManager) {
        guard self.manager == nil else { return }
        self.manager = manager
        installHandler()
        // Room shortcuts follow the rooms: a deleted room's shortcut stops holding its keys.
        roomsObserver = manager.$rooms
            .map { Set($0.map(\.id)) }
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { @MainActor in self?.registerAll() }
            }
        registerAll()
    }

    /// Sets or clears an action's shortcut. Returns why it was refused, if it was.
    @discardableResult
    func set(_ combo: NativeKeyCombo?, for action: NativeShortcutAction) -> String? {
        if let combo {
            if let problem = combo.problem { return problem }
            if let other = shortcuts.first(where: { $0.key != action && $0.value.sameKeys(as: combo) })?.key {
                return "\(combo.title) is already used for \(title(for: other))."
            }
        }
        shortcuts[action] = combo
        NativeShortcutStore.save(shortcuts, to: defaults)
        registerAll()
        return nil
    }

    /// While a shortcut is being recorded, the registered ones are released so their keys reach
    /// the recorder instead of running.
    func setPaused(_ paused: Bool) {
        guard self.paused != paused else { return }
        self.paused = paused
        registerAll()
    }

    func title(for action: NativeShortcutAction) -> String {
        switch action {
        case .toggleAll: return "Turn all lights on or off"
        case .brightnessUp: return "Brighten lights"
        case .brightnessDown: return "Dim lights"
        case .toggleRoom(let id):
            return manager?.rooms.first(where: { $0.id == id }).map { "Turn \($0.name) on or off" } ?? "a room"
        }
    }

    // MARK: Actions

    func perform(_ action: NativeShortcutAction) {
        guard let manager else { return }
        switch action {
        case .toggleAll:
            togglePower(manager.devices, manager: manager)
        case .toggleRoom(let id):
            guard let room = manager.rooms.first(where: { $0.id == id }) else { return }
            togglePower(manager.devices(in: room), manager: manager)
        case .brightnessUp:
            stepBrightness(by: Self.brightnessStep, manager: manager)
        case .brightnessDown:
            stepBrightness(by: -Self.brightnessStep, manager: manager)
        }
    }

    /// Any light on turns them all off; otherwise they all turn on. No confirmation, unlike the
    /// menu command: a shortcut is deliberate, and undo still works.
    private func togglePower(_ lights: [LightDevice], manager: LightManager) {
        guard !lights.isEmpty else { return }
        manager.setPower(deviceIDs: Set(lights.map(\.id)), on: !lights.contains(where: \.isOn))
    }

    /// Steps each light that's on from its own level. Lights that are off stay off.
    private func stepBrightness(by delta: Double, manager: LightManager) {
        let lit = manager.devices.filter(\.isOn)
        let groups = Dictionary(grouping: lit) { Self.stepped($0.brightness, by: delta) }
        for (value, lights) in groups {
            manager.setBrightness(deviceIDs: Set(lights.map(\.id)), value: value)
        }
    }

    /// `value + delta`, kept between 1% and 100% and rounded to whole percent.
    static func stepped(_ value: Double, by delta: Double) -> Double {
        let next = ((value + delta) * 100).rounded() / 100
        return min(1, max(0.01, next))
    }

    // MARK: Carbon

    private func installHandler() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard status == noErr, hotKeyID.signature == nativeHotKeySignature else {
                return OSStatus(eventNotHandledErr)
            }
            let center = Unmanaged<NativeShortcutCenter>.fromOpaque(context).takeUnretainedValue()
            let id = hotKeyID.id
            Task { @MainActor in center.fire(id) }
            return noErr
        }, 1, &spec, context, &handler)
    }

    private func fire(_ id: UInt32) {
        guard let action = registered[id]?.action else { return }
        perform(action)
    }

    private func registerAll() {
        for entry in registered.values { UnregisterEventHotKey(entry.ref) }
        registered = [:]
        var refused: Set<NativeShortcutAction> = []
        guard !paused, let manager else {
            unavailable = []
            return
        }
        let rooms = Set(manager.rooms.map(\.id))
        for (action, combo) in shortcuts {
            if case .toggleRoom(let id) = action, !rooms.contains(id) { continue }
            let id = nextID
            nextID &+= 1
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(combo.keyCode, NativeKeyCombo.carbonModifiers(combo.modifierFlags),
                                             EventHotKeyID(signature: nativeHotKeySignature, id: id),
                                             GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                registered[id] = (action, ref)
            } else {
                refused.insert(action)
            }
        }
        unavailable = refused
    }
}
#endif

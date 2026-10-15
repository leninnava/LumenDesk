import AppKit
import Carbon.HIToolbox
import XCTest
@testable import LumenDesk

/// Fork: global shortcut encoding, persistence and validation. Nothing here registers a hot key.
@MainActor
final class NativeShortcutsTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "NativeShortcutsTests"

    override func setUp() {
        super.setUp()
        UserDefaults().removePersistentDomain(forName: suite)
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private let lKey = NativeKeyCombo(keyCode: UInt32(kVK_ANSI_L), modifiers: [.control, .option, .command], key: "L")

    func testCarbonModifiersMapEachFlag() {
        XCTAssertEqual(NativeKeyCombo.carbonModifiers([.command]), UInt32(cmdKey))
        XCTAssertEqual(NativeKeyCombo.carbonModifiers([.option]), UInt32(optionKey))
        XCTAssertEqual(NativeKeyCombo.carbonModifiers([.control]), UInt32(controlKey))
        XCTAssertEqual(NativeKeyCombo.carbonModifiers([.shift]), UInt32(shiftKey))
        XCTAssertEqual(NativeKeyCombo.carbonModifiers([.control, .option, .command, .shift]),
                       UInt32(cmdKey | optionKey | controlKey | shiftKey))
        XCTAssertEqual(NativeKeyCombo.carbonModifiers([]), 0)
    }

    func testComboKeepsOnlyShortcutModifiers() {
        let combo = NativeKeyCombo(keyCode: 1, modifiers: [.command, .option, .capsLock, .function, .numericPad], key: "S")
        XCTAssertEqual(combo.modifierFlags, [.command, .option])
    }

    func testTitleUsesMenuOrder() {
        XCTAssertEqual(lKey.title, "⌃⌥⌘L")
        XCTAssertEqual(NativeKeyCombo(keyCode: UInt32(kVK_F5), modifiers: [.command, .shift, .option], key: "F5").title,
                       "⌥⇧⌘F5")
    }

    func testRejectsCombosThatWouldTakeKeysFromOtherApps() {
        XCTAssertNotNil(NativeKeyCombo(keyCode: 1, modifiers: [], key: "S").problem)
        XCTAssertNotNil(NativeKeyCombo(keyCode: 1, modifiers: [.shift], key: "S").problem)
        XCTAssertNotNil(NativeKeyCombo(keyCode: 1, modifiers: [.command], key: "S").problem)
        XCTAssertNil(NativeKeyCombo(keyCode: 1, modifiers: [.command, .shift], key: "S").problem)
        XCTAssertNil(NativeKeyCombo(keyCode: 1, modifiers: [.option], key: "S").problem)
        XCTAssertNil(NativeKeyCombo(keyCode: 1, modifiers: [.control], key: "S").problem)
    }

    func testActionStorageKeysRoundTrip() {
        let room = UUID()
        for action in [NativeShortcutAction.toggleAll, .brightnessUp, .brightnessDown, .toggleRoom(room)] {
            XCTAssertEqual(NativeShortcutAction(storageKey: action.storageKey), action)
        }
        XCTAssertNil(NativeShortcutAction(storageKey: "room:not-a-uuid"))
        XCTAssertNil(NativeShortcutAction(storageKey: "somethingElse"))
    }

    func testStoreRoundTripsShortcuts() {
        let room = UUID()
        let up = NativeKeyCombo(keyCode: UInt32(kVK_UpArrow), modifiers: [.control, .option], key: "↑")
        NativeShortcutStore.save([.toggleAll: lKey, .toggleRoom(room): up], to: defaults)
        XCTAssertEqual(NativeShortcutStore.load(from: defaults), [.toggleAll: lKey, .toggleRoom(room): up])
    }

    func testStoreSkipsUnusableEntries() throws {
        let bad = NativeKeyCombo(keyCode: 1, modifiers: [.shift], key: "S")
        let data = try JSONEncoder().encode(["toggleAll": lKey, "future": lKey, "brightnessUp": bad])
        defaults.set(data, forKey: NativeShortcutStore.key)
        XCTAssertEqual(NativeShortcutStore.load(from: defaults), [.toggleAll: lKey])

        defaults.set(Data("not json".utf8), forKey: NativeShortcutStore.key)
        XCTAssertEqual(NativeShortcutStore.load(from: defaults), [:])
    }

    func testCenterPersistsAndRefusesDuplicatesAndBadCombos() {
        let center = NativeShortcutCenter(defaults: defaults)
        XCTAssertNil(center.set(lKey, for: .toggleAll))
        // The same keys recorded under another layout still count as taken.
        let sameKeys = NativeKeyCombo(keyCode: lKey.keyCode, modifiers: lKey.modifierFlags, key: "Ł")
        XCTAssertNotNil(center.set(sameKeys, for: .brightnessUp))
        XCTAssertNotNil(center.set(NativeKeyCombo(keyCode: 2, modifiers: [.shift], key: "D"), for: .brightnessUp))
        // Re-recording an action's own shortcut is fine.
        XCTAssertNil(center.set(sameKeys, for: .toggleAll))

        XCTAssertEqual(NativeShortcutCenter(defaults: defaults).shortcuts, [.toggleAll: sameKeys])
        center.set(nil, for: .toggleAll)
        XCTAssertEqual(NativeShortcutCenter(defaults: defaults).shortcuts, [:])
    }

    func testBrightnessStepsStayInRange() {
        XCTAssertEqual(NativeShortcutCenter.stepped(0.5, by: 0.1), 0.6, accuracy: 0.0001)
        XCTAssertEqual(NativeShortcutCenter.stepped(0.95, by: 0.1), 1)
        XCTAssertEqual(NativeShortcutCenter.stepped(0.05, by: -0.1), 0.01)
        XCTAssertEqual(NativeShortcutCenter.stepped(0.333, by: -0.1), 0.23, accuracy: 0.0001)
    }
}

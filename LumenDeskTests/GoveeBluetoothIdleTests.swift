import XCTest
@testable import LumenDesk

/// Fork: closing idle Bluetooth links and reopening them on the next command. Runs without
/// Bluetooth hardware: the controller gets no central, so links never get past "searching".
final class GoveeBluetoothIdleTests: XCTestCase {
    private let advert = "ihoment_H6008_1A2B"

    private func makeController() -> GoveeBluetoothController {
        let controller = GoveeBluetoothController(makeCentral: { _ in nil })
        controller.isPaired = { [advert] in $0 == advert }
        return controller
    }

    private func bluetoothLight() -> LightDevice {
        LightDevice(id: "govee:ble:\(advert)", brand: .govee, backendID: "ble:\(advert)",
                    name: "H6008 1A2B", address: "Bluetooth", sku: "H6008")
    }

    func testLANLinksCloseAfterTheirTimeout() {
        XCTAssertFalse(GoveeBluetoothController.shouldRelease(
            bluetoothOnly: false, idleFor: 299, lanTimeout: 300, bluetoothOnlyTimeout: nil))
        XCTAssertTrue(GoveeBluetoothController.shouldRelease(
            bluetoothOnly: false, idleFor: 301, lanTimeout: 300, bluetoothOnlyTimeout: nil))
        // The Bluetooth-only setting doesn't change LAN lights.
        XCTAssertFalse(GoveeBluetoothController.shouldRelease(
            bluetoothOnly: false, idleFor: 120, lanTimeout: 300, bluetoothOnlyTimeout: 60))
    }

    func testBluetoothOnlyLinksStayOpenUnlessReleaseIsOn() {
        XCTAssertFalse(GoveeBluetoothController.shouldRelease(
            bluetoothOnly: true, idleFor: 86_400, lanTimeout: 300, bluetoothOnlyTimeout: nil))
        XCTAssertFalse(GoveeBluetoothController.shouldRelease(
            bluetoothOnly: true, idleFor: 59, lanTimeout: 300, bluetoothOnlyTimeout: 60))
        XCTAssertTrue(GoveeBluetoothController.shouldRelease(
            bluetoothOnly: true, idleFor: 61, lanTimeout: 300, bluetoothOnlyTimeout: 60))
    }

    func testIdleSettingMapsToTimeout() {
        XCTAssertNil(NativeBluetoothIdleRelease.timeout(enabled: false, minutes: 5))
        XCTAssertEqual(NativeBluetoothIdleRelease.timeout(enabled: true, minutes: 1), 60)
        XCTAssertEqual(NativeBluetoothIdleRelease.timeout(enabled: true, minutes: 15), 900)
        // An unexpected stored value falls back to the default.
        XCTAssertEqual(NativeBluetoothIdleRelease.timeout(enabled: true, minutes: 7), 300)
    }

    func testReleasedLinkReopensOnTheNextCommandButNotOnPolling() {
        let controller = makeController()
        let light = bluetoothLight()
        controller.bluetoothOnlyIdleTimeout = 60

        controller.setPower(light, on: true)
        XCTAssertTrue(controller.hasLink(light))

        controller.tick(now: Date().addingTimeInterval(30))
        XCTAssertTrue(controller.hasLink(light), "not idle long enough")

        controller.tick(now: Date().addingTimeInterval(120))
        XCTAssertFalse(controller.hasLink(light))
        XCTAssertTrue(controller.isReleased(light))
        XCTAssertEqual(controller.states[light.id], .released)

        controller.refresh(light)
        XCTAssertFalse(controller.hasLink(light), "polling must not reopen a released link")

        controller.setPower(light, on: false)
        XCTAssertTrue(controller.hasLink(light), "a command reopens the link")
        XCTAssertEqual(controller.states[light.id], .searching)
        // Still counted as released until the light answers, so it isn't marked offline meanwhile.
        XCTAssertTrue(controller.isReleased(light))
    }

    func testBluetoothOnlyLinksStayOpenByDefault() {
        let controller = makeController()
        let light = bluetoothLight()
        controller.setPower(light, on: true)
        controller.tick(now: Date().addingTimeInterval(86_400))
        XCTAssertTrue(controller.hasLink(light))
        XCTAssertFalse(controller.isReleased(light))
    }

    func testTurningReleaseOffReconnectsReleasedLights() {
        let controller = makeController()
        let light = bluetoothLight()
        controller.bluetoothOnlyIdleTimeout = 60
        controller.setPower(light, on: true)
        controller.tick(now: Date().addingTimeInterval(120))
        XCTAssertFalse(controller.hasLink(light))

        controller.bluetoothOnlyIdleTimeout = nil
        XCTAssertTrue(controller.hasLink(light))
    }

    func testForgettingAReleasedLightClearsIt() {
        let controller = makeController()
        let light = bluetoothLight()
        controller.bluetoothOnlyIdleTimeout = 60
        controller.setPower(light, on: true)
        controller.tick(now: Date().addingTimeInterval(120))
        controller.forget(light)
        XCTAssertFalse(controller.isReleased(light))
        XCTAssertNil(controller.states[light.id])
    }

    func testUnpairedLightsGetNoLink() {
        let controller = GoveeBluetoothController(makeCentral: { _ in nil })
        let light = bluetoothLight()
        controller.setPower(light, on: true)
        XCTAssertFalse(controller.hasLink(light))
    }
}

import XCTest
@testable import LumenDesk

/// Fork: Govee Bluetooth frames, session cipher, advert matching and scene parsing. The segment
/// and scene vectors are frames a real H60A1 accepted (see FORK.md).
final class GoveeBluetoothTests: XCTestCase {
    private func hex(_ frame: [UInt8]) -> String {
        frame.map { String(format: "%02x", $0) }.joined(separator: " ")
    }

    func testSegmentColorFrameMatchesHardwareVerifiedFrame() {
        let frame = GoveeBluetoothProtocol.segmentColorFrame((255, 0, 0), segments: [0])
        XCTAssertEqual(hex(frame), "33 05 15 01 ff 00 00 00 00 00 00 00 01 00 00 00 00 00 00 dc")
    }

    func testSegmentMaskCoversTheThirteenRingSegments() {
        let frame = GoveeBluetoothProtocol.segmentColorFrame((255, 255, 255), segments: Array(0..<13))
        XCTAssertEqual(Array(frame[12...14]), [0xFF, 0x1F, 0x00])
    }

    func testSceneFramesMatchGovee2mqttVector() throws {
        // Forest, code 212, from govee2mqtt's ble.rs snapshot test.
        let param = try XCTUnwrap(Data(base64Encoded: "AyYAAQAKAgH/GQG0CgoCyBQF//8AAP//////AP//lP8AFAGWAAAAACMAAg8FAgH/FAH7AAAB+goEBP8AtP8AR///4/8AAAAAAAAAABoAAAABAgH/BQHIFBQC7hQBAP8AAAAAAAAAAA=="))
        XCTAssertEqual(GoveeBluetoothProtocol.sceneFrames(code: 212, param: param).map(hex), [
            "a3 00 01 07 02 03 26 00 01 00 0a 02 01 ff 19 01 b4 0a 0a d9",
            "a3 01 02 c8 14 05 ff ff 00 00 ff ff ff ff ff 00 ff ff 94 12",
            "a3 02 ff 00 14 01 96 00 00 00 00 23 00 02 0f 05 02 01 ff 0a",
            "a3 03 14 01 fb 00 00 01 fa 0a 04 04 ff 00 b4 ff 00 47 ff b3",
            "a3 04 ff e3 ff 00 00 00 00 00 00 00 00 1a 00 00 00 01 02 5d",
            "a3 05 01 ff 05 01 c8 14 14 02 ee 14 01 00 ff 00 00 00 00 92",
            "a3 ff 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 5c",
            "33 05 04 d4 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 e6",
        ])
    }

    func testRainbowSceneMatchesFramesTheH60A1Accepted() throws {
        let param = try XCTUnwrap(Data(base64Encoded: "ASkAAAAFAgH//wLMHh4DfxQG/wAA/38A//8AAP8AAAD/iwD/EAD0AAD8AA=="))
        XCTAssertEqual(GoveeBluetoothProtocol.sceneFrames(code: 11071, param: param).map(hex), [
            "a3 00 01 03 02 01 29 00 00 00 05 02 01 ff ff 02 cc 1e 1e 43",
            "a3 01 03 7f 14 06 ff 00 00 ff 7f 00 ff ff 00 00 ff 00 00 4c",
            "a3 ff 00 ff 8b 00 ff 10 00 f4 00 00 fc 00 00 00 00 00 00 cf",
            "33 05 04 3f 2b 00 00 00 00 00 00 00 00 00 00 00 00 00 00 26",
        ])
    }

    func testSceneWithoutParameterIsOnlyTheSelectFrame() {
        XCTAssertEqual(GoveeBluetoothProtocol.sceneFrames(code: 1, param: Data()).map(hex),
                       ["33 05 04 01 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 33"])
    }

    func testSessionCipherRoundTrips() throws {
        let cipher = try XCTUnwrap(GoveeSessionCipher(key: Array(0..<16)))
        let frame = GoveeBluetoothProtocol.segmentColorFrame((1, 2, 3), segments: [4])
        let wire = try XCTUnwrap(cipher.encrypt(frame))
        XCTAssertNotEqual(wire, frame)
        XCTAssertEqual(cipher.decrypt(wire), frame)
    }

    func testSessionCipherRejectsWrongSizes() {
        XCTAssertNil(GoveeSessionCipher(key: Array(repeating: 0, count: 15)))
        XCTAssertNil(GoveeSessionCipher.handshake.encrypt([0x33, 0x01]))
    }

    func testParsesAdvertNames() {
        XCTAssertEqual(GoveeBluetoothProtocol.parseName("GVH60A1ABCE")?.sku, "H60A1")
        XCTAssertEqual(GoveeBluetoothProtocol.parseName("GVH60A1ABCE")?.suffix, 0xABCE)
        XCTAssertEqual(GoveeBluetoothProtocol.parseName("ihoment_H6008_3C4D")?.sku, "H6008")
        XCTAssertEqual(GoveeBluetoothProtocol.parseName("Govee_H6008_3C4D")?.suffix, 0x3C4D)
        XCTAssertNil(GoveeBluetoothProtocol.parseName("Living Room TV"))
    }

    func testMatchesAdvertToLANLightByModelAndAddress() {
        let id = "0E:60:12:34:56:78:AB:CD"
        // Bluetooth MAC is the Wi-Fi MAC plus one.
        XCTAssertTrue(GoveeBluetoothProtocol.advertName("GVH60A1ABCE", matchesSKU: "H60A1", deviceID: id))
        XCTAssertTrue(GoveeBluetoothProtocol.advertName("GVH60A1ABCD", matchesSKU: "H60A1", deviceID: id))
        XCTAssertFalse(GoveeBluetoothProtocol.advertName("GVH60A1ABCF", matchesSKU: "H60A1", deviceID: id))
        XCTAssertFalse(GoveeBluetoothProtocol.advertName("GVH60A4ABCE", matchesSKU: "H60A1", deviceID: id))
        XCTAssertFalse(GoveeBluetoothProtocol.advertName("GVH60A1ABCE", matchesSKU: nil, deviceID: id))
    }

    func testParsesStatusReplies() {
        XCTAssertEqual(GoveeBluetoothProtocol.parse([0xAA, 0x01, 0x01]), .power(true))
        XCTAssertEqual(GoveeBluetoothProtocol.parse([0xAA, 0x04, 0x64]), .brightness(100))
        XCTAssertEqual(GoveeBluetoothProtocol.parse([0xAA, 0x05, 0x04, 0x3F, 0x2B]), .mode([0x04, 0x3F, 0x2B]))
        XCTAssertNil(GoveeBluetoothProtocol.parse([0x33, 0x01, 0x01]))
    }

    func testParsesSceneLibraryAndSkipsEmptyEntries() throws {
        let json = #"{"data":{"categories":[{"categoryName":"Natural","scenes":[{"sceneName":"Sunrise","lightEffects":[{"sceneCode":1,"scenceParam":""}]},{"sceneName":"Broken","lightEffects":[]},{"sceneName":"Forest","lightEffects":[{"sceneCode":11063,"scenceParam":"AQI="}]}]}]}}"#
        let scenes = try GoveeSceneStore.parse(Data(json.utf8))
        XCTAssertEqual(scenes.map(\.name), ["Sunrise", "Forest"])
        XCTAssertEqual(scenes.last?.param, Data([1, 2]))
        XCTAssertEqual(scenes.last?.category, "Natural")
    }

    // MARK: Bluetooth-only lights (H6008)

    func testBasicControlFramesMatchHardwareVerifiedH6008Frames() {
        XCTAssertEqual(hex(GoveeBluetoothProtocol.colorFrame(r: 255, g: 0, b: 0)),
                       "33 05 0d ff 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 c4")
        XCTAssertEqual(hex(GoveeBluetoothProtocol.brightnessFrame(percent: 30)),
                       "33 04 1e 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 29")
        XCTAssertEqual(Array(GoveeBluetoothProtocol.powerFrame(on: false).prefix(3)), [0x33, 0x01, 0x00])
    }

    func testBrightnessIsClampedToOneThroughHundred() {
        XCTAssertEqual(GoveeBluetoothProtocol.brightnessFrame(percent: 0)[2], 1)
        XCTAssertEqual(GoveeBluetoothProtocol.brightnessFrame(percent: 255)[2], 100)
    }

    func testWhiteFrameCarriesKelvinBigEndian() {
        let frame = GoveeBluetoothProtocol.whiteFrame(kelvin: 2700)
        XCTAssertEqual(Array(frame[0...2]), [0x33, 0x05, 0x0D])
        XCTAssertEqual(Array(frame[6...7]), [0x0A, 0x8C])
        XCTAssertEqual(frame[3], 255)  // warm white: full red
        XCTAssertLessThan(frame[5], frame[4])  // less blue than green
    }

    func testReadsColourStateFromModeReply() throws {
        let white = try XCTUnwrap(GoveeBluetoothProtocol.colorState(fromMode: [0x0D, 0xFF, 0xA9, 0x57, 0x0A, 0x8C]))
        XCTAssertEqual(white.kelvin, 2700)
        let red = try XCTUnwrap(GoveeBluetoothProtocol.colorState(fromMode: [0x0D, 0xFF, 0x00, 0x00, 0x00, 0x00]))
        XCTAssertEqual(red.r, 255)
        XCTAssertEqual(red.kelvin, 0)
        XCTAssertNil(GoveeBluetoothProtocol.colorState(fromMode: [0x15, 0x01, 0x00]))
    }

    // MARK: Security regressions (see FORK.md)

    func testUntrustedAddressTextIsNotUsedAsALogFormat() {
        // Before the fix this crashed the process: the text went to NSLog as its format string.
        XCTAssertEqual(GoveeClient.commandAddress(source: "192.168.0.36", reported: "%@%@%@%s%s%n"), "192.168.0.36")
    }

    func testOnlyMACStyleGoveeDeviceIDsAreAccepted() {
        XCTAssertTrue(GoveeProtocol.isValidDeviceID("0E:60:12:34:56:78:AB:CD"))
        XCTAssertTrue(GoveeProtocol.isValidDeviceID("d0:c9:07:b8:ca:ce"))
        XCTAssertFalse(GoveeProtocol.isValidDeviceID("ble:ihoment_H6008_1A2B"))
        XCTAssertFalse(GoveeProtocol.isValidDeviceID("%@"))
        XCTAssertFalse(GoveeProtocol.isValidDeviceID("0E:60:12:34:56:78:AB:CD:00"))
    }

    func testLANLightCannotPassAsBluetoothOnly() {
        let spoofed = LightDevice(id: "govee:ble:x", brand: .govee, backendID: "ble:ihoment_H6008_1A2B",
                                  name: "x", address: "192.168.0.50", sku: "H6008")
        XCTAssertFalse(spoofed.isBluetoothOnly)
        let paired = LightDevice(id: "govee:ble:ihoment_H6008_1A2B", brand: .govee,
                                 backendID: "ble:ihoment_H6008_1A2B", name: "x", address: "Bluetooth", sku: "H6008")
        XCTAssertTrue(paired.isBluetoothOnly)
    }

    func testControllerRefusesBluetoothOnlyLightsThatWereNotPaired() {
        let bluetooth = GoveeBluetoothController()
        bluetooth.isPaired = { _ in false }
        let light = LightDevice(id: "govee:ble:ihoment_H6008_1A2B", brand: .govee,
                                backendID: "ble:ihoment_H6008_1A2B", name: "x", address: "Bluetooth", sku: "H6008")
        bluetooth.send([GoveeBluetoothProtocol.powerFrame(on: true)], to: light)
        bluetooth.prepare(light)
        XCTAssertNil(bluetooth.states[light.id])
    }

    func testOversizedSceneParametersAreRejected() throws {
        XCTAssertEqual(GoveeBluetoothProtocol.sceneFrames(code: 1, param: Data(count: 4400)), [])
        let big = Data(count: GoveeBluetoothProtocol.maxSceneParamBytes + 1).base64EncodedString()
        let json = #"{"data":{"categories":[{"categoryName":"X","scenes":[{"sceneName":"Huge","lightEffects":[{"sceneCode":5,"scenceParam":"\#(big)"}]},{"sceneName":"Fine","lightEffects":[{"sceneCode":6,"scenceParam":"AQI="}]}]}]}}"#
        XCTAssertEqual(try GoveeSceneStore.parse(Data(json.utf8)).map(\.name), ["Fine"])
    }

    func testAdvertNamesMustUseGoveeNamingSchemes() {
        XCTAssertNil(GoveeBluetoothProtocol.parseName("ANYTHINGH60A1ABCE"))
        XCTAssertNil(GoveeBluetoothProtocol.parseName("evil_H6008_1A2B"))
        XCTAssertEqual(GoveeBluetoothProtocol.parseName("ihoment_H6008_1A2B")?.suffix, 0x1A2B)
        XCTAssertEqual(GoveeBluetoothProtocol.parseName("GVH60A1ABCE")?.sku, "H60A1")
    }
}

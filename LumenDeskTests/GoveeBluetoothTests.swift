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
        XCTAssertEqual(GoveeBluetoothProtocol.parseName("GVH60A1CACF")?.sku, "H60A1")
        XCTAssertEqual(GoveeBluetoothProtocol.parseName("GVH60A1CACF")?.suffix, 0xCACF)
        XCTAssertEqual(GoveeBluetoothProtocol.parseName("ihoment_H6008_F821")?.sku, "H6008")
        XCTAssertEqual(GoveeBluetoothProtocol.parseName("Govee_H6008_F821")?.suffix, 0xF821)
        XCTAssertNil(GoveeBluetoothProtocol.parseName("Living Room TV"))
    }

    func testMatchesAdvertToLANLightByModelAndAddress() {
        let id = "0E:60:D0:C9:07:B8:CA:CE"
        // Bluetooth MAC is the Wi-Fi MAC plus one.
        XCTAssertTrue(GoveeBluetoothProtocol.advertName("GVH60A1CACF", matchesSKU: "H60A1", deviceID: id))
        XCTAssertTrue(GoveeBluetoothProtocol.advertName("GVH60A1CACE", matchesSKU: "H60A1", deviceID: id))
        XCTAssertFalse(GoveeBluetoothProtocol.advertName("GVH60A1CAD0", matchesSKU: "H60A1", deviceID: id))
        XCTAssertFalse(GoveeBluetoothProtocol.advertName("GVH60A4CACF", matchesSKU: "H60A1", deviceID: id))
        XCTAssertFalse(GoveeBluetoothProtocol.advertName("GVH60A1CACF", matchesSKU: nil, deviceID: id))
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
}

/*
Copyright NetFoundry Inc.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

https://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/
import XCTest
@testable import CZiti

class ZitiIdentityTests: XCTestCase {

    func testCodableRoundTrip() throws {
        let id = ZitiIdentity(id: "test-id-123", ztAPIs: ["https://ctrl1:1280", "https://ctrl2:1280"],
                              name: "test-identity", certs: "-----BEGIN CERTIFICATE-----\ntest\n-----END CERTIFICATE-----",
                              ca: "-----BEGIN CERTIFICATE-----\nca\n-----END CERTIFICATE-----")
        id.startDisabled = true

        let data = try JSONEncoder().encode(id)
        let decoded = try JSONDecoder().decode(ZitiIdentity.self, from: data)

        XCTAssertEqual(decoded.id, "test-id-123")
        XCTAssertEqual(decoded.ztAPIs, ["https://ctrl1:1280", "https://ctrl2:1280"])
        XCTAssertEqual(decoded.name, "test-identity")
        XCTAssertEqual(decoded.certs, "-----BEGIN CERTIFICATE-----\ntest\n-----END CERTIFICATE-----")
        XCTAssertEqual(decoded.ca, "-----BEGIN CERTIFICATE-----\nca\n-----END CERTIFICATE-----")
        XCTAssertEqual(decoded.startDisabled, true)
    }

    func testZtAPIDerivedFromZtAPIs() {
        let id = ZitiIdentity(id: "x", ztAPIs: ["https://first:1280", "https://second:1280"])
        XCTAssertEqual(id.ztAPI, "https://first:1280")
    }

    func testZtAPIEmptyWhenZtAPIsEmpty() {
        let id = ZitiIdentity(id: "x", ztAPIs: [])
        XCTAssertEqual(id.ztAPI, "")
    }

    func testOptionalFieldsDefaultToNil() throws {
        let json = """
        {"id":"minimal","ztAPI":"https://ctrl:1280"}
        """
        let decoded = try JSONDecoder().decode(ZitiIdentity.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(decoded.id, "minimal")
        XCTAssertNil(decoded.name)
        XCTAssertNil(decoded.certs)
        XCTAssertNil(decoded.ca)
        XCTAssertNil(decoded.ztAPIs)
    }

    func testSaveAndLoadFromFile() throws {
        let id = ZitiIdentity(id: "file-test", ztAPIs: ["https://ctrl:1280"], name: "saved")
        let tmpFile = NSTemporaryDirectory() + "ZitiIdentityTest-\(UUID().uuidString).zid"
        defer { try? FileManager.default.removeItem(atPath: tmpFile) }

        XCTAssertTrue(id.save(tmpFile))

        let data = try Data(contentsOf: URL(fileURLWithPath: tmpFile))
        let loaded = try JSONDecoder().decode(ZitiIdentity.self, from: data)
        XCTAssertEqual(loaded.id, "file-test")
        XCTAssertEqual(loaded.name, "saved")
    }

    func testStartDisabledRoundTripFalse() throws {
        let id = ZitiIdentity(id: "x", ztAPIs: ["https://ctrl:1280"])
        id.startDisabled = false
        let data = try JSONEncoder().encode(id)
        let decoded = try JSONDecoder().decode(ZitiIdentity.self, from: data)
        XCTAssertEqual(decoded.startDisabled, false)
    }

    func testStartDisabledRoundTripTrue() throws {
        let id = ZitiIdentity(id: "x", ztAPIs: ["https://ctrl:1280"])
        id.startDisabled = true
        let data = try JSONEncoder().encode(id)
        let decoded = try JSONDecoder().decode(ZitiIdentity.self, from: data)
        XCTAssertEqual(decoded.startDisabled, true)
    }
}

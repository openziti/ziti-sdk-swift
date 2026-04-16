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

class ZitiTunnelServerConfigV1Tests: XCTestCase {

    func testDecodeProtocolMapsToProto() throws {
        let json = """
        {"hostname":"backend.internal","port":5432,"protocol":"tcp"}
        """
        let cfg = try JSONDecoder().decode(ZitiTunnelServerConfigV1.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(cfg.hostname, "backend.internal")
        XCTAssertEqual(cfg.port, 5432)
        XCTAssertEqual(cfg.proto, "tcp")
    }

    func testEncodeUsesProtocolKey() throws {
        let json = """
        {"hostname":"h","port":1,"protocol":"udp"}
        """
        let cfg = try JSONDecoder().decode(ZitiTunnelServerConfigV1.self, from: json.data(using: .utf8)!)
        let encoded = try JSONEncoder().encode(cfg)
        let dict = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        XCTAssertEqual(dict["protocol"] as? String, "udp")
        XCTAssertNil(dict["proto"])
    }

    func testDecodeMissingProtocolFails() {
        let json = """
        {"hostname":"h","port":1}
        """
        XCTAssertThrowsError(try JSONDecoder().decode(ZitiTunnelServerConfigV1.self, from: json.data(using: .utf8)!))
    }
}

class ZitiTunnelClientConfigV1Tests: XCTestCase {

    func testDecode() throws {
        let json = """
        {"hostname":"backend.internal","port":5000}
        """
        let cfg = try JSONDecoder().decode(ZitiTunnelClientConfigV1.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(cfg.hostname, "backend.internal")
        XCTAssertEqual(cfg.port, 5000)
    }

    func testRoundTrip() throws {
        let json = """
        {"hostname":"h","port":80}
        """
        let original = try JSONDecoder().decode(ZitiTunnelClientConfigV1.self, from: json.data(using: .utf8)!)
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ZitiTunnelClientConfigV1.self, from: encoded)
        XCTAssertEqual(decoded.hostname, "h")
        XCTAssertEqual(decoded.port, 80)
    }
}

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

class ZitiInterceptConfigV1Tests: XCTestCase {

    func testDecodeFullConfig() throws {
        let json = """
        {
            "protocols": ["tcp", "udp"],
            "addresses": ["192.168.1.0/24", "10.0.0.0/8", "example.com"],
            "portRanges": [
                {"low": 80, "high": 443},
                {"low": 8000, "high": 9000}
            ],
            "dialOptions": {
                "identity": "my-id",
                "connectTimeoutSeconds": 30
            },
            "sourceIp": "192.168.1.1"
        }
        """
        let cfg = try JSONDecoder().decode(ZitiInterceptConfigV1.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(cfg.protocols, ["tcp", "udp"])
        XCTAssertEqual(cfg.addresses, ["192.168.1.0/24", "10.0.0.0/8", "example.com"])
        XCTAssertEqual(cfg.portRanges.count, 2)
        XCTAssertEqual(cfg.portRanges[0].low, 80)
        XCTAssertEqual(cfg.portRanges[0].high, 443)
        XCTAssertEqual(cfg.portRanges[1].low, 8000)
        XCTAssertEqual(cfg.portRanges[1].high, 9000)
        XCTAssertEqual(cfg.dialOptions?.identity, "my-id")
        XCTAssertEqual(cfg.dialOptions?.connectTimeoutSeconds, 30)
        XCTAssertEqual(cfg.sourceIp, "192.168.1.1")
    }

    func testDecodeWithoutOptionals() throws {
        let json = """
        {
            "protocols": ["tcp"],
            "addresses": ["10.0.0.1"],
            "portRanges": [{"low": 80, "high": 80}]
        }
        """
        let cfg = try JSONDecoder().decode(ZitiInterceptConfigV1.self, from: json.data(using: .utf8)!)
        XCTAssertNil(cfg.dialOptions)
        XCTAssertNil(cfg.sourceIp)
    }

    func testDecodeEmptyPortRanges() throws {
        let json = """
        {
            "protocols": ["tcp"],
            "addresses": ["x.y.z"],
            "portRanges": []
        }
        """
        let cfg = try JSONDecoder().decode(ZitiInterceptConfigV1.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(cfg.portRanges.count, 0)
    }

    func testCodableRoundTrip() throws {
        let json = """
        {"protocols":["tcp"],"addresses":["10.0.0.1"],"portRanges":[{"low":80,"high":443}],"sourceIp":"1.2.3.4"}
        """
        let original = try JSONDecoder().decode(ZitiInterceptConfigV1.self, from: json.data(using: .utf8)!)
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ZitiInterceptConfigV1.self, from: encoded)

        XCTAssertEqual(decoded.protocols, original.protocols)
        XCTAssertEqual(decoded.addresses, original.addresses)
        XCTAssertEqual(decoded.portRanges.count, original.portRanges.count)
        XCTAssertEqual(decoded.sourceIp, original.sourceIp)
    }

    func testDialOptionsAllNil() throws {
        let json = """
        {
            "protocols": ["tcp"],
            "addresses": ["x"],
            "portRanges": [{"low": 1, "high": 1}],
            "dialOptions": {}
        }
        """
        let cfg = try JSONDecoder().decode(ZitiInterceptConfigV1.self, from: json.data(using: .utf8)!)
        XCTAssertNotNil(cfg.dialOptions)
        XCTAssertNil(cfg.dialOptions?.identity)
        XCTAssertNil(cfg.dialOptions?.connectTimeoutSeconds)
    }
}

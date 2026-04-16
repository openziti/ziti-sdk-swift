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

class ZitiHostConfigV1Tests: XCTestCase {

    func testDecodeProtocolMapsToProto() throws {
        // "protocol" is a reserved word in Swift, so the type maps the JSON "protocol" key to "proto"
        let json = """
        {"protocol":"tcp","address":"10.0.0.1","port":8080}
        """
        let cfg = try JSONDecoder().decode(ZitiHostConfigV1.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(cfg.proto, "tcp")
        XCTAssertEqual(cfg.address, "10.0.0.1")
        XCTAssertEqual(cfg.port, 8080)
    }

    func testEncodeUsesProtocolKey() throws {
        let json = """
        {"protocol":"udp","address":"0.0.0.0","port":53}
        """
        let cfg = try JSONDecoder().decode(ZitiHostConfigV1.self, from: json.data(using: .utf8)!)
        let encoded = try JSONEncoder().encode(cfg)
        let dict = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        XCTAssertEqual(dict["protocol"] as? String, "udp")
        XCTAssertNil(dict["proto"])
    }

    func testDecodeFullConfig() throws {
        let json = """
        {
            "protocol": "tcp",
            "forwardProtocol": true,
            "allowedProtocols": ["tcp", "udp"],
            "address": "0.0.0.0",
            "forwardAddress": false,
            "allowedAddresses": ["192.168.1.0/24"],
            "allowedSourceAddresses": ["10.0.0.0/8"],
            "port": 8080,
            "forwardPort": true,
            "allowedPortRanges": [{"low": 80, "high": 443}],
            "listenOptions": {
                "connectTimeoutSeconds": 30,
                "maxConnections": 1000,
                "identity": "host-id",
                "bindUsingEdgeIdentity": true
            }
        }
        """
        let cfg = try JSONDecoder().decode(ZitiHostConfigV1.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(cfg.proto, "tcp")
        XCTAssertEqual(cfg.forwardProtocol, true)
        XCTAssertEqual(cfg.allowedProtocols, ["tcp", "udp"])
        XCTAssertEqual(cfg.address, "0.0.0.0")
        XCTAssertEqual(cfg.forwardAddress, false)
        XCTAssertEqual(cfg.allowedAddresses, ["192.168.1.0/24"])
        XCTAssertEqual(cfg.allowedSourceAddresses, ["10.0.0.0/8"])
        XCTAssertEqual(cfg.port, 8080)
        XCTAssertEqual(cfg.forwardPort, true)
        XCTAssertEqual(cfg.allowedPortRanges?.count, 1)
        XCTAssertEqual(cfg.allowedPortRanges?[0].low, 80)
        XCTAssertEqual(cfg.allowedPortRanges?[0].high, 443)
        XCTAssertEqual(cfg.listenOptions?.connectTimeoutSeconds, 30)
        XCTAssertEqual(cfg.listenOptions?.maxConnections, 1000)
        XCTAssertEqual(cfg.listenOptions?.identity, "host-id")
        XCTAssertEqual(cfg.listenOptions?.bindUsingEdgeIdentity, true)
    }

    func testDecodeMinimalConfig() throws {
        let json = """
        {}
        """
        let cfg = try JSONDecoder().decode(ZitiHostConfigV1.self, from: json.data(using: .utf8)!)
        XCTAssertNil(cfg.proto)
        XCTAssertNil(cfg.address)
        XCTAssertNil(cfg.port)
        XCTAssertNil(cfg.listenOptions)
    }

    func testCodableRoundTrip() throws {
        let json = """
        {"protocol":"tcp","address":"1.2.3.4","port":8080,"listenOptions":{"identity":"x","maxConnections":10}}
        """
        let original = try JSONDecoder().decode(ZitiHostConfigV1.self, from: json.data(using: .utf8)!)
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ZitiHostConfigV1.self, from: encoded)

        XCTAssertEqual(decoded.proto, original.proto)
        XCTAssertEqual(decoded.address, original.address)
        XCTAssertEqual(decoded.port, original.port)
        XCTAssertEqual(decoded.listenOptions?.identity, original.listenOptions?.identity)
        XCTAssertEqual(decoded.listenOptions?.maxConnections, original.listenOptions?.maxConnections)
    }
}

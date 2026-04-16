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

class ZitiUrlClientConfigV1Tests: XCTestCase {

    func testGetPortExplicit() throws {
        let json = """
        {"scheme":"https","hostname":"api.example.com","port":8443}
        """
        let cfg = try JSONDecoder().decode(ZitiUrlClientConfigV1.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(cfg.getPort(), 8443)
    }

    func testGetPortDefaultsHttps() throws {
        let json = """
        {"scheme":"https","hostname":"api.example.com"}
        """
        let cfg = try JSONDecoder().decode(ZitiUrlClientConfigV1.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(cfg.getPort(), 443)
    }

    func testGetPortDefaultsHttp() throws {
        let json = """
        {"scheme":"http","hostname":"api.example.com"}
        """
        let cfg = try JSONDecoder().decode(ZitiUrlClientConfigV1.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(cfg.getPort(), 80)
    }

    func testGetPortUnknownSchemeDefaultsTo80() throws {
        let json = """
        {"scheme":"ws","hostname":"api.example.com"}
        """
        let cfg = try JSONDecoder().decode(ZitiUrlClientConfigV1.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(cfg.getPort(), 80)
    }

    func testDecodeWithHeaders() throws {
        let json = """
        {"scheme":"https","hostname":"api.example.com","headers":{"X-Auth":"token","X-Trace":"1"}}
        """
        let cfg = try JSONDecoder().decode(ZitiUrlClientConfigV1.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(cfg.headers?["X-Auth"], "token")
        XCTAssertEqual(cfg.headers?["X-Trace"], "1")
    }

    func testDecodeWithoutHeaders() throws {
        let json = """
        {"scheme":"https","hostname":"api.example.com"}
        """
        let cfg = try JSONDecoder().decode(ZitiUrlClientConfigV1.self, from: json.data(using: .utf8)!)
        XCTAssertNil(cfg.headers)
    }
}

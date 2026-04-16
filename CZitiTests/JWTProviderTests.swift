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

class JWTProviderTests: XCTestCase {

    func testDecodeWithAllFields() throws {
        let json = """
        {"name":"My Provider","issuer":"https://auth.example.com","canCertEnroll":true,"canTokenEnroll":false}
        """
        let provider = try JSONDecoder().decode(JWTProvider.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(provider.name, "My Provider")
        XCTAssertEqual(provider.issuer, "https://auth.example.com")
        XCTAssertTrue(provider.canCertEnroll)
        XCTAssertFalse(provider.canTokenEnroll)
    }

    func testDecodeMissingBooleanKeysDefaultToFalse() throws {
        // This is the bug scenario from old .zid files that lacked these keys
        let json = """
        {"name":"Legacy Provider","issuer":"https://old.example.com"}
        """
        let provider = try JSONDecoder().decode(JWTProvider.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(provider.name, "Legacy Provider")
        XCTAssertEqual(provider.issuer, "https://old.example.com")
        XCTAssertFalse(provider.canCertEnroll)
        XCTAssertFalse(provider.canTokenEnroll)
    }

    func testDecodeNullBooleanValues() throws {
        let json = """
        {"name":"Null Bools","issuer":"https://x.com","canCertEnroll":null,"canTokenEnroll":null}
        """
        let provider = try JSONDecoder().decode(JWTProvider.self, from: json.data(using: .utf8)!)

        XCTAssertFalse(provider.canCertEnroll)
        XCTAssertFalse(provider.canTokenEnroll)
    }

    func testDecodeBothBooleansTrue() throws {
        let json = """
        {"name":"Full","issuer":"https://x.com","canCertEnroll":true,"canTokenEnroll":true}
        """
        let provider = try JSONDecoder().decode(JWTProvider.self, from: json.data(using: .utf8)!)

        XCTAssertTrue(provider.canCertEnroll)
        XCTAssertTrue(provider.canTokenEnroll)
    }

    func testCodableRoundTrip() throws {
        let json = """
        {"name":"Round Trip","issuer":"https://rt.example.com","canCertEnroll":true,"canTokenEnroll":false}
        """
        let original = try JSONDecoder().decode(JWTProvider.self, from: json.data(using: .utf8)!)

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(JWTProvider.self, from: encoded)

        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.issuer, original.issuer)
        XCTAssertEqual(decoded.canCertEnroll, original.canCertEnroll)
        XCTAssertEqual(decoded.canTokenEnroll, original.canTokenEnroll)
    }

    func testDecodePreservesExactValues() throws {
        // Verify encoding includes the boolean fields (so round-trip from new .zid files works)
        let json = """
        {"name":"P","issuer":"I","canCertEnroll":false,"canTokenEnroll":true}
        """
        let provider = try JSONDecoder().decode(JWTProvider.self, from: json.data(using: .utf8)!)
        let encoded = try JSONEncoder().encode(provider)
        let reDecoded = try JSONDecoder().decode(JWTProvider.self, from: encoded)

        XCTAssertFalse(reDecoded.canCertEnroll)
        XCTAssertTrue(reDecoded.canTokenEnroll)
    }
}

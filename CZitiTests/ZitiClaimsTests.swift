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

class ZitiClaimsTests: XCTestCase {

    func testCodableRoundTrip() throws {
        let claims = ZitiClaims("subject-123", "https://issuer.example.com", "ott", 1700000000, "jwt-id-456")

        let data = try JSONEncoder().encode(claims)
        let decoded = try JSONDecoder().decode(ZitiClaims.self, from: data)

        XCTAssertEqual(decoded.sub, "subject-123")
        XCTAssertEqual(decoded.iss, "https://issuer.example.com")
        XCTAssertEqual(decoded.em, "ott")
        XCTAssertEqual(decoded.exp, 1700000000)
        XCTAssertEqual(decoded.jti, "jwt-id-456")
    }

    func testAllOptionalsNil() throws {
        let claims = ZitiClaims("sub-only", nil, nil, nil, nil)

        let data = try JSONEncoder().encode(claims)
        let decoded = try JSONDecoder().decode(ZitiClaims.self, from: data)

        XCTAssertEqual(decoded.sub, "sub-only")
        XCTAssertNil(decoded.iss)
        XCTAssertNil(decoded.em)
        XCTAssertNil(decoded.exp)
        XCTAssertNil(decoded.jti)
    }

    func testDecodeFromJSON() throws {
        let json = """
        {"sub":"identity-abc","iss":"https://ctrl:1280","em":"ott","exp":9999999999,"jti":"jti-xyz"}
        """
        let decoded = try JSONDecoder().decode(ZitiClaims.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(decoded.sub, "identity-abc")
        XCTAssertEqual(decoded.iss, "https://ctrl:1280")
        XCTAssertEqual(decoded.em, "ott")
        XCTAssertEqual(decoded.exp, 9999999999)
        XCTAssertEqual(decoded.jti, "jti-xyz")
    }

    func testDecodeMinimalJSON() throws {
        let json = """
        {"sub":"just-sub"}
        """
        let decoded = try JSONDecoder().decode(ZitiClaims.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(decoded.sub, "just-sub")
        XCTAssertNil(decoded.iss)
        XCTAssertNil(decoded.em)
    }
}

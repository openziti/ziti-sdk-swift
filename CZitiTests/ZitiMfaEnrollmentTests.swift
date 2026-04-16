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

class ZitiMfaEnrollmentTests: XCTestCase {

    func testDecodeFull() throws {
        let json = """
        {
            "isVerified": true,
            "provisioningUrl": "otpauth://totp/user@example.com?secret=ABC",
            "recoveryCodes": ["code-1", "code-2", "code-3"]
        }
        """
        let mfa = try JSONDecoder().decode(ZitiMfaEnrollment.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(mfa.isVerified, true)
        XCTAssertEqual(mfa.provisioningUrl, "otpauth://totp/user@example.com?secret=ABC")
        XCTAssertEqual(mfa.recoveryCodes, ["code-1", "code-2", "code-3"])
    }

    func testDecodeAllOptionalsMissing() throws {
        let json = """
        {}
        """
        let mfa = try JSONDecoder().decode(ZitiMfaEnrollment.self, from: json.data(using: .utf8)!)
        XCTAssertNil(mfa.isVerified)
        XCTAssertNil(mfa.provisioningUrl)
        XCTAssertNil(mfa.recoveryCodes)
    }

    func testDecodeEmptyRecoveryCodes() throws {
        let json = """
        {"isVerified":false,"recoveryCodes":[]}
        """
        let mfa = try JSONDecoder().decode(ZitiMfaEnrollment.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(mfa.isVerified, false)
        XCTAssertEqual(mfa.recoveryCodes, [])
    }

    func testRoundTrip() throws {
        let json = """
        {"isVerified":true,"provisioningUrl":"x","recoveryCodes":["a","b"]}
        """
        let original = try JSONDecoder().decode(ZitiMfaEnrollment.self, from: json.data(using: .utf8)!)
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ZitiMfaEnrollment.self, from: encoded)
        XCTAssertEqual(decoded.isVerified, original.isVerified)
        XCTAssertEqual(decoded.provisioningUrl, original.provisioningUrl)
        XCTAssertEqual(decoded.recoveryCodes, original.recoveryCodes)
    }
}

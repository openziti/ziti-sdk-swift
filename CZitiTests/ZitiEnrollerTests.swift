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

class ZitiEnrollerTests: XCTestCase {

    // MARK: - base64UrlDecode

    func testBase64UrlDecodeStandardInput() {
        let enroller = ZitiEnroller("/dev/null")
        // "Hello, World!" in base64url (no padding)
        let result = enroller.base64UrlDecode("SGVsbG8sIFdvcmxkIQ")
        XCTAssertNotNil(result)
        XCTAssertEqual(String(data: result!, encoding: .utf8), "Hello, World!")
    }

    func testBase64UrlDecodeWithUrlSafeChars() {
        let enroller = ZitiEnroller("/dev/null")
        // base64url uses - instead of + and _ instead of /
        // Standard base64: "ab+c/d==" -> base64url: "ab-c_d"
        let standard = Data([0x69, 0xBF, 0x9C, 0xFD])
        let encoded = standard.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let result = enroller.base64UrlDecode(encoded)
        XCTAssertEqual(result, standard)
    }

    func testBase64UrlDecodeWithPadding() {
        let enroller = ZitiEnroller("/dev/null")
        // "A" base64 = "QQ==" -> base64url = "QQ"
        let result = enroller.base64UrlDecode("QQ")
        XCTAssertNotNil(result)
        XCTAssertEqual(String(data: result!, encoding: .utf8), "A")
    }

    func testBase64UrlDecodeEmptyString() {
        let enroller = ZitiEnroller("/dev/null")
        let result = enroller.base64UrlDecode("")
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.count, 0)
    }

    func testBase64UrlDecodeJWTPayload() {
        let enroller = ZitiEnroller("/dev/null")
        // A realistic JWT payload
        let payload = """
        {"sub":"abc-123","iss":"https://ctrl:1280","em":"ott","exp":1700000000}
        """
        let encoded = payload.data(using: .utf8)!.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let result = enroller.base64UrlDecode(encoded)
        XCTAssertNotNil(result)
        XCTAssertEqual(String(data: result!, encoding: .utf8), payload)
    }

    // MARK: - getClaims

    func testGetClaimsFromValidJWT() throws {
        // Build a minimal JWT (header.payload.signature)
        let header = Data("{}".utf8).base64EncodedString()
        let payload = Data("""
        {"sub":"identity-xyz","iss":"https://ctrl:1280","em":"ott","exp":1700000000,"jti":"jwt-001"}
        """.utf8).base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
        let jwt = "\(header).\(payload).fakesig"

        let tmpFile = NSTemporaryDirectory() + "test-jwt-\(UUID().uuidString).jwt"
        defer { try? FileManager.default.removeItem(atPath: tmpFile) }
        try jwt.write(toFile: tmpFile, atomically: true, encoding: .utf8)

        let enroller = ZitiEnroller(tmpFile)
        let claims = enroller.getClaims()

        XCTAssertNotNil(claims)
        XCTAssertEqual(claims?.sub, "identity-xyz")
        XCTAssertEqual(claims?.iss, "https://ctrl:1280")
        XCTAssertEqual(claims?.em, "ott")
        XCTAssertEqual(claims?.exp, 1700000000)
        XCTAssertEqual(claims?.jti, "jwt-001")
    }

    func testGetClaimsReturnsNilForMissingFile() {
        let enroller = ZitiEnroller("/nonexistent/path/to/file.jwt")
        XCTAssertNil(enroller.getClaims())
    }

    func testGetClaimsReturnsNilForInvalidJWT() throws {
        let tmpFile = NSTemporaryDirectory() + "bad-jwt-\(UUID().uuidString).jwt"
        defer { try? FileManager.default.removeItem(atPath: tmpFile) }
        try "not-a-jwt".write(toFile: tmpFile, atomically: true, encoding: .utf8)

        let enroller = ZitiEnroller(tmpFile)
        XCTAssertNil(enroller.getClaims())
    }

    func testGetClaimsReturnsNilWhenSubMissing() throws {
        let header = Data("{}".utf8).base64EncodedString()
        let payload = Data("""
        {"iss":"https://ctrl:1280","em":"ott"}
        """.utf8).base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
        let jwt = "\(header).\(payload).fakesig"

        let tmpFile = NSTemporaryDirectory() + "nosub-jwt-\(UUID().uuidString).jwt"
        defer { try? FileManager.default.removeItem(atPath: tmpFile) }
        try jwt.write(toFile: tmpFile, atomically: true, encoding: .utf8)

        let enroller = ZitiEnroller(tmpFile)
        XCTAssertNil(enroller.getClaims())
    }

    func testGetClaimsWithNetworkJWT() throws {
        let header = Data("{}".utf8).base64EncodedString()
        let payload = Data("""
        {"sub":"net-id","iss":"https://ctrl:1280","em":"ca"}
        """.utf8).base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
        let jwt = "\(header).\(payload).sig"

        let tmpFile = NSTemporaryDirectory() + "net-jwt-\(UUID().uuidString).jwt"
        defer { try? FileManager.default.removeItem(atPath: tmpFile) }
        try jwt.write(toFile: tmpFile, atomically: true, encoding: .utf8)

        let enroller = ZitiEnroller(tmpFile)
        let claims = enroller.getClaims()
        XCTAssertNotNil(claims)
        XCTAssertEqual(claims?.em, "ca")
    }

    // MARK: - EnrollmentResponse Codable

    func testEnrollmentResponseCodableRoundTrip() throws {
        let id = ZitiEnroller.EnrollmentResponse.Identity(
            cert: "-----BEGIN CERTIFICATE-----\ncert\n-----END CERTIFICATE-----",
            key: "-----BEGIN EC PRIVATE KEY-----\nkey\n-----END EC PRIVATE KEY-----",
            ca: "-----BEGIN CERTIFICATE-----\nca\n-----END CERTIFICATE-----"
        )
        let resp = ZitiEnroller.EnrollmentResponse(
            ztAPIs: ["https://ctrl1:1280", "https://ctrl2:1280"],
            id: id
        )

        let data = try JSONEncoder().encode(resp)
        let decoded = try JSONDecoder().decode(ZitiEnroller.EnrollmentResponse.self, from: data)

        XCTAssertEqual(decoded.ztAPIs, ["https://ctrl1:1280", "https://ctrl2:1280"])
        XCTAssertEqual(decoded.id.cert, resp.id.cert)
        XCTAssertEqual(decoded.id.key, resp.id.key)
        XCTAssertEqual(decoded.id.ca, resp.id.ca)
    }

    func testEnrollmentResponseWithNilIdentityFields() throws {
        let id = ZitiEnroller.EnrollmentResponse.Identity(cert: nil, key: nil, ca: nil)
        let resp = ZitiEnroller.EnrollmentResponse(ztAPIs: ["https://ctrl:1280"], id: id)

        let data = try JSONEncoder().encode(resp)
        let decoded = try JSONDecoder().decode(ZitiEnroller.EnrollmentResponse.self, from: data)

        XCTAssertEqual(decoded.ztAPIs, ["https://ctrl:1280"])
        XCTAssertNil(decoded.id.cert)
        XCTAssertNil(decoded.id.key)
        XCTAssertNil(decoded.id.ca)
    }
}

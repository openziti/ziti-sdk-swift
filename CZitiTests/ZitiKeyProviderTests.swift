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

class ZitiKeyProviderTests: XCTestCase {

#if CZITI_TEST_INSECURE_KEYS
    func testSelectedProvider() {
        XCTAssertTrue(zitiKeyProvider is InsecureTestKeyProvider)
    }

    func testCreateKeyReturnsRSAPrivateKeyPEM() throws {
        let pem = try XCTUnwrap(InsecureTestKeyProvider().createKey(tag: "x"))
        XCTAssertTrue(pem.hasPrefix("-----BEGIN RSA PRIVATE KEY-----\n"))
        XCTAssertTrue(pem.hasSuffix("\n-----END RSA PRIVATE KEY-----\n"))

        let der = ZitiKeychain(tag: "x").convertToDER(pem)
        let attrs: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPrivate]
        let key = try XCTUnwrap(SecKeyCreateWithData(der as CFData, attrs as CFDictionary, nil))
        let keyAttrs = try XCTUnwrap(SecKeyCopyAttributes(key) as? [CFString: Any])
        XCTAssertEqual(keyAttrs[kSecAttrKeySizeInBits] as? Int, ZitiKeychain.keySize)
    }

    func testCreateKeyIsEphemeral() throws {
        let p = InsecureTestKeyProvider()
        let a = try XCTUnwrap(p.createKey(tag: "same-tag"))
        let b = try XCTUnwrap(p.createKey(tag: "same-tag"))
        XCTAssertNotEqual(a, b)
    }

    func testRoundTripThroughIdentity() throws {
        let p = InsecureTestKeyProvider()
        let pem = try XCTUnwrap(p.createKey(tag: "tmp-uuid"))
        let id = ZitiIdentity(id: "real-id", ztAPIs: ["https://ctrl:1280"])
        p.persistKey(pem, in: id)
        XCTAssertEqual(id.key, pem)

        // survives .zid encode/decode, and is what run() would hand to the C SDK
        let decoded = try JSONDecoder().decode(ZitiIdentity.self, from: JSONEncoder().encode(id))
        XCTAssertEqual(p.keyString(for: decoded), pem)
    }

    func testCopyKeyToFinalIdentity() throws {
        // enrollToCert: key is persisted in the temporary identity, then carried to the final one
        let p = InsecureTestKeyProvider()
        let pem = try XCTUnwrap(p.createKey(tag: "tmp-uuid"))
        let tmpId = ZitiIdentity(id: "tmp-uuid", ztAPIs: ["https://ctrl:1280"])
        p.persistKey(pem, in: tmpId)

        let finalId = ZitiIdentity(id: "real-id", ztAPIs: ["https://ctrl:1280"])
        p.copyKey(from: tmpId, to: finalId)
        XCTAssertEqual(finalId.key, pem)
        XCTAssertEqual(p.keyString(for: finalId), pem)
    }

    func testKeychainOperationsAreNoOps() {
        let p = InsecureTestKeyProvider()
        XCTAssertNil(p.deleteKey(tag: "x", silent: false))
        XCTAssertNil(p.retagKey(from: "x", to: "y"))
        XCTAssertNil(p.storeCertificate(tag: "x", pem: "not a cert"))
        XCTAssertNil(p.deleteCertificate(tag: "x", silent: false))
    }
#else
    func testSelectedProvider() {
        XCTAssertTrue(zitiKeyProvider is KeychainKeyProvider)
    }
#endif
}

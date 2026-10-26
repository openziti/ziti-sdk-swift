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

/// Pins the exact keychain attributes used to create, find, update and delete keys and certificates.
/// Existing installs locate their keys with these queries, so any change here can orphan stored keys.
class ZitiKeychainTests: XCTestCase {

    let tag = "test-tag-1234"
    var atag: Data { return tag.data(using: .utf8)! }

    // self-signed P-256 certificate, CN=czititest
    let certPEM = """
    -----BEGIN CERTIFICATE-----
    MIIBGjCBwAIJAJdJHkUV1zekMAoGCCqGSM49BAMCMBQxEjAQBgNVBAMMCWN6aXRp
    dGVzdDAgFw0yNjEwMjIxOTQ3NTFaGA8yMTI2MDkyODE5NDc1MVowFDESMBAGA1UE
    AwwJY3ppdGl0ZXN0MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEpyMnMNFxtelv
    h/U4TiSMkReG0mLw7WU+ofPqtqsvSN3FjMJrt2kHPe+vS6pNANiqdecJyUDbbeqE
    mNyRz5b9rzAKBggqhkjOPQQDAgNJADBGAiEA6vAD5ekA5Od4NdvGqJN3bdV+mZ72
    fprax4w4aTtRQFACIQC/sU5et6LHXymwMI4GB5n8qmcg8bisEdW8N/doZY+9LA==
    -----END CERTIFICATE-----

    """

    func makeTestCert() throws -> SecCertificate {
        let zkc = ZitiKeychain(tag: tag)
        return try XCTUnwrap(SecCertificateCreateWithData(nil, zkc.convertToDER(certPEM) as CFData))
    }

    func assertDictEqual(_ actual: [CFString: Any], _ expected: [CFString: Any],
                         file: StaticString = #filePath, line: UInt = #line) {
        let a = actual as NSDictionary
        let e = expected as NSDictionary
        XCTAssertEqual(a.count, e.count, "key count mismatch", file: file, line: line)
        XCTAssertEqual(a, e, file: file, line: line)
    }

    // MARK: - keys

    func testCreateKeyParameters() {
        let expected: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits: 3072,
            kSecReturnRef: kCFBooleanTrue!,
            kSecAttrLabel: tag,
            kSecAttrIsPermanent: kCFBooleanTrue!,
            kSecAttrApplicationTag: atag,
            kSecPrivateKeyAttrs: [
                kSecAttrIsPermanent: kCFBooleanTrue!,
                kSecAttrLabel: tag,
                kSecAttrApplicationTag: atag] as [CFString: Any],
            kSecUseDataProtectionKeychain: kCFBooleanTrue!]
        assertDictEqual(ZitiKeychain.createKeyParameters(tag: tag), expected)
    }

    func testPrivateKeyQuery() {
        let expected: [CFString: Any] = [
            kSecClass: kSecClassKey,
            kSecAttrKeyClass: kSecAttrKeyClassPrivate,
            kSecAttrApplicationTag: atag,
            kSecReturnRef: kCFBooleanTrue!,
            kSecUseDataProtectionKeychain: kCFBooleanTrue!]
        assertDictEqual(ZitiKeychain.privateKeyQuery(tag: tag), expected)
    }

    func testDeleteKeyQueryPublic() {
        let expected: [CFString: Any] = [
            kSecClass: kSecClassKey,
            kSecAttrKeyClass: kSecAttrKeyClassPublic,
            kSecAttrApplicationTag: atag,
            kSecUseDataProtectionKeychain: kCFBooleanTrue!]
        assertDictEqual(ZitiKeychain.deleteKeyQuery(tag: tag, keyClass: kSecAttrKeyClassPublic), expected)
    }

    func testDeleteKeyQueryPrivate() {
        let expected: [CFString: Any] = [
            kSecClass: kSecClassKey,
            kSecAttrKeyClass: kSecAttrKeyClassPrivate,
            kSecAttrApplicationTag: atag,
            kSecUseDataProtectionKeychain: kCFBooleanTrue!]
        assertDictEqual(ZitiKeychain.deleteKeyQuery(tag: tag, keyClass: kSecAttrKeyClassPrivate), expected)
    }

    func testRetagQuery() {
        let expected: [CFString: Any] = [
            kSecClass: kSecClassKey,
            kSecAttrKeyClass: kSecAttrKeyClassPrivate,
            kSecAttrApplicationTag: atag,
            kSecUseDataProtectionKeychain: kCFBooleanTrue!]
        assertDictEqual(ZitiKeychain.retagQuery(tag: tag), expected)
    }

    func testRetagUpdate() {
        let newTag = "real-identity-id"
        let expected: [CFString: Any] = [
            kSecAttrApplicationTag: newTag.data(using: .utf8)!,
            kSecAttrLabel: newTag]
        assertDictEqual(ZitiKeychain.retagUpdate(newTag: newTag), expected)
    }

    func testTagIsUTF8() {
        let t = "ünïcødé-tag"
        let q = ZitiKeychain.privateKeyQuery(tag: t) as NSDictionary
        XCTAssertEqual(q[kSecAttrApplicationTag] as? Data, Data(t.utf8))
    }

    // MARK: - certificates

    func testCertificateAddParameters() throws {
        let cert = try makeTestCert()
        let expected: [CFString: Any] = [
            kSecClass: kSecClassCertificate,
            kSecValueRef: cert,
            kSecAttrLabel: tag,
            kSecUseDataProtectionKeychain: kCFBooleanTrue!]
        assertDictEqual(ZitiKeychain.certificateAddParameters(tag: tag, cert: cert), expected)
    }

    func testCertificatesAddParametersWithLabel() throws {
        let cert = try makeTestCert()
        let expected: [CFString: Any] = [
            kSecClass: kSecClassCertificate,
            kSecValueRef: cert,
            kSecAttrLabel: "czititest",
            kSecUseDataProtectionKeychain: kCFBooleanTrue!]
        assertDictEqual(ZitiKeychain.certificatesAddParameters(cert: cert, label: "czititest"), expected)
    }

    func testCertificatesAddParametersWithoutLabel() throws {
        let cert = try makeTestCert()
        let expected: [CFString: Any] = [
            kSecClass: kSecClassCertificate,
            kSecValueRef: cert,
            kSecUseDataProtectionKeychain: kCFBooleanTrue!]
        assertDictEqual(ZitiKeychain.certificatesAddParameters(cert: cert, label: nil), expected)
    }

    func testLegacyCertificateQuery() {
        // No kSecUseDataProtectionKeychain, by design: this finds certificates stored by older releases.
        let expected: [CFString: Any] = [
            kSecClass: kSecClassCertificate,
            kSecReturnRef: kCFBooleanTrue!,
            kSecAttrLabel: "some-cn"]
        assertDictEqual(ZitiKeychain.legacyCertificateQuery(label: "some-cn"), expected)
    }

    func testCertificateQuery() {
        let expected: [CFString: Any] = [
            kSecClass: kSecClassCertificate,
            kSecReturnRef: kCFBooleanTrue!,
            kSecAttrLabel: tag,
            kSecUseDataProtectionKeychain: kCFBooleanTrue!]
        assertDictEqual(ZitiKeychain.certificateQuery(tag: tag), expected)
    }

    func testCertificateDeleteParameters() throws {
        let cert = try makeTestCert()
        let expected: [CFString: Any] = [
            kSecClass: kSecClassCertificate,
            kSecValueRef: cert,
            kSecAttrLabel: tag,
            kSecUseDataProtectionKeychain: kCFBooleanTrue!]
        assertDictEqual(ZitiKeychain.certificateDeleteParameters(tag: tag, cert: cert), expected)
    }

    // MARK: - PEM

    func testConvertToPEMShort() {
        let zkc = ZitiKeychain(tag: tag)
        XCTAssertEqual(zkc.convertToPEM("RSA PRIVATE KEY", der: Data([0, 1, 2])),
                       "-----BEGIN RSA PRIVATE KEY-----\nAAEC\n-----END RSA PRIVATE KEY-----\n")
    }

    func testConvertToPEMExactLine() {
        let zkc = ZitiKeychain(tag: tag)
        XCTAssertEqual(zkc.convertToPEM("RSA PRIVATE KEY", der: Data(0..<48)),
                       "-----BEGIN RSA PRIVATE KEY-----\n" +
                       "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8gISIjJCUmJygpKissLS4v\n" +
                       "-----END RSA PRIVATE KEY-----\n")
    }

    func testConvertToPEMOneOverLine() {
        let zkc = ZitiKeychain(tag: tag)
        XCTAssertEqual(zkc.convertToPEM("RSA PRIVATE KEY", der: Data(0..<49)),
                       "-----BEGIN RSA PRIVATE KEY-----\n" +
                       "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8gISIjJCUmJygpKissLS4v\n" +
                       "MA==\n" +
                       "-----END RSA PRIVATE KEY-----\n")
    }

    func testConvertToPEMMultiLine() {
        // includes '+' and '=' which must pass through unchanged
        let zkc = ZitiKeychain(tag: tag)
        XCTAssertEqual(zkc.convertToPEM("CERTIFICATE", der: Data(0..<100)),
                       "-----BEGIN CERTIFICATE-----\n" +
                       "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8gISIjJCUmJygpKissLS4v\n" +
                       "MDEyMzQ1Njc4OTo7PD0+P0BBQkNERUZHSElKS0xNTk9QUVJTVFVWV1hZWltcXV5f\n" +
                       "YGFiYw==\n" +
                       "-----END CERTIFICATE-----\n")
    }

    func testConvertToPEMSlash() {
        let zkc = ZitiKeychain(tag: tag)
        XCTAssertEqual(zkc.convertToPEM("X", der: Data([0xff, 0xff, 0xff])),
                       "-----BEGIN X-----\n////\n-----END X-----\n")
    }

    func testConvertToPEMEmpty() {
        let zkc = ZitiKeychain(tag: tag)
        XCTAssertEqual(zkc.convertToPEM("X", der: Data()), "-----BEGIN X-----\n-----END X-----\n")
        XCTAssertNil(zkc.convertToPEM("X", ders: []))
    }

    func testConvertToPEMMultipleDers() {
        let zkc = ZitiKeychain(tag: tag)
        XCTAssertEqual(zkc.convertToPEM("CERTIFICATE", ders: [Data([0, 1, 2]), Data([0xff, 0xff, 0xff])]),
                       "-----BEGIN CERTIFICATE-----\nAAEC\n-----END CERTIFICATE-----\n" +
                       "-----BEGIN CERTIFICATE-----\n////\n-----END CERTIFICATE-----\n")
    }

    func testCertificatePEMRoundTrip() throws {
        let zkc = ZitiKeychain(tag: tag)
        let der = zkc.convertToDER(certPEM)
        XCTAssertEqual(zkc.convertToPEM("CERTIFICATE", der: der), certPEM)
    }

    func testGetKeyPEMDefaultType() throws {
        // ephemeral key, never touches the keychain
        let params: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits: 2048,
            kSecAttrIsPermanent: false]
        let key = try XCTUnwrap(SecKeyCreateRandomKey(params as CFDictionary, nil))
        let der = try XCTUnwrap(SecKeyCopyExternalRepresentation(key, nil) as Data?)

        let zkc = ZitiKeychain(tag: tag)
        let pem = zkc.getKeyPEM(key)
        XCTAssertTrue(pem.hasPrefix("-----BEGIN RSA PRIVATE KEY-----\n"))
        XCTAssertTrue(pem.hasSuffix("\n-----END RSA PRIVATE KEY-----\n"))
        XCTAssertEqual(pem, zkc.convertToPEM("RSA PRIVATE KEY", der: der))
        XCTAssertEqual(zkc.convertToDER(pem), der)
    }
}

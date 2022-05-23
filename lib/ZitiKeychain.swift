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

import Foundation

/// This class manages access to the Keychain, creating and storing keys and certificates needed to access a Ziti network.
///
/// This is primarily an internally used class, though certain methods are marked public in order to support senarios where the enrollment is
/// provided by an application other than the one that needs to access Ziti using this identity (which will require the end user to provide their credentials
/// to configure the keychain to allow the application access to the keys and certificates).
///
public class ZitiKeychain : NSObject {
    private let log = ZitiLog(ZitiKeychain.self)
    
    private let tag:String
    private let atag:Data
    
    /// Initialize an instance of `ZitiKeychain`
    ///
    /// - Parameters:
    ///     - tag: a `String` used to identify the application in the keychain.  This is usually set to the `sub` field of the one-time JWT used during enrollment
    public init(tag:String) {
        self.tag = tag
        self.atag = tag.data(using: .utf8)!
        super.init()
    }
    
    
    private let keySize = 3072
    func createPrivateKey() -> SecKey? {
        let privateKeyParams: [CFString: Any] = [ // iOS
            kSecAttrIsPermanent: true,
            kSecAttrLabel: tag,
            kSecAttrApplicationTag: atag]
        
        var parameters: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits: keySize,
            kSecReturnRef: kCFBooleanTrue as Any,
            kSecAttrLabel: tag, //macOs
            kSecAttrIsPermanent: true, // macOs
            kSecAttrApplicationTag: atag, //macOs
            kSecPrivateKeyAttrs: privateKeyParams]
        if #available(iOS 13.0, OSX 10.15, *) {
            parameters[kSecUseDataProtectionKeychain] = true
        }
        
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(parameters as CFDictionary, &error) else {
            log.error("Unable to create private key for \(tag): \(error!.takeRetainedValue() as Error)")
            return nil
        }
        return privateKey
    }
    
    func getPrivateKey() -> SecKey? {
        let (key, _, _) = getKeyPair()
        return key
    }
    
    func getKeyPair() -> (privKey:SecKey?, pubKey:SecKey?, ZitiError?) {
        var parameters:[CFString:Any] = [
            kSecClass: kSecClassKey,
            kSecAttrKeyClass: kSecAttrKeyClassPrivate,
            kSecAttrApplicationTag: atag,
            kSecReturnRef: kCFBooleanTrue!]
        if #available(iOS 13.0, OSX 10.15, *) {
            parameters[kSecUseDataProtectionKeychain] = true
        }
        
        var ref: AnyObject?
        let status = SecItemCopyMatching(parameters as CFDictionary, &ref)
        guard status == errSecSuccess else {
            let errStr = SecCopyErrorMessageString(status, nil) as String? ?? "\(status)"
            log.error(errStr)
            return (nil, nil, ZitiError("Unable to get private key for \(tag): \(errStr)", errorCode: Int(status)))
        }
        let privKey = ref! as! SecKey
        guard let pubKey = SecKeyCopyPublicKey(privKey) else {
            let errStr = "Unable to copy public key for \(tag)"
            log.error(errStr)
            return (nil, nil, ZitiError(errStr))
        }
        return (privKey, pubKey, nil)
    }
    
    func keyPairExists() -> Bool {
        let (_, _, e) = getKeyPair()
        return e == nil
    }
    
    func getKeyPEM(_ key:SecKey, _ type:String="RSA PRIVATE KEY") -> String {
        var cfErr:Unmanaged<CFError>?
        guard let derKey = SecKeyCopyExternalRepresentation(key, &cfErr) else {
            log.error("Unable to get external rep for key: \(cfErr!.takeRetainedValue() as Error)")
            return ""
        }
        return convertToPEM(type, der: derKey as Data)
    }
    
    private func deleteKey(_ keyClass:CFString) -> OSStatus {
        var deleteQuery:[CFString:Any] = [
            kSecClass: kSecClassKey,
            kSecAttrKeyClass: keyClass,
            kSecAttrApplicationTag: atag]
        if #available(iOS 13.0, OSX 10.15, *) {
            deleteQuery[kSecUseDataProtectionKeychain] = true
        }
        return SecItemDelete(deleteQuery as CFDictionary)
    }
    
    func deleteKeyPair(silent:Bool=false) -> ZitiError? {
        _ = deleteKey(kSecAttrKeyClassPublic)
        let status = deleteKey(kSecAttrKeyClassPrivate)
        guard status == errSecSuccess else {
            let errStr = SecCopyErrorMessageString(status, nil) as String? ?? "\(status)"
            if !silent { log.error(errStr) }
            return ZitiError("Unable to delete key pair for \(tag): \(errStr)", errorCode: Int(status))
        }
        return nil
    }
    
#if os(macOS)
    /// __macOS only__
    /// This method will prompt for user creds to access keychain to mark the provided certificate as `Trusted`
    ///
    /// - Parameters:
    ///     - certificate: The certificate for which to add trust
    public func addTrustForCertificate(_ certificate:SecCertificate) -> OSStatus {
        //let trustSettings:[String:Any] = [ kSecTrustSettingsPolicy : SecPolicyCreateSSL(true, nil)]
        return SecTrustSettingsSetTrustSettings(certificate,
                                                SecTrustSettingsDomain.user,
                                                nil) //trustSettings as CFTypeRef)
    }
#endif
    
    func isRootCa(_ cert:SecCertificate) -> Bool {
        if let issuer = SecCertificateCopyNormalizedIssuerSequence(cert),
            let subject = SecCertificateCopyNormalizedSubjectSequence(cert) {
            if (issuer as NSData).isEqual(to: (subject as NSData) as Data) {
                return true
            }
        }
        return false
    }
    
    /// Extract the Root CA certificate from the provided pool
    ///
    /// - Parameters:
    ///     - caPool: PEM-formatted pool of CA certificates
    ///
    /// - Returns:the Root CA certificate, or `nil` if not found
    public func extractRootCa(_ caPool:String) -> SecCertificate? {
        let pems = extractPEMs(caPool)
        for c in PEMstoCerts(pems) {
            if isRootCa(c) { return c }
        }
        return nil
    }
    
    /// Add the provided Root CA pool to the keychain
    ///
    /// - Parameters:
    ///     - caPool:PEM-formatted pool of CA certificates
    ///
    /// - Returns: `true` if the certificates are successfully added to the keychain, otherwise `false`
    public func addCaPool(_ caPool:String) -> Bool {
        let certs = extractCerts(caPool)
        for cert in certs {
            var parameters: [CFString: Any] = [
                kSecClass: kSecClassCertificate,
                kSecValueRef: cert]
            if #available(iOS 13.0, OSX 10.15, *) {
                parameters[kSecUseDataProtectionKeychain] = true
            }
            let status = SecItemAdd(parameters as CFDictionary, nil)
            guard status == errSecSuccess || status == errSecDuplicateItem else {
                let errStr = SecCopyErrorMessageString(status, nil) as String? ?? "\(status)"
                log.error("Unable to store certificate for \(tag): \(errStr)")
                return false
            }
            log.info("Added cert to keychain: \(String(describing: SecCertificateCopySubjectSummary(cert)))")
        }
        return true
    }
    
#if os(macOS) // if #available(iOS 13.0, OSX 10.15, *)
    /**
     * Evaluates a trust object asynchronously on the specified dispatch queue.
     *
     * - Parameters:
     *      - certificates: The certificate to be verified, plus any other certificates that might be useful for verifying the certificate.
     *      - queue: The dispatch queue on which the result block should execute. You must call the method from the same queue.
     *      - result: A closure that the method calls to report the result of trust evaluation.
     *
     * You must call this method from the same dispatch queue that you specify as the queue parameter.
     */
    public func evalTrustForCertificates(_ certificates:[SecCertificate],
                                         _ queue:DispatchQueue,
                                         _ result: @escaping SecTrustWithErrorCallback) -> OSStatus {
        var secTrust:SecTrust?
        let policy = SecPolicyCreateBasicX509()
        let stcStatus = SecTrustCreateWithCertificates(certificates as CFTypeRef, policy, &secTrust)
        if stcStatus != errSecSuccess { return stcStatus }
        guard secTrust != nil else { return errSecBadReq }
        let sceStatus = SecTrustEvaluateAsyncWithError(secTrust!, queue, result)
        return sceStatus
    }
#endif
    
    func storeCertificate(fromPem pem:String) -> ZitiError? {
        let (_, zErr) = storeCertificate(fromDer: convertToDER(pem))
        if zErr != nil {
            log.error(zErr!.localizedDescription)
        }
        return zErr
    }
    
    func storeCertificate(fromDer der:Data) -> (SecCertificate?, ZitiError?) {
        guard let certificate = SecCertificateCreateWithData(nil, der as CFData) else {
            let errStr = "Unable to create certificate from data for \(tag)"
            log.error(errStr)
            return (nil, ZitiError(errStr))
        }
        var parameters: [CFString: Any] = [
            kSecClass: kSecClassCertificate,
            kSecValueRef: certificate,
            kSecAttrLabel: tag]
        if #available(iOS 13.0, OSX 10.15, *) {
            parameters[kSecUseDataProtectionKeychain] = true
        }
        let status = SecItemAdd(parameters as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else {
            let errStr = SecCopyErrorMessageString(status, nil) as String? ?? "\(status)"
            log.error(errStr)
            return (nil, ZitiError("Unable to store certificate for \(tag): \(errStr)", errorCode: Int(status)))
        }
        return (certificate, nil)
    }
    
    func getCertificate() -> (Data?, ZitiError?) {
        let params: [CFString: Any] = [
            kSecClass: kSecClassCertificate,
            kSecReturnRef: kCFBooleanTrue!,
            kSecAttrLabel: tag]
        
        var cert: CFTypeRef?
        let status = SecItemCopyMatching(params as CFDictionary, &cert)
        guard status == errSecSuccess else {
            let errStr = SecCopyErrorMessageString(status, nil) as String? ?? "\(status)"
            log.error(errStr)
            return (nil, ZitiError("Unable to get certificate for \(tag): \(errStr)", errorCode: Int(status)))
        }
        guard let certData = SecCertificateCopyData(cert as! SecCertificate) as Data? else {
            let errStr = "Unable to copy certificate data for \(tag)"
            log.error(errStr)
            return (nil, ZitiError(errStr))
        }
        return (certData, nil)
    }
    
    func deleteCertificate(silent:Bool=false) -> ZitiError? {
        var params: [CFString: Any] = [
            kSecClass: kSecClassCertificate,
            kSecReturnRef: kCFBooleanTrue!,
            kSecAttrLabel: tag]
        if #available(iOS 13.0, OSX 10.15, *) {
            params[kSecUseDataProtectionKeychain] = true
        }
        
        var cert: CFTypeRef?
        let copyStatus = SecItemCopyMatching(params as CFDictionary, &cert)
        guard copyStatus == errSecSuccess else {
            let errStr = SecCopyErrorMessageString(copyStatus, nil) as String? ?? "\(copyStatus)"
            if !silent { log.error(errStr) }
            return ZitiError("Unable to find certificate for \(tag): \(errStr)", errorCode: Int(copyStatus))
        }
        
        var delParams: [CFString:Any] = [
            kSecClass: kSecClassCertificate,
            kSecValueRef: cert!,
            kSecAttrLabel: tag]
        if #available(iOS 13.0, OSX 10.15, *) {
            delParams[kSecUseDataProtectionKeychain] = true
        }
        let deleteStatus = SecItemDelete(delParams as CFDictionary)
        guard deleteStatus == errSecSuccess else {
            let errStr = SecCopyErrorMessageString(deleteStatus, nil) as String? ?? "\(deleteStatus)"
            if !silent { log.error(errStr) }
            return ZitiError("Unable to delete certificate for \(tag): \(errStr)", errorCode: Int(deleteStatus))
        }
        return nil
    }
    
    func convertToPEM(_ type:String, der:Data) -> String {
        guard let str = der.base64EncodedString(options: NSData.Base64EncodingOptions(rawValue: 0)).addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed) else {
            return ""
        }
        var pem = "-----BEGIN \(type)-----\n";
        for (i, ch) in str.enumerated() {
            pem.append(ch)
            if ((i != 0) && ((i+1) % 64 == 0)) {
                pem.append("\n")
            }
        }
        if (str.count % 64) != 0 {
            pem.append("\n")
        }
        return pem + "-----END \(type)-----\n"
    }
    
    /// Extract certificates from a PEM-formatted CA pool and return an array of `SecCertificate` objects
    ///
    /// - Parameters:
    ///     - caPool: PEM-formatted pool of CA certificates
    ///
    /// - Returns: an array of `SecCertificate` objects
    public func extractCerts(_ caPool:String) -> [SecCertificate] {
        return PEMstoCerts(extractPEMs(caPool))
    }
    
    func extractPEMs(_ caPool:String) -> [String] {
        var pems:[String] = []
        let start = "-----BEGIN CERTIFICATE-----"
        let end = "-----END CERTIFICATE-----"
        
        var pem:String? = nil
        caPool.split(separator: "\n").forEach { line in
            if line == start {
                pem = String(line) + "\n"
            } else if pem != nil {
                if line == end {
                    pems.append(pem!)
                    pem = nil
                } else {
                    pem = pem! + line + "\n"
                }
            }
        }
        return pems
    }
    
    func PEMstoCerts(_ pems:[String]) -> [SecCertificate] {
        var certs:[SecCertificate] = []
        pems.forEach { pem in
            let der = convertToDER(pem)
            if let cert = SecCertificateCreateWithData(nil, der as CFData) {
                certs.append(cert)
            }
        }
        return certs
    }
        
    func convertToDER(_ pem:String) -> Data {
        var der = Data()
        pem.split(separator: "\n").forEach { line in
            if line.starts(with: "-----") == false {
                der.append(Data(base64Encoded: String(line)) ?? Data())
            }
        }
        return der
    }
}

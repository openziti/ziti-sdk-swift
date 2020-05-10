/*
Copyright 2020 NetFoundry, Inc.

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

@objc public class ZitiKeychain : NSObject {
    private let tag:String
    private let atag:Data
    
    public init(tag:String) {
        self.tag = tag
        self.atag = tag.data(using: .utf8)!
        super.init()
    }
    
    @objc public func storeController(_ controller:String) -> ZitiError? {
        guard let data = controller.data(using: .utf8) else {
            return ZitiError("\(#function): Unable to create keychain data for \(controller)")
        }
        
        let parameters: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: tag,
            kSecAttrGeneric: atag,
            kSecAttrAccount: atag,
            kSecValueData: data]
        let status = SecItemAdd(parameters as CFDictionary, nil)
        guard status == errSecSuccess else {
            let errStr = SecCopyErrorMessageString(status, nil) as String? ?? "\(status)"
            return ZitiError("Unable to store controller for \(tag): \(errStr)", errorCode: Int(status))
        }
        return nil
    }
    
    @objc public func getController() -> String? {
        guard let atag = tag.data(using: .utf8) else { return nil }
        let parameters: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: "Ziti",
            kSecAttrGeneric: atag,
            kSecAttrAccount: atag,
            kSecReturnData: kCFBooleanTrue!]
        
        var result:AnyObject?
        let status = SecItemCopyMatching(parameters as CFDictionary, &result)
        guard status == errSecSuccess else {
            // TODO: Log error message
            // let errStr = SecCopyErrorMessageString(status, nil) as String? ?? "\(status)"
            // ZitiError("\(#function): Unable to get private key for \(tag): \(errStr)", errorCode: Int(status))
            return nil
        }
        if let data = result as? Data {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }
    
    @objc public func storePrivateKey(fromPem pem:String, _ keyType:CFString) -> ZitiError? {
        return storePrivateKey(fromDer: convertToDER(pem), keyType)
    }
    
    func storePrivateKey(fromDer der:Data, _ keyType:CFString) -> ZitiError? {
        let parameters: [CFString: Any] = [kSecAttrKeyType: keyType]
        
        var cfErr:Unmanaged<CFError>?
        guard let secKey = SecKeyCreateFromData(parameters as CFDictionary, der as CFData, &cfErr) else {
            return ZitiError("Unable to create key from data: \(cfErr!.takeRetainedValue() as Error)")
        }
        return storePrivateKey(secKey)
    }
    
    func storePrivateKey(_ key:SecKey) -> ZitiError? {
        guard let atag = tag.data(using: .utf8) else {
            return ZitiError("\(#function): Unable to create application tag \(tag)")
        }
        let parameters: [CFString: Any] = [
            kSecClass: kSecClassKey,
            kSecAttrKeyClass: kSecAttrKeyClassPrivate,
            kSecAttrApplicationTag: atag,
            kSecValueRef: key]
        let status = SecItemAdd(parameters as CFDictionary, nil)
        guard status == errSecSuccess else {
            let errStr = SecCopyErrorMessageString(status, nil) as String? ?? "\(status)"
            return ZitiError("Unable to store private key for \(tag): \(errStr)", errorCode: Int(status))
        }
        return nil
    }
    
    func getKeyPair() -> (privKey:SecKey?, pubKey:SecKey?, ZitiError?) {
        let parameters:[CFString:Any] = [
            kSecClass: kSecClassKey,
            kSecAttrKeyClass: kSecAttrKeyClassPrivate,
            kSecAttrApplicationTag: atag,
            kSecReturnRef: kCFBooleanTrue!]
        var ref: AnyObject?
        let status = SecItemCopyMatching(parameters as CFDictionary, &ref)
        guard status == errSecSuccess else {
            let errStr = SecCopyErrorMessageString(status, nil) as String? ?? "\(status)"
            return (nil, nil, ZitiError("\(#function): Unable to get private key for \(tag): \(errStr)", errorCode: Int(status)))
        }
        let privKey = ref! as! SecKey
        guard let pubKey = SecKeyCopyPublicKey(privKey) else {
            return (nil, nil, ZitiError("\(#function): Unable to copy public key for \(tag)"))
        }
        return (privKey, pubKey, nil)
    }
    
    func keyPairExists() -> Bool {
        let (_, _, e) = getKeyPair()
        return e == nil
    }
    
    func getKeyPEM(_ key:SecKey, _ type:String="EC PRIVATE KEY") -> String {
        var cfErr:Unmanaged<CFError>?
        guard let derKey = SecKeyCopyExternalRepresentation(key, &cfErr) else {
            NSLog("\(#function): Unable to get external rep for key: \(cfErr!.takeRetainedValue() as Error)")
            return ""
        }
        return convertToPEM(type, der: derKey as Data)
    }
    
    private func deleteKey(_ keyClass:CFString) -> OSStatus {
        let deleteQuery:[CFString:Any] = [
            kSecClass: kSecClassKey,
            kSecAttrKeyClass: keyClass,
            kSecAttrApplicationTag: atag]
        return SecItemDelete(deleteQuery as CFDictionary)
    }
    
    func deleteKeyPair() -> ZitiError? {
        _ = deleteKey(kSecAttrKeyClassPublic)
        let status = deleteKey(kSecAttrKeyClassPrivate)
        guard status == errSecSuccess else {
            let errStr = SecCopyErrorMessageString(status, nil) as String? ?? "\(status)"
            return ZitiError("Unable to delete key pair for \(tag): \(errStr)", errorCode: Int(status))
        }
        return nil
    }
    
#if os(macOS)
    // Will prompt for user creds to access keychain
    @objc public func addTrustForCertificate(_ certificate:SecCertificate) -> OSStatus {
        return SecTrustSettingsSetTrustSettings(certificate, SecTrustSettingsDomain.user, nil) // macOS only
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
    
    @objc public func extractRootCa(_ caPool:String) -> SecCertificate? {
        let pems = extractPEMs(caPool)
        var cert:SecCertificate?
        PEMstoCerts(pems).forEach { c in
            if isRootCa(c) {
                cert = c
            }
        }
        return cert
    }
    
    /**
     * !!You must call this method from the same dispatch queue that you specify as the queue parameter.
     */
    @objc public func evalTrustForCertificates(_ certificates:[SecCertificate],
                                         _ queue:DispatchQueue,
                                         _ result: @escaping SecTrustWithErrorCallback) -> OSStatus {
        var secTrust:SecTrust?
        let policy = SecPolicyCreateBasicX509()
        let stcStatus = SecTrustCreateWithCertificates(certificates as CFTypeRef, policy, &secTrust)
        if stcStatus != errSecSuccess { return stcStatus }
        guard secTrust != nil else { return errSecBadReq }
        /*
        let dq = DispatchQueue(label: "evalTrustForCertificate")
        dq.async {
            let sceStatus = SecTrustEvaluateAsyncWithError(secTrust!, dq, result)
        }*/
        let sceStatus = SecTrustEvaluateAsyncWithError(secTrust!, queue, result)
        return sceStatus
    }
    
    @objc public func storeCertificate(fromPem pem:String) -> ZitiError? {
         let (_, zErr) = storeCertificate(fromDer: convertToDER(pem))
        return zErr
    }
    
    func storeCertificate(fromDer der:Data) -> (SecCertificate?, ZitiError?) {
        guard let certificate = SecCertificateCreateWithData(nil, der as CFData) else {
            return (nil, ZitiError("Unable to create certificate from data for \(tag)"))
        }
        let parameters: [CFString: Any] = [
            kSecClass: kSecClassCertificate,
            kSecValueRef: certificate,
            kSecAttrLabel: tag]
        let status = SecItemAdd(parameters as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else {
            let errStr = SecCopyErrorMessageString(status, nil) as String? ?? "\(status)"
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
            return (nil, ZitiError("Unable to get certificate for \(tag): \(errStr)", errorCode: Int(status)))
        }
        guard let certData = SecCertificateCopyData(cert as! SecCertificate) as Data? else {
            return (nil, ZitiError("Unable to copy certificate data for \(tag)"))
        }
        return (certData, nil)
    }
    
    func deleteCertificate() -> ZitiError? {
        let params: [CFString: Any] = [
            kSecClass: kSecClassCertificate,
            kSecReturnRef: kCFBooleanTrue!,
            kSecAttrLabel: tag]
        
        var cert: CFTypeRef?
        let copyStatus = SecItemCopyMatching(params as CFDictionary, &cert)
        guard copyStatus == errSecSuccess else {
            let errStr = SecCopyErrorMessageString(copyStatus, nil) as String? ?? "\(copyStatus)"
            return ZitiError("Unable to find certificate for \(tag): \(errStr)", errorCode: Int(copyStatus))
        }
        
        let delParams: [CFString:Any] = [
            kSecClass: kSecClassCertificate,
            kSecValueRef: cert!,
            kSecAttrLabel: tag]
        let deleteStatus = SecItemDelete(delParams as CFDictionary)
        guard deleteStatus == errSecSuccess else {
            let errStr = SecCopyErrorMessageString(deleteStatus, nil) as String? ?? "\(deleteStatus)"
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
    
    @objc public func extractCerts(_ caPool:String) -> [SecCertificate] {
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
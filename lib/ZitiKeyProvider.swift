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

/// Creates, finds and removes the private key and certificate for an identity.
///
/// Private key and identity certificate storage in `Ziti` and `ZitiTunnel` goes through
/// `zitiKeyProvider` so storage details stay in one place.
protocol ZitiKeyProvider {
    /// Delete any existing key pair for `tag`, create a new private key and return it as PEM.
    /// Returns `nil` if the key could not be created.
    func createKey(tag:String) -> String?

    /// The private key string `run()` hands to the C SDK for `id`, or `nil` if there is none
    /// (e.g. external authentication). Today this is always a PEM, but a provider whose keys
    /// can't leave the keychain would return a `keychain:` reference instead.
    func keyString(for id:ZitiIdentity) -> String?

    /// The certificate PEM `run()` hands to the C SDK for `id`, or `nil` if there is none
    /// (e.g. external authentication).
    func certificates(for id:ZitiIdentity) -> String?

    func deleteKey(tag:String, silent:Bool) -> ZitiError?

    /// Move the private key stored under `oldTag` to `newTag`.
    func retagKey(from oldTag:String, to newTag:String) -> ZitiError?

    /// Store the first certificate in `pem` for `tag`.
    func storeCertificate(tag:String, pem:String) -> ZitiError?

    func deleteCertificate(tag:String, silent:Bool) -> ZitiError?

    /// Called with the PEM returned by `createKey(tag:)` once the enrolled identity exists.
    func persistKey(_ pem:String, in id:ZitiIdentity)

    /// Carry whatever `persistKey(_:in:)` stored in `src` over to `dst`, for when enrollment
    /// replaces a temporary identity with the final one.
    func copyKey(from src:ZitiIdentity, to dst:ZitiIdentity)
}

/// Keys and certificates live in the keychain, managed by `ZitiKeychain`.
struct KeychainKeyProvider : ZitiKeyProvider {
    func createKey(tag:String) -> String? {
        let zkc = ZitiKeychain(tag: tag)
        _ = zkc.deleteKeyPair(silent: true)
        guard let privKey = zkc.createPrivateKey() else { return nil }
        return zkc.getKeyPEM(privKey)
    }

    func keyString(for id:ZitiIdentity) -> String? {
        let zkc = ZitiKeychain(tag: id.id)
        guard let privKey = zkc.getPrivateKey() else { return nil }
        return zkc.getKeyPEM(privKey)
    }

    func certificates(for id:ZitiIdentity) -> String? {
        return id.getCertificates(ZitiKeychain(tag: id.id))
    }

    func deleteKey(tag:String, silent:Bool) -> ZitiError? {
        return ZitiKeychain(tag: tag).deleteKeyPair(silent: silent)
    }

    func retagKey(from oldTag:String, to newTag:String) -> ZitiError? {
        return ZitiKeychain(tag: oldTag).retagPrivateKey(to: newTag)
    }

    func storeCertificate(tag:String, pem:String) -> ZitiError? {
        return ZitiKeychain(tag: tag).storeCertificate(fromPem: pem)
    }

    func deleteCertificate(tag:String, silent:Bool) -> ZitiError? {
        return ZitiKeychain(tag: tag).deleteCertificate(silent: silent)
    }

    func persistKey(_ pem:String, in id:ZitiIdentity) {
        // the key is already in the keychain
    }

    func copyKey(from src:ZitiIdentity, to dst:ZitiIdentity) {
        // the key is already in the keychain
    }
}

#if CZITI_TEST_INSECURE_KEYS
#warning("CZITI_TEST_INSECURE_KEYS is set: private keys are stored in plaintext. Test builds only.")

/// __Test builds only.__ Generates ephemeral keys and keeps the PEM in `ZitiIdentity.key`
/// (and so in plaintext in the .zid file). Never reads or writes the keychain, which lets
/// ad-hoc signed tools enroll without the data protection keychain entitlement. Never use
/// in a release build.
struct InsecureTestKeyProvider : ZitiKeyProvider {
    private static let log = ZitiLog()

    // Lazy-initialized so the warning prints at most once per process, the first time
    // a key is generated or loaded from an identity.
    private static let warning: Void = {
        let msg = "⚠️  CZITI_TEST_INSECURE_KEYS build: private keys are generated ephemerally and written into .zid files in plaintext. NEVER SHIP THIS BUILD.\n"
        FileHandle.standardError.write(Data(msg.utf8))
    }()

    func createKey(tag:String) -> String? {
        _ = InsecureTestKeyProvider.warning
        let parameters: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits: ZitiKeychain.keySize,
            kSecAttrIsPermanent: false,
        ]
        var error: Unmanaged<CFError>?
        guard let privKey = SecKeyCreateRandomKey(parameters as CFDictionary, &error) else {
            InsecureTestKeyProvider.log.error("Unable to create ephemeral private key for \(tag): \(error!.takeRetainedValue() as Error)")
            return nil
        }
        return ZitiKeychain(tag: tag).getKeyPEM(privKey)
    }

    func keyString(for id:ZitiIdentity) -> String? {
        guard let key = id.key, !key.isEmpty else { return nil }
        _ = InsecureTestKeyProvider.warning
        return key
    }

    func certificates(for id:ZitiIdentity) -> String? {
        return id.getCertificates(nil)
    }

    func deleteKey(tag:String, silent:Bool) -> ZitiError? { return nil }
    func retagKey(from oldTag:String, to newTag:String) -> ZitiError? { return nil }
    func storeCertificate(tag:String, pem:String) -> ZitiError? { return nil }
    func deleteCertificate(tag:String, silent:Bool) -> ZitiError? { return nil }

    func persistKey(_ pem:String, in id:ZitiIdentity) {
        id.key = pem
    }

    func copyKey(from src:ZitiIdentity, to dst:ZitiIdentity) {
        dst.key = src.key
    }
}
#endif

/// The key provider used by this build.
let zitiKeyProvider: ZitiKeyProvider = {
#if CZITI_TEST_INSECURE_KEYS
    return InsecureTestKeyProvider()
#else
    return KeychainKeyProvider()
#endif
}()

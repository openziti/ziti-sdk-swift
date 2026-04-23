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
import CFNetwork
import CZitiPrivate

/// Configures an HTTP CONNECT proxy for all Ziti controller and edge router connections.
///
/// The proxy is global - calling ``setProxy(host:port:)`` affects all Ziti contexts in the process.
/// This class also provides system proxy detection and keychain-based credential storage.
@objc public class ZitiHttpProxyConfig : NSObject {
    private static let log = ZitiLog(ZitiHttpProxyConfig.self)

    private override init() { super.init() }

    // MARK: - Proxy Configuration

    /// Set the global HTTP CONNECT proxy without authentication.
    ///
    /// - Parameters:
    ///   - host: Proxy hostname or IP address
    ///   - port: Proxy port number
    @objc public static func setProxy(host: String, port: UInt16) {
        let portStr = String(port)
        log.info("setting proxy to \(host):\(portStr)")
        ziti_proxy_set(host.cString(using: .utf8), portStr.cString(using: .utf8))
    }

    /// Set the global HTTP CONNECT proxy with BASIC authentication.
    ///
    /// - Parameters:
    ///   - host: Proxy hostname or IP address
    ///   - port: Proxy port number
    ///   - username: Proxy username for BASIC auth
    ///   - password: Proxy password for BASIC auth
    @objc public static func setProxy(host: String, port: UInt16, username: String, password: String) {
        let portStr = String(port)
        log.info("setting proxy to \(host):\(portStr) with basic auth (user: \(username))")
        ziti_proxy_set(host.cString(using: .utf8), portStr.cString(using: .utf8))
        let authResult = ziti_proxy_set_auth(username.cString(using: .utf8), password.cString(using: .utf8))
        if authResult != 0 {
            log.error("failed to set proxy auth, result: \(authResult)")
        }
    }

    /// Clear the global proxy, restoring direct connections.
    @objc public static func clearProxy() {
        log.info("clearing proxy")
        ziti_proxy_clear()
    }

    // MARK: - System Proxy Detection

    /// Detect the system HTTP proxy settings.
    ///
    /// Uses `CFNetworkCopySystemProxySettings()` to read the system-configured HTTP proxy.
    /// This detects host and port only; system proxy credentials are not reliably accessible
    /// (impossible on iOS, triggers a user dialog on macOS).
    ///
    /// - Returns: A tuple of `(host, port)` if a system HTTP proxy is enabled, or `nil` if none is configured.
    public static func systemProxy() -> (host: String, port: UInt16)? {
        // CFNetworkCopySystemProxySettings returns a +1 (Create Rule) CFDictionary,
        // so takeRetainedValue() is correct to transfer ownership to ARC.
        guard let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any] else {
            log.debug("unable to read system proxy settings")
            return nil
        }

        guard let enabled = settings[kCFNetworkProxiesHTTPEnable as String] as? Int, enabled != 0 else {
            log.debug("system HTTP proxy not enabled")
            return nil
        }

        guard let host = settings[kCFNetworkProxiesHTTPProxy as String] as? String, !host.isEmpty else {
            log.debug("system HTTP proxy host not set")
            return nil
        }

        guard let port = settings[kCFNetworkProxiesHTTPPort as String] as? Int, port > 0, port <= UInt16.max else {
            log.debug("system HTTP proxy port not set or out of range")
            return nil
        }

        log.info("detected system proxy: \(host):\(port)")
        return (host: host, port: UInt16(port))
    }

    // MARK: - Keychain Credential Storage

    /// Store proxy credentials in the keychain.
    ///
    /// Stores `username` and `password` as a `kSecClassInternetPassword` item keyed by
    /// proxy host, port, and `kSecAttrProtocolHTTPProxy`. If credentials already exist for
    /// the given host and port, they are replaced.
    ///
    /// - Parameters:
    ///   - username: Proxy username
    ///   - password: Proxy password
    ///   - proxyHost: The proxy server hostname
    ///   - proxyPort: The proxy server port
    ///
    /// - Returns: A ``ZitiError`` if the operation fails, or `nil` on success.
    @discardableResult
    @objc public static func storeCredentials(username: String, password: String,
                                              proxyHost: String, proxyPort: UInt16) -> ZitiError? {
        if let deleteErr = deleteCredentials(proxyHost: proxyHost, proxyPort: proxyPort) {
            log.warn("pre-store delete failed for \(proxyHost):\(proxyPort): \(deleteErr.localizedDescription)")
        }

        guard let passwordData = password.data(using: .utf8) else {
            let errStr = "unable to encode password as UTF-8"
            log.error(errStr)
            return ZitiError(errStr)
        }

        var query: [CFString: Any] = [
            kSecClass: kSecClassInternetPassword,
            kSecAttrServer: proxyHost,
            kSecAttrPort: Int(proxyPort),
            kSecAttrProtocol: kSecAttrProtocolHTTPProxy,
            kSecAttrAccount: username,
            kSecValueData: passwordData
        ]
        // Match ZitiKeychain pattern. Note: kSecUseDataProtectionKeychain requires
        // a provisioning-profile-backed app identity; CLI tools may get -34018.
        if #available(iOS 13.0, macOS 10.15, *) {
            query[kSecUseDataProtectionKeychain] = true
        }

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            let errStr = SecCopyErrorMessageString(status, nil) as String? ?? "\(status)"
            log.error("failed to store proxy credentials for \(proxyHost):\(proxyPort): \(errStr)")
            return ZitiError("Unable to store proxy credentials: \(errStr)", errorCode: Int(status))
        }

        log.info("stored proxy credentials for \(proxyHost):\(proxyPort) (user: \(username))")
        return nil
    }

    /// Load proxy credentials from the keychain.
    ///
    /// - Parameters:
    ///   - proxyHost: The proxy server hostname
    ///   - proxyPort: The proxy server port
    ///
    /// - Returns: A ``ZitiProxyCredentials`` if found, or `nil` if no credentials are stored.
    @objc public static func loadCredentials(proxyHost: String, proxyPort: UInt16) -> ZitiProxyCredentials? {
        var query: [CFString: Any] = [
            kSecClass: kSecClassInternetPassword,
            kSecAttrServer: proxyHost,
            kSecAttrPort: Int(proxyPort),
            kSecAttrProtocol: kSecAttrProtocolHTTPProxy,
            kSecReturnAttributes: true,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        if #available(iOS 13.0, macOS 10.15, *) {
            query[kSecUseDataProtectionKeychain] = true
        }

        var ref: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &ref)
        guard status == errSecSuccess else {
            if status != errSecItemNotFound {
                let errStr = SecCopyErrorMessageString(status, nil) as String? ?? "\(status)"
                log.error("failed to load proxy credentials for \(proxyHost):\(proxyPort): \(errStr)")
            }
            return nil
        }

        guard let item = ref as? [CFString: Any],
              let username = item[kSecAttrAccount] as? String,
              let passwordData = item[kSecValueData] as? Data,
              let password = String(data: passwordData, encoding: .utf8) else {
            log.error("unable to decode proxy credentials for \(proxyHost):\(proxyPort)")
            return nil
        }

        log.debug("loaded proxy credentials for \(proxyHost):\(proxyPort) (user: \(username))")
        return ZitiProxyCredentials(username: username, password: password)
    }

    /// Delete proxy credentials from the keychain.
    ///
    /// - Parameters:
    ///   - proxyHost: The proxy server hostname
    ///   - proxyPort: The proxy server port
    ///
    /// - Returns: A ``ZitiError`` if the delete fails (other than item-not-found), or `nil` on success.
    @discardableResult
    @objc public static func deleteCredentials(proxyHost: String, proxyPort: UInt16) -> ZitiError? {
        var query: [CFString: Any] = [
            kSecClass: kSecClassInternetPassword,
            kSecAttrServer: proxyHost,
            kSecAttrPort: Int(proxyPort),
            kSecAttrProtocol: kSecAttrProtocolHTTPProxy
        ]
        if #available(iOS 13.0, macOS 10.15, *) {
            query[kSecUseDataProtectionKeychain] = true
        }

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            let errStr = SecCopyErrorMessageString(status, nil) as String? ?? "\(status)"
            log.error("failed to delete proxy credentials for \(proxyHost):\(proxyPort): \(errStr)")
            return ZitiError("Unable to delete proxy credentials: \(errStr)", errorCode: Int(status))
        }

        log.debug("deleted proxy credentials for \(proxyHost):\(proxyPort)")
        return nil
    }
}

/// Proxy credentials returned by ``ZitiHttpProxyConfig/loadCredentials(proxyHost:proxyPort:)``.
@objc public class ZitiProxyCredentials : NSObject {
    @objc public let username: String
    @objc public let password: String

    init(username: String, password: String) {
        self.username = username
        self.password = password
    }
}

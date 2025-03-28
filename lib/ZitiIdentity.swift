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

/**
 Identity information for interacting with Ziti
 
 Objects of these types are `Codable` so can easiliy be converted to/from JSON and stored on disk.  A `ZitiIdentity` is created as part of `Ziti.enroll(_:_:)`, and can be used to initialiaze on instance of `Ziti`.
 
 - See Also:
    - `Ziti.enroll(_:_:)`
    - `Ziti.init(fromFile:)`
 */
@objc open class ZitiIdentity : NSObject, Codable {
    private static let log = ZitiLog(ZitiIdentity.self)
    private var log:ZitiLog { return ZitiIdentity.log }
    
    /// Identity string
    ///
    /// Initially the `sub` field from the  one-time enrollment JWT.  Used by `Ziti` to store and retrieve identity-related items in the Keychain
    @objc public let id:String
    
    /// Certificate CNs
    ///
    /// Common names for the certificates in this identities certificate chain. The first element will always match `id`.
    /// Used by `Ziti` to retrieve certificates from the Keychain.
    @objc public var certCNs:[String]?

    /// scheme, host, and port used to communicate with Ziti controller
    @objc public var ztAPI:String
    
    /// scheme, host. and port of all controllers in cluster
    @objc public var ztAPIs:[String]?
    
    /// name assocaited with this identity in Ziti.
    ///
    /// Note that this name is unknown until a session with Ziti is active
    @objc public var name:String?
    
    /// CA pool verified as part of enrollment that can be used to establish trust with of the  Ziti controller
    @objc public var ca:String?
    
    /// Request `Ziti` to start this identity in disabled state
    public var startDisabled:Bool? = false
    
    /// Initialize a `ZitiIdentity` given the provided identity infomation
    ///
    /// - Parameters:
    ///     - id: unique identifier of this identity
    ///     - ztAPIs: URLs for accessing Ziti controller API
    ///     - certCNs: common names of certififcates 
    ///     - name: name currently configured for this identity
    ///     - ca: CA pool that can be used to verify trust of the Ziti controller
    @objc public init(id:String, ztAPIs:[String], certCNs:[String]?=nil, name:String?=nil, ca:String?=nil) {
        self.id = id
        self.certCNs = [ id ]
        if let certCNs {
            for cn in certCNs {
                if cn == id { continue }
                self.certCNs?.append(cn)
            }
        }
        self.ztAPI = ztAPIs.first ?? ""
        self.ztAPIs = ztAPIs
        self.name = name
        self.ca = ca
    }
    
    @objc public func getCertCNs() -> [String] {
        return certCNs ?? [self.id]
    }
    
    /// Save this object to a JSON file
    ///
    /// This file can be used to initialize a `Ziti` object.
    ///
    /// - Parameters:
    ///     - initFile: file containing JSON-encoded data representing this object
    ///
    /// - See also:
    ///     - `Ziti.enroll(_:_:)`
    @objc public func save(_ initFile:String) -> Bool {
        guard let data = try? JSONEncoder().encode(self) else {
            log.error("unable to encode data for id: \(id)")
            return false
        }
        
        let url = URL(fileURLWithPath: initFile)
        do { try data.write(to: url, options: .atomic) } catch {
            log.error("unable to write file \(initFile): \(error.localizedDescription)")
            return false
        }
        return true
    }    
}

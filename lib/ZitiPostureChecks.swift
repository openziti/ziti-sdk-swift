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

/// Used for passing context among callbacks and mapping to `Ziti` C SDK function
@objc public class ZitiPostureContext : NSObject {
    let ztx:OpaquePointer, id:UnsafeMutablePointer<Int8>?
    init(_ ztx:OpaquePointer, _ id:UnsafeMutablePointer<Int8>?) {
        self.ztx = ztx
        self.id = id
        super.init()
    }
}

///
/// `Ziti` can be initialized with an instance of this class that implements various posture checks, used to determine if a `Ziti` identity is allowed access to specific services
///
@objc open class ZitiPostureChecks : NSObject {
    
    /// Postture response for MAC address query
    /// 
    /// - Parameters:
    ///     - ctx: posture context
    ///     - macAddresses: array of the mac addresses the host currently can access. Values should be hex strings. `nil` signifies not supported.
    public typealias MacResponse = (_ ctx:ZitiPostureContext, _ macAddresses:[String]) -> Void
    
    /// Postture query for MAC address
    ///
    /// - Parameters:
    ///     - ctx: posture context
    ///     - responseCallback: callback to invoke in response to this query
    public typealias MacQuery = (_ ctx:ZitiPostureContext, _ responseCallback:MacResponse) -> Void
    
    /// Postture response for host domain query
    ///
    /// - Parameters:
    ///     - ctx: posture context
    ///     - domain: Host domain. `nil` signifies not supported.
    public typealias DomainResponse = (_ ctx:ZitiPostureContext, _ domain:String) -> Void
    
    /// Postture query for Domain
    ///
    /// - Parameters:
    ///     - ctx: posture context
    ///     - responseCallback: callback to invoke in response to this query
    public typealias DomainQuery = (_ ctx:ZitiPostureContext, _ responseCallback:DomainResponse) -> Void
    
    /// Postture response for host domain query
    ///
    /// - Parameters:
    ///     - ctx: posture context
    ///     - type: type of operating sytem (e.g., "macOS", "iOS")
    ///     - version: OS version
    ///     - build: OS build. `nil` signifies not supported
    public typealias OsResponse = (_ ctx:ZitiPostureContext, _ type:String, _ version:String, _ build:String) -> Void
    
    /// Postture query for Operating System
    ///
    /// - Parameters:
    ///     - ctx: posture context
    ///     - responseCallback: callback to invoke in response to this query
    public typealias OsQuery = (_ ctx:ZitiPostureContext, _ responseCallback:OsResponse) -> Void
    
    /// Postture response for process query
    ///
    /// - Parameters:
    ///     - ctx: posture context
    ///     - path: path of the process to inspect
    ///     - isRunning: is the process currently running?
    ///     - hash: sha512 hash of the process's binary file
    ///     - signers: sha1 hex string fingerprints of the binary or `nil` if not supported
    public typealias ProcessResponse =
        (_ ctx:ZitiPostureContext, _ path:String, _ isRunning:Bool, _ hash:String, _ signers:[String]) -> Void
    
    /// Postture query for process information
    ///
    /// - Parameters:
    ///     - ctx: posture context
    ///     - responseCallback: callback to invoke in response to this query
    public typealias ProcessQuery = (_ ctx:ZitiPostureContext, _ path:String,  _ responseCallback:ProcessResponse) -> Void
    
    /// Optional support for query of MAC addresses
    @objc public var macQuery:MacQuery? = nil
    
    /// Optional support for query of host domain
    @objc public var domainQuery:DomainQuery? = nil
    
    /// Optional support for query of operating system version
    @objc public var osQuery:OsQuery? = nil
    
    /// Optional support for query of process informaion
    @objc public var processQuery:ProcessQuery? = nil
}

class ZitiMacContext : ZitiPostureContext {
    let cb:ziti_pr_mac_cb
    init(_ ztx:OpaquePointer, _ id:UnsafeMutablePointer<Int8>?, _ cb: @escaping ziti_pr_mac_cb) {
        self.cb = cb
        super.init(ztx, id)
    }
}

// Helper classes for passing around the C SDK callbacks
class ZitiDomainContext : ZitiPostureContext {
    let cb:ziti_pr_domain_cb
    init(_ ztx:OpaquePointer, _ id:UnsafeMutablePointer<Int8>?, _ cb: @escaping ziti_pr_domain_cb) {
        self.cb = cb
        super.init(ztx, id)
    }
}

class ZitiOsContext : ZitiPostureContext {
    let cb:ziti_pr_os_cb
    init(_ ztx:OpaquePointer, _ id:UnsafeMutablePointer<Int8>?, _ cb: @escaping ziti_pr_os_cb) {
        self.cb = cb
        super.init(ztx, id)
    }
}

class ZitiProcessContext : ZitiPostureContext {
    let cb:ziti_pr_process_cb
    init(_ ztx:OpaquePointer, _ id:UnsafeMutablePointer<Int8>?, _ cb: @escaping ziti_pr_process_cb) {
        self.cb = cb
        super.init(ztx, id)
    }
}

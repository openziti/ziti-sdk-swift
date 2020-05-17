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
 
/**
 This is the main entry point for interacting with Ziti.
 
 Provides a Swift-friendly way to access the Ziti C SDK
 
 Configure `Ziti` with a `ZitiIdentity`.  A `ZitiEdentity` can be created by enrolling with `Ziti` using a one-time JWT.  See `Ziti.enroll(jwtFile:enrollCallback`.  The `ZitiIdentity` can also be configured as part of `Ziti.init?(fromFile:)`and other `Ziti`initializers.
 
 `Ziti` uses a loop to process events, similar to`Foudation`'s `Runloop` (though implemented using `libuv`).  Start `Ziti` processing via the `run()` method, which enters
  and infinate loop processing `Ziti` events until `shutdown()` is called.  Tthe `perform()` method supports scheduling work to be run on this thread and can be called safely
  from other threads.
 
 - See also:
    - `ZitiUrlProtocol` for registering a `URLProtocol` for intercepting HTTP and HTTPS calls make using the `URLSession` framework and routing them over a `Ziti` network.
 */
@objc public class Ziti : NSObject, ZitiUnretained {
    private static let log = ZitiLog(Ziti.self)
    private let log = Ziti.log
    
    private var runThread:Thread?
    private var loop = uv_loop_t()
    private var nfCtx:nf_context?
    
    /// Type used for closure called for an operation to be performed on the loop
    public typealias PerformCallback = () -> Void
    private var opsAsyncHandle:UnsafeMutablePointer<uv_async_t>?
    private var opsQueueLock = NSLock()
    private var opsQueue:[PerformCallback] = []
    
    /// Type used for closure called when changes to services are detected or a call to `serviceAvailable()` is made
    ///
    /// - Parameters:
    ///      - svc: the `ziti-sdk-c`'s `ziti_service` that has changed, or nil on error condition
    ///      - status: ZITI_OK, ZITI_SERVICE_UNAVAILABLE, or errorCode on nil `ziti_service`
    public typealias ServiceCallback = (_ svc: UnsafeMutablePointer<ziti_service>?, _ status:Int32) -> Void
    private var serviceCallbacksLock = NSLock()
    private var serviceCallbacks:[ServiceCallback] = []
    
    private var id:ZitiIdentity
    
    // MARK: - Initializers
    
    /// Initialize `Ziti` with a `ZitiIdentity` stored in a JSON file.
    ///
    /// A typical usage of `Ziti` is to enroll using `Ziti.enroll(jwtFile:,enrollCallback)`, store the resulting file on disk,
    /// and use that file for subsequent creations of objects of class `Ziti`.  The `ZitiIdentity` contains the information needed
    /// to access the Keychain for stored identity information (keys and identity certificates).
    ///
    /// - Parameters:
    ///     - fromFile: file containing JSON representation of a `ZitiIdentity`
    ///
    /// - Returns: A `Ziti` object or `nil`on failure to load from file
    @objc public init?(fromFile initFile:String) {
        let url = URL(fileURLWithPath: initFile)
        guard let data = try? Data.init(contentsOf: url) else {
            log.error("unable to load file \(initFile)")
            return nil
        }
        guard let zid = try? JSONDecoder().decode(ZitiIdentity.self, from: data) else {
            log.error("unable to parse file \(initFile)")
            return nil
        }
        self.id = zid
        uv_loop_init(&loop)
        super.init()
    }
    
    /// Initialize `Ziti` with information needed for a`ZitiIdentity`.
    ///
    /// The `ZitiIdentity` contains the information needed to access the Keychain for stored identity information (keys and identity certificates).
    ///
    /// - Parameters:
    ///     - id: Usually the `sub` field from the  one-time enrollment JWT.  Used by `Ziti` to store and retrieve identity-related items in the Keychain`
    ///     - ztAPI: scheme, host, and port used to communicate with Ziti controller
    ///     - name: name assocaited with this identity in Ziti. 
    ///     - caPool: CA pool verified as part of enrollment that can be used to establish trust with of the  Ziti controller
    @objc public init(_ id:String, _ ztAPI:String, name:String?, caPool:String?) {
        self.id = ZitiIdentity(id:id, ztAPI:ztAPI, name:name, ca:caPool)
        uv_loop_init(&loop)
        super.init()
    }
    
    /// Initialize `Ziti` with a`ZitiIdentity`.
    ///
    /// - Parameters:
    ///     - zid: the `ZitiIdentity` containing the information needed to access the Keychain for stored identity information (keys and identity certificates).
    @objc public init(withId zid:ZitiIdentity) {
        self.id = zid
        uv_loop_init(&loop)
        super.init()
    }
    
    /// Remove keys and certificates created during `enroll()` from the keychain
    @objc public func forget() {
        let zkc = ZitiKeychain(tag: id.id)
        
        if let zErr = zkc.deleteKeyPair() {
            log.warn("unable to delete keys for \(id.id) from keychain: \(zErr.localizedDescription)")
        }
        
        if let zErr = zkc.deleteCertificate() {
            log.warn("unable to delete certificate for \(id.id) from keychain: \(zErr.localizedDescription)")
        }
    }
    
    // MARK: - Enrollment
    
    /// Type used for escaping  closure called following an enrollment attempt
    ///
    /// - Parameters:
    ///      - zid: `ZitiIdentity` returned on successful enrollment.  `nil` on failed attempt
    ///      - error: `ZitiError` containing error information on failed enrollment attempt
    public typealias EnrollmentCallback = (_ zid:ZitiIdentity?, _ error:ZitiError?) -> Void
    
    /// Enroll a Ziti identity using a JWT file
    ///
    /// Enrollment consists of parsing the JWT to determins controller address, verifytng the given JWT was signed with the controller's public key,
    /// downloading the CA chain from the controller (to be used as part of establishing trust in future interactions with the controller), generating a
    /// private key (stored in the Keychain), creating a Certificate Signing Request (CSR), sending the CSR to the controller and receiving our signed
    /// certificate.  This certificate is stored in the Keychain and required for future interactions with the controller.
    ///
    /// A `ZitiIdentity` is passed back in the `EnrollmentCallback` that can be stored and using to create an instance of `Ziti`
    ///
    /// - Parameters:
    ///      - jwtFile:  file containing one-time JWT token for enrollment
    ///      - cb: callback called indicating status of enrollment attempt
    @objc public static func enroll( _ jwtFile:String, _ enrollCallback: @escaping EnrollmentCallback) {
        let enroller = ZitiEnroller(jwtFile)
        guard let subj = enroller.getSubj() else {
            let errStr = "unable to extract sub from JWT"
            log.error(errStr, function:"enroll()")
            enrollCallback(nil, ZitiError(errStr))
            return
        }
        
        // Create private key
        let zkc = ZitiKeychain(tag: subj)
        guard let privKey = zkc.createPrivateKey() else {
            let errStr = "unable to generate private key"
            log.error(errStr, function:"enroll()")
            enrollCallback(nil, ZitiError(errStr))
            return
        }
        let pem = zkc.getKeyPEM(privKey)
        
        // Enroll
        enroller.enroll(privatePem: pem) { resp, _, zErr in
            guard let resp = resp, zErr == nil else {
                log.error(String(describing: zErr), function:"enroll()")
                enrollCallback(nil, zErr)
                return
            }
            
            // Store certificate
            let cert = dropFirst("pem:", resp.id.cert)
            guard zkc.storeCertificate(fromPem: cert) == nil else {
                let errStr = "Unable to store certificate\n"
                log.error(errStr, function:"enroll()")
                enrollCallback(nil, ZitiError(errStr))
                return
            }
            
            // Grab CA if specified
            var ca = resp.id.ca
            if let idCa = resp.id.ca {
                ca = dropFirst("pem:", idCa)
            }
            
            let zid = ZitiIdentity(id: subj, ztAPI: resp.ztAPI, ca: ca)
            log.info("Enrolled id:\(subj) with controller:\(zid.ztAPI)", function:"enroll()")
            
            enrollCallback(zid, nil)
        }
    }
    
    // MARK: Ziti operational methods
    
    /// Type used for escaping  closure called follwing initialize of Ziti connectivity
    ///
    /// - Parameters:
    ///      - error: `ZitiError` containing error information on failed initialization attempt
    public typealias InitCallback = (ZitiError?) -> Void
    private var initCallback:InitCallback?
    
    /// Execute a permanant loop processing data from all attached sources (including Ziti)
    ///
    ///  Start `Ziti` processing via this method.  All Ziti processing occurs in the same thread as this call and all callbacks run on this thread.
    ///  Use the `perform()` to schedule work to be run on this thread.   `perform()` can be called safely from other threads.
    ///
    /// - Parameters:
    ///     - initCallback: called when intialization with the Ziti controller is complete
    ///
    /// - See also:
    ///     - runAsync()
    @objc public func run(_ initCallback: @escaping InitCallback) {
        guard let cztAPI = id.ztAPI.cString(using: .utf8) else {
            let errStr = "unable to convert controller URL (ztAPI) to C string"
            log.error(errStr)
            initCallback(ZitiError(errStr))
            return
        }
        
        // Get certificate
        let zkc = ZitiKeychain(tag: id.id)
        let (maybeCert, zErr) = zkc.getCertificate()
        guard let cert = maybeCert, zErr == nil else {
            let errStr = zErr != nil ? zErr!.localizedDescription : "unable to retrieve certificate from keychain"
            log.error(errStr)
            initCallback(zErr ?? ZitiError(errStr))
            return
        }
        let certPEM = zkc.convertToPEM("CERTIFICATE", der: cert)
        
        // Get private key
        guard let privKey = zkc.getPrivateKey() else {
            let errStr = "unable to retrive private key from keychain"
            log.error(errStr)
            initCallback(ZitiError(errStr))
            return
        }
        let privKeyPEM = zkc.getKeyPEM(privKey)
                
        // setup TL
        let caLen = (id.ca == nil ? 0 : id.ca!.count + 1)
        let tls = default_tls_context(id.ca?.cString(using: .utf8), caLen)
        let tlsStat = tls?.pointee.api.pointee.set_own_cert(tls?.pointee.ctx,
                                              certPEM.cString(using: .utf8),
                                              certPEM.count + 1,
                                              privKeyPEM.cString(using: .utf8),
                                              privKeyPEM.count + 1)
        guard tlsStat == 0 else {
            let errStr = "unable to configure TLS, error code: \(tlsStat ?? 0)"
            log.error(errStr)
            initCallback(ZitiError(errStr, errorCode: Int(tlsStat ?? 0)))
            return
        }
        
        // Add opsQueue async handler
        opsAsyncHandle = UnsafeMutablePointer.allocate(capacity: 1)
        opsAsyncHandle?.initialize(to: uv_async_t())
        if uv_async_init(ZitiUrlProtocol.loop, opsAsyncHandle, Ziti.onPerformOps) != 0 {
            let errStr = "unable to init opsAsyncHandle"
            log.error(errStr)
            initCallback(ZitiError(errStr))
            return
        }
        opsAsyncHandle?.pointee.data = self.toVoidPtr()
        opsAsyncHandle?.withMemoryRebound(to: uv_handle_t.self, capacity: 1) {
            uv_unref($0)
        }
                
        // remove comiler warning on cztAPI memory living past the inti call
        let ctrlPtr = UnsafeMutablePointer<Int8>.allocate(capacity: id.ztAPI.count)
        ctrlPtr.initialize(from: cztAPI, count: id.ztAPI.count)
        defer { ctrlPtr.deallocate() } // just needs to live through the call to NF_init_opts
        
        // init NF
        self.initCallback = initCallback
        var nfOpts = nf_options(config: nil,
                                controller: ctrlPtr,
                                tls:tls,
                                config_types: ziti_all_configs,
                                init_cb: Ziti.onInit,
                                service_cb: Ziti.onService,
                                refresh_interval: 30,
                                ctx: self.toVoidPtr())
        
        let initStatus = NF_init_opts(&nfOpts, &loop, self.toVoidPtr())
        guard initStatus == ZITI_OK else {
            let errStr = String(cString: ziti_errorstr(initStatus))
            log.error("unable to initialize Ziti, \(initStatus): \(errStr)", function:"start()")
            initCallback(ZitiError(errStr, errorCode: Int(initStatus)))
            return
        }
        
        // must be done after NF_init...
        //ziti_debug_level = 11
        uv_mbed_set_debug(5, stdout) // TODO: get rid of this...
        
        // Save off reference to current thread and run the loop
        runThread = Thread.current
        runThread?.name = "ziti_uv_loop"
        
        let rStatus = uv_run(&loop, UV_RUN_DEFAULT)
        guard rStatus == 0 else {
            let errStr = String(cString: uv_strerror(rStatus))
            log.error("error running uv loop: \(rStatus) \(errStr)")
            initCallback(ZitiError(errStr, errorCode: Int(rStatus)))
            return
        }
        
        let cStatus = uv_loop_close(&loop)
        if cStatus != 0 {
            let errStr = String(cString: uv_strerror(cStatus))
            log.error("error closing uv loop: \(cStatus) \(errStr)")
            return
        }
    }
    
    /// Create a new thread for `Ziti.run()` and returns
    ///
    /// - Parameters:
    ///     - initCallback: called when intialization with the Ziti controller is complete
    @objc public func runAsync(_ initCallback: @escaping InitCallback) {
        Thread(target: self, selector: #selector(Ziti.run), object: initCallback).start()
    }
    
    /// Shutdown the Ziti processing started via `Ziti.run()`.  This will cause the loop to exit once all scheduled activity on the loop completes
    @objc public func shutdown() {
        perform {
            self.log.info("Ziti shutdown started")
            NF_shutdown(self.nfCtx)
        }
    }
    
    /// Create a ZitiConnection object
    ///
    /// This method will only be able to create connections after `Ziti` has started running (see `run()`)
    ///
    /// - Returns: An intialized `ZitiConnection` or nil on error
    @objc public func createConnection() -> ZitiConnection? {
        guard let nfCtx = self.nfCtx else {
            log.error("invalid (nil) context")
            return nil
        }
        var nfConn:nf_connection?
        NF_conn_init(nfCtx, &nfConn, nil)
        return ZitiConnection(self, nfConn)
    }
    
    /// Get the version of the wrapped Ziti C SDK
    ///
    /// - Returns: tupple of version, revision, buildDate
    public func getCSDKVersion() -> (version:String, revision:String, buildDate:String) {
        guard let vPtr = NF_get_version() else {
            return ("", "", "")
        }
        return (String(cString: vPtr.pointee.version),
                String(cString: vPtr.pointee.revision),
                String(cString: vPtr.pointee.build_date))
    }
    
    /// Get the version of the connected controller
    ///
    /// - Returns: tupple of version, revision, buildDate or ("", "", "") if Ziti is not currently running
    public func getControllerVersion() -> (version:String, revision:String, buildDate:String) {
        guard let nfCtx = self.nfCtx, let vPtr = NF_get_controller_version(nfCtx) else {
            return ("", "", "")
        }
        return (String(cString: vPtr.pointee.version),
                String(cString: vPtr.pointee.revision),
                String(cString: vPtr.pointee.build_date))
    }
    
    /// Retrieve current transfer rates
    ///
    /// Rates are in bytes / second, calculated using 1 minute EWMA
    public func getTransferRates() -> (up:Double, down:Double) {
        var up:Double=0.0, down:Double=0.0
        if let nfCtx = self.nfCtx {
            NF_get_transfer_rates(nfCtx, &up, &down)
        }
        return (up, down)
    }
    
    /// Checks availability of service
    ///
    /// The supplied name is case sensitive. Note that this function is not synchronous
    ///
    /// - Parameters:
    ///     - service: the name of the service to check
    ///     - onServiceAvaialble: callback called with status `ZITI_OK` of `ZITI_SERVICE_NOT_AVAILABLE`
    ///
    @objc public func serviceAvailable(_ service:String, _ onServiceAvailable: @escaping ServiceCallback) {
        perform {
            let req = ServiceAvailableRequest(self, onServiceAvailable)
            let status = NF_service_available(self.nfCtx, service.cString(using: .utf8), Ziti.onServiceAvailable, req.toVoidPtr())
            guard status == ZITI_OK else {
                self.log.error(String(cString: ziti_errorstr(status)))
                return
            }
            self.serviceAvaialbleRequests.append(req)
        }
    }
    
    /// Perform an operation in the context of the Ziti run loop, potentially not until the next iteration of the loop
    ///
    /// Ziti is not threadsafe.  All operations must run on the same thread as `Ziti.run()`.  Use the `perform()` method to execute
    /// the closure on the Ziti thread
    ///
    /// - Parameters:
    ///    - op: Escaping closure that executes on the same thread as `Ziti.run()  `
    @objc public func perform(_ op: @escaping PerformCallback) {
        if Thread.current == runThread {
            op()
        } else {
            opsQueueLock.lock()
            opsQueue.append(op)
            opsQueueLock.unlock()
            uv_async_send(opsAsyncHandle)
        }
    }
    
    /// Register a closure to be called when services are added, changed, or deletes
    ///
    /// These callbacks should be registerd before `Ziti.run()` is execute or the intiali callbacks for the services will be missed
    ///
    /// - Parameters:
    ///     - cb: The closre to be executed
    @objc public func registerServiceCallback(_ cb: @escaping ServiceCallback) {
        serviceCallbacksLock.lock()
        serviceCallbacks.append(cb)
        serviceCallbacksLock.unlock()
    }
        
    // MARK: - Static C Callbacks
    
    static private let onInit:nf_init_cb = { nf_context, status, ctx in
        guard let mySelf = zitiUnretained(Ziti.self, ctx)  else {
            log.wtf("invalid context", function:"onInit()")
            return
        }
        guard status == ZITI_OK else {
            let errStr = String(cString: ziti_errorstr(status))
            log.error(errStr, function:"on_nf_init()")
            mySelf.initCallback?(ZitiError(errStr, errorCode: Int(status)))
            return
        }
        mySelf.nfCtx = nf_context
        mySelf.initCallback?(nil)
    }
    
    static private let onPerformOps:uv_async_cb = { h in
        guard let ctx = h?.pointee.data, let mySelf = zitiUnretained(Ziti.self, ctx)  else {
            log.wtf("invalid context", function:"onPerformOps()")
            return
        }
        
        mySelf.opsQueueLock.lock()
        var opsQueue = mySelf.opsQueue
        mySelf.opsQueue = []
        mySelf.opsQueueLock.unlock()
        
        opsQueue.forEach { op in
            op()
        }
    }
    
    static private let onService:nf_service_cb = { nf, zs, status, ctx in
        guard let mySelf = zitiUnretained(Ziti.self, ctx)  else {
            log.wtf("invalid context", function:"onService()")
            return
        }
        
        if status != ZITI_OK && status != ZITI_SERVICE_UNAVAILABLE {
            log.warn("received status \(status): \(String(cString: ziti_errorstr(status)))", function:"onService()")
        }
        
        mySelf.serviceCallbacksLock.lock()
        mySelf.serviceCallbacks.forEach { cb in
            cb(zs, status)
        }
        mySelf.serviceCallbacksLock.unlock()
    }
    
    static private let onServiceAvailable:nf_service_cb = { nf, zs, status, ctx in
        guard let req = zitiUnretained(ServiceAvailableRequest.self, ctx) else {
            log.wtf("invalid context", function:"onServiceAvaialble()")
            return
        }
        if let ziti = req.ziti {
            ziti.serviceAvaialbleRequests = ziti.serviceAvaialbleRequests.filter { $0 !== req }
        }
        req.cb(zs, status)
    }
    
    // MARK: - Helpers
    
    private static func dropFirst(_ drop:String, _ str:String) -> String {
        var newStr = str
        if newStr.starts(with: drop) {
            newStr = String(newStr.dropFirst(drop.count))
        }
        return newStr
    }
    
    class ServiceAvailableRequest : ZitiUnretained {
        weak var ziti:Ziti?
        let cb:ServiceCallback
        init(_ ziti:Ziti, _ cb: @escaping ServiceCallback) {
            self.ziti = ziti
            self.cb = cb
        }
    }
    var serviceAvaialbleRequests:[ServiceAvailableRequest] = []
}

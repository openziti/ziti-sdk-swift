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
 This is the main entry point for interacting with Ziti, and provides a Swift-friendly way to access the Ziti C SDK
 
 Configure `Ziti` with a `ZitiIdentity`.  A `ZitiIdentity` can be created by enrolling with using a one-time JWT.  See `Ziti.enroll(_:_:)`.  The `ZitiIdentity` can also be configured as part of `Ziti.init(fromFile:)`and other `Ziti`initializers.
 
 `Ziti` uses a loop to process events, similar to`Foudation`'s `Runloop` (though implemented using `libuv`).  Start `Ziti` processing via the `Ziti.run(_:)` method, which enters an infinate loop processing `Ziti` events until `Ziti.shutdown()` is called.  Tthe `Ziti.perform(_:)` method supports scheduling work to be run on this thread and can be called safely from other threads.
 
 - See also:
    - `ZitiIdentity` required to configure Ziti access
    - `Ziti.enroll(_:_:)` create a `ZitiIdentity` by enrolling using a one-time JWT
    - `Ziti.init(fromFile:)` create a `ZitiIdentity` by loading from a JSON file.
    - `ZitiConnection` for accessing or providing Ziti services
    - `ZitiUrlProtocol` for registering a `URLProtocol` for intercepting HTTP and HTTPS calls make using the `URLSession` framework and routing them over a `Ziti` network.
 */
@objc public class Ziti : NSObject, ZitiUnretained {
    private static let log = ZitiLog(Ziti.self)
    private let log = Ziti.log
    
    var loop:UnsafeMutablePointer<uv_loop_t>!
    var privateLoop:Bool
    public var ztx:ziti_context?
    
    // temporary until user data available for posture checks
    static var postureContexts:[ziti_context:Ziti?] = [:]
    
    // This memory is held onto an used by C-SDK.  If not using a private loop we need to make sure these three things
    // stay in memory
    private var tls: UnsafeMutablePointer<tls_context>?
    private var ctrlPtr: UnsafeMutablePointer<Int8>?
    private var nfOpts: ziti_options?
    
    
    /// Type used for escaping  closure called follwing initialize of Ziti connectivity
    ///
    /// - Parameters:
    ///      - error: `ZitiError` containing error information on failed initialization attempt
    public typealias InitCallback = (_ error:ZitiError?) -> Void
    private var initCallback:InitCallback?
    private var postureChecks:ZitiPostureChecks?
    
    /// Type used for escaping  closure called when ZitiEvent is received
    ///
    /// - Parameters:
    ///      - event: `ZitiEvent` containing event information
    public typealias EventCallback = (_ event: ZitiEvent?) -> Void
    private var eventCallbacksLock = NSLock()
    private var eventCallbacks:[(cb:EventCallback, mask:UInt32)] = []
    
    /// Type used for closure called when a call to `serviceAvailable(_:_:)` is made
    ///
    /// - Parameters:
    ///     - ztx: Ziti context
    ///     - svc: the `ziti-sdk-c`'s `ziti_service` that has changed, or nil on error condition
    ///     - status: ZITI_OK, ZITI_SERVICE_UNAVAILABLE, or errorCode on nil `ziti_service`
    public typealias ServiceCallback = (_ ztx:ziti_context? , _ svc: UnsafeMutablePointer<ziti_service>?, _ status:Int32) -> Void
    
    /// Type used for closure called for an operation to be performed on the loop
    public typealias PerformCallback = () -> Void
    private var opsAsyncHandle:UnsafeMutablePointer<uv_async_t>?
    private var opsQueueLock = NSLock()
    private var opsQueue:[PerformCallback] = []
    
    private var connections:[ZitiConnection] = []
    private var connectionsLock = NSLock()
    
    private var id:ZitiIdentity
    
    // MARK: - Initializers
    
    /// Initialize `Ziti` with a `ZitiIdentity` stored in a JSON file.
    ///
    /// A typical usage of `Ziti` is to enroll using `Ziti.enroll(_:_:)`, store the resulting file on disk,
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
        privateLoop = true
        loop = UnsafeMutablePointer<uv_loop_t>.allocate(capacity: 1)
        loop.initialize(to: uv_loop_t())
        uv_loop_init(loop)
        super.init()
        initOpsHandle()
    }
    
    /// Initialize `Ziti` with information needed for a `ZitiIdentity`.
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
        privateLoop = true
        loop = UnsafeMutablePointer<uv_loop_t>.allocate(capacity: 1)
        loop.initialize(to: uv_loop_t())
        uv_loop_init(loop)
        super.init()
        initOpsHandle()
    }
    
    /// Initialize `Ziti` with a `ZitiIdentity`.
    ///
    /// - Parameters:
    ///     - zid: the `ZitiIdentity` containing the information needed to access the Keychain for stored identity information (keys and identity certificates).
    @objc public init(withId zid:ZitiIdentity) {
        self.id = zid
        privateLoop = true
        loop = UnsafeMutablePointer<uv_loop_t>.allocate(capacity: 1)
        loop.initialize(to: uv_loop_t())
        uv_loop_init(loop)
        super.init()
        initOpsHandle()
    }
    
    /// Initilize `Ziti` with an externally supplied `uv_loop`.
    ///
    /// This can be useful when an application needs to manage multiple `ZitiIdentity`s and share a single `uv_loop`
    /// In this scenario, the loop is expected to execute outside of the `run(:_)` method.
    ///
    /// - Parameters:
    ///     - zid: the `ZitiIdentity` containing the information needed to access the Keychain for stored identity information (keys and identity certificates).
    ///     - loop: the externanally supplied `uv_loop`
    ///
    public init(zid:ZitiIdentity, loop:UnsafeMutablePointer<uv_loop_t>) {
        self.id = zid
        self.privateLoop = false
        self.loop = loop
        super.init()
        initOpsHandle()
    }
    
    private func initOpsHandle() {
        opsAsyncHandle = UnsafeMutablePointer.allocate(capacity: 1)
        opsAsyncHandle?.initialize(to: uv_async_t())
        uv_async_init(loop, opsAsyncHandle, Ziti.onPerformOps)
        opsAsyncHandle?.pointee.data = self.toVoidPtr()
        opsAsyncHandle?.withMemoryRebound(to: uv_handle_t.self, capacity: 1) {
            uv_unref($0)
        }
    }
    
    deinit {
        if privateLoop {
            loop.deinitialize(count: 1)
            loop.deallocate()
        }
        opsAsyncHandle?.deinitialize(count: 1)
        opsAsyncHandle?.deallocate()
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
        _ = zkc.deleteKeyPair(silent:true) // certain failure/retry scenarios can cause the key & cert to already exist
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
            _ = zkc.deleteCertificate(silent: true)
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
            log.info("Enrolled id:\(subj) with controller: \(zid.ztAPI)", function:"enroll()")
            
            enrollCallback(zid, nil)
        }
    }
    
    // MARK: Ziti Operational Methods
    
    /// Convienience method for calling `run(_:_)` with `nil` posture check support
    ///
    /// - Parameters:
    ///     - initCallback: called when intialization with the Ziti controller is complete
    ///
    /// - See also:
    ///     - `run(_:_)`
    ///     - `runAsync(_:)`
    @objc public func run(_ initCallback: @escaping InitCallback) {
        run(nil,  initCallback)
    }
    
    /// Execute a permanant loop processing data from all attached sources (including Ziti)
    ///
    /// Start `Ziti` processing via this method.  All Ziti processing occurs in the same thread as this call and all callbacks run on this thread.
    /// Use the `perform(_:)` to schedule work to be run on this thread.   `perform(_:)` can be called safely from other threads.
    ///
    /// Note that if a `uv_loop` is specified during `Ziti` initialization, running the loop is expected to occur outside of this call.  In this scenario,
    /// this method initializes Ziti for connections using the configured `ZitiIdentity` and blocks until the calling thread is cancelled.
    ///
    /// - Parameters:
    ///     - postureChecks: provide (optional) support for posture checks
    ///     - initCallback: called when intialization with the Ziti controller is complete
    ///
    /// - See also:
    ///     - `runAsync(_:)`
    @objc public func run(_ postureChecks:ZitiPostureChecks?, _ initCallback: @escaping InitCallback) {
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
        
        // setup TLS
        let caLen = (id.ca == nil ? 0 : id.ca!.count + 1)
        tls = default_tls_context(id.ca?.cString(using: .utf8), caLen)
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
                
        // remove compiler warning on cztAPI memory living past the inti call
        ctrlPtr = UnsafeMutablePointer<Int8>.allocate(capacity: id.ztAPI.count + 1)
        ctrlPtr!.initialize(from: cztAPI, count: id.ztAPI.count + 1)
        
        // init NF
        self.initCallback = initCallback
        self.postureChecks = postureChecks
        
        nfOpts = ziti_options(config: nil,
                                controller: ctrlPtr,
                                tls:tls,
                                config_types: ziti_all_configs,
                                refresh_interval: 30,
                                metrics_type: EWMA_1m,
                                router_keepalive: 5,
                                pq_mac_cb: Ziti.onMacQuery,
                                pq_os_cb:  Ziti.onOsQuery,
                                pq_process_cb: Ziti.onProcessQuery,
                                pq_domain_cb: Ziti.onDomainQuery,
                                app_ctx: self.toVoidPtr(),
                                events: ZitiContextEvent.rawValue | ZitiRouterEvent.rawValue | ZitiServiceEvent.rawValue,
                                event_cb: Ziti.onEvent)
        
        let initStatus = ziti_init_opts(&(nfOpts!), loop, self.toVoidPtr())
        guard initStatus == ZITI_OK else {
            let errStr = String(cString: ziti_errorstr(initStatus))
            log.error("unable to initialize Ziti, \(initStatus): \(errStr)", function:"start()")
            initCallback(ZitiError(errStr, errorCode: Int(initStatus)))
            return
        }
        
        // set log level
        ZitiLog.setLogLevel(.INFO)
        
        // Save off reference to current thread and run the loop
        if privateLoop {
            Thread.current.name = "ziti_uv_loop_private"
            
            let rStatus = uv_run(loop, UV_RUN_DEFAULT)
            guard rStatus == 0 else {
                let errStr = String(cString: uv_strerror(rStatus))
                log.error("error running uv loop: \(rStatus) \(errStr)")
                initCallback(ZitiError(errStr, errorCode: Int(rStatus)))
                return
            }
            log.info("uv loop complete with status 0")
            
            let cStatus = uv_loop_close(loop)
            if cStatus != 0 {
                let errStr = String(cString: uv_strerror(cStatus))
                log.error("error closing uv loop: \(cStatus) \(errStr)")
                return
            }
        }
    }
    
    // need to wrap initCallback in NSObject to pass through selector
    class SelectorArg : NSObject {
        let initCallback:InitCallback
        var postureChecks:ZitiPostureChecks?
        init(_ postureChecks:ZitiPostureChecks?, _ initCallback: @escaping InitCallback) {
            self.postureChecks = postureChecks
            self.initCallback = initCallback
        }
    }
    @objc func runThreadWrapper(_ sa:SelectorArg) {
        run(sa.postureChecks, sa.initCallback)
    }
    
    /// `Create a new thread for `run(_:)` and return
    ///
    /// - Parameters:
    ///     - initCallback: called when intialization with the Ziti controller is complete
    @objc public func runAsync(_ initCallback: @escaping InitCallback) {
        let arg = SelectorArg(nil, initCallback)
        Thread(target: self, selector: #selector(Ziti.runThreadWrapper), object: arg).start()
    }
    
    /// `Create a new thread for `run(_:)` and return
    ///
    /// - Parameters:
    ///     - postureChecks:provide (optional) support for posture checking
    ///     - initCallback: called when intialization with the Ziti controller is complete
    @objc public func runAsync(_ postureChecks:ZitiPostureChecks?, _ initCallback: @escaping InitCallback) {
        let arg = SelectorArg(postureChecks, initCallback)
        Thread(target: self, selector: #selector(Ziti.runThreadWrapper), object: arg).start()
    }
    
    /// Shutdown the Ziti processing started via `run(_:)`.  This will cause the loop to exit once all scheduled activity on the loop completes
    @objc public func shutdown() {
        perform {
            self.log.info("Ziti shutdown started")
            ziti_shutdown(self.ztx)
        }
    }
    
    /// Create a `ZitiConnection` object
    ///
    /// This method will only be able to create connections after `Ziti` has started running (see `run(_:)`)
    ///
    /// - Returns: An intialized `ZitiConnection` or nil on error
    @objc public func createConnection() -> ZitiConnection? {
        guard let ztx = self.ztx else {
            log.error("invalid (nil) context")
            return nil
        }
        var zConn:ziti_connection?
        ziti_conn_init(ztx, &zConn, nil)
        
        let zc = ZitiConnection(self, zConn)
        retainConnection(zc)
        return zc
    }
    func retainConnection(_ zc:ZitiConnection) {
        connectionsLock.lock()
        connections.append(zc)
        connectionsLock.unlock()
    }
    func releaseConnection(_ zc:ZitiConnection) {
        connectionsLock.lock()
        connections = connections.filter { $0 !== zc }
        connectionsLock.unlock()
    }
    
    /// Get the version of the wrapped Ziti C SDK
    ///
    /// - Returns: tuple  of version, revision, buildDate
    public func getCSDKVersion() -> (version:String, revision:String, buildDate:String) {
        guard let vPtr = ziti_get_version() else {
            return ("", "", "")
        }
        return (String(cString: vPtr.pointee.version),
                String(cString: vPtr.pointee.revision),
                String(cString: vPtr.pointee.build_date))
    }
    
    /// Get the version of the connected controller
    ///
    /// - Returns: tuple of version, revision, buildDate or ("", "", "") if Ziti is not currently running
    public func getControllerVersion() -> (version:String, revision:String, buildDate:String) {
        guard let ztx = self.ztx, let vPtr = ziti_get_controller_version(ztx) else {
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
        if let ztx = self.ztx {
            ziti_get_transfer_rates(ztx, &up, &down)
        }
        return (up, down)
    }
    
    /// Output debugging information to standard out
    ///
    /// This method must be called in an interation of the loop
    @objc public func dump() {
        ziti_dump(ztx)
    }
    
    /// Checks availability of service
    ///
    /// The supplied name is case sensitive. Note that this function is not synchronous
    ///
    /// - Parameters:
    ///     - service: the name of the service to check
    ///     - onServiceAvaialble: callback called with status `ZITI_OK` of `ZITI_SERVICE_NOT_AVAILABLE`
    public func serviceAvailable(_ service:String, _ onServiceAvailable: @escaping ServiceCallback) {
        perform {
            let req = ServiceAvailableRequest(self, onServiceAvailable)
            let status = ziti_service_available(self.ztx, service.cString(using: .utf8), Ziti.onServiceAvailable, req.toVoidPtr())
            guard status == ZITI_OK else {
                self.log.error(String(cString: ziti_errorstr(status)))
                return
            }
            self.serviceAvaialbleRequests.append(req)
        }
    }
    
    /// Perform an operation in an upcoming iteration of the loop
    ///
    /// Ziti is not threadsafe.  All operations must run on the same thread as `run(_:)`.  Use the `perform(_:)` method to execute
    /// the operation on the Ziti thread
    ///
    /// - Parameters:
    ///    - op: Escaping closure that executes on the same thread as `run(_:)  `
    @objc public func perform(_ op: @escaping PerformCallback) {
        opsQueueLock.lock()
        opsQueue.append(op)
        opsQueueLock.unlock()
        uv_async_send(opsAsyncHandle)
    }
    
    /// Register a closure to be called when events are received
    ///
    /// These callbacks should be registerd before `run(_:)` is executed or the intiali events will be missed
    ///
    /// - Parameters:
    ///     - cb: The closre to be executed
    public func registerEventCallback(_ cb: @escaping EventCallback, _ mask:UInt32=0xffff) {
        eventCallbacksLock.lock()
        eventCallbacks.append((cb:cb, mask:mask))
        eventCallbacksLock.unlock()
    }
        
    // MARK: - Static C Callbacks
    
    static private let onEvent:ziti_event_cb = { ztx, cEvent in
        guard let ctx = ziti_app_ctx(ztx), let mySelf = zitiUnretained(Ziti.self, ctx) else {
            log.wtf("invalid context", function:"onEvent()")
            return
        }
        guard let cEvent = cEvent else {
            log.wtf("invalid event", function:"onEvent()")
            return
        }
        
        // always update zid name...
        if let czid = ziti_get_identity(ztx) {
            let name = String(cString: czid.pointee.name)
            if mySelf.id.name != name {
                log.info("zid name: \(name)", function:"onEvent()")
                mySelf.id.name = name
            }
        }
        
        // first time..
        if let ztx = ztx, mySelf.ztx == nil {
            mySelf.ztx = ztx
            Ziti.postureContexts[ztx] = mySelf
            mySelf.initCallback?(nil)
        }
        
        // send the event...
        let event = ZitiEvent(mySelf, cEvent)
        log.debug(event.debugDescription, function:"onEvent()")
        
        mySelf.eventCallbacksLock.lock()
        mySelf.eventCallbacks.forEach { listener in
            let mask = listener.mask
            if mask & event.type.rawValue != 0 {
                listener.cb(event)
            }
        }
        mySelf.eventCallbacksLock.unlock()
    }
    
    static private let onMacQuery:ziti_pq_mac_cb = { ztx, id, cb in
        guard let ztx = ztx, let id = id, let cb = cb, let mySelf = Ziti.postureContexts[ztx] else {
            log.wtf("invalid context", function:"onMacQuery()")
            return
        }
        guard let query = mySelf?.postureChecks?.macQuery else {
            log.warn("query not configured", function: "onMacQuery()")
            cb(ztx, id, nil, 0)
            return
        }
        query(ZitiMacContext(ztx, id, cb), Ziti.onMacResponse)
    }
    
    static private let onMacResponse:ZitiPostureChecks.MacResponse = { ctx, macArray in
        let macCtx = ctx as! ZitiMacContext
        
        guard let mySelf = Ziti.postureContexts[ctx.ztx] else {
            log.wtf("invalid context", function:"onMacResponse()")
            return
        }
        guard let macArray = macArray else {
            mySelf?.perform {
                macCtx.cb(macCtx.ztx, ctx.id, nil, 0)
            }
            return
        }
        
        mySelf?.perform {
            withArrayOfCStrings(macArray) { arr in
                let cp = copyStringArray(arr, Int32(arr.count))
                macCtx.cb(macCtx.ztx, ctx.id, cp, Int32(macArray.count))
                freeStringArray(cp)
            }
        }
    }
    
    static private let onOsQuery:ziti_pq_os_cb = { ztx, id, cb in
        guard let ztx = ztx, let id = id, let cb = cb, let mySelf = Ziti.postureContexts[ztx] else {
            log.wtf("invalid context", function:"onOsQuery()")
            return
        }
        guard let query = mySelf?.postureChecks?.osQuery else {
            log.warn("query not configured", function: "onOsQuery()")
            cb(ztx, id, nil, nil, nil)
            return
        }
        query(ZitiOsContext(ztx, id, cb), Ziti.onOsResponse)
    }
    
    static private let onOsResponse:ZitiPostureChecks.OsResponse = { ctx, type, version, build in
        let osCtx = ctx as! ZitiOsContext
        guard let mySelf = Ziti.postureContexts[ctx.ztx] else {
            log.wtf("invalid context", function:"onOsResponse()")
            return
        }
        
        mySelf?.perform {
            // C SDK didn't use `const` for strings, so need to copy 'em
            let cType = type != nil ? copyString(type!.cString(using: .utf8)) : nil
            let cVersion = version != nil ? copyString(version!.cString(using: .utf8)) : nil
            let cBuild = build != nil ? copyString(build!.cString(using: .utf8)) : nil
            
            osCtx.cb(osCtx.ztx, osCtx.id, cType, cVersion,  cBuild)
            
            freeString(cType)
            freeString(cVersion)
            freeString(cBuild)
        }
    }
    
    static private let onProcessQuery:ziti_pq_process_cb = { ztx, id, path, cb in
        guard let ztx = ztx, let id = id, let cb = cb, let mySelf = Ziti.postureContexts[ztx] else {
            log.wtf("invalid context", function:"onProcessQuery()")
            return
        }
        guard let query = mySelf?.postureChecks?.processQuery else {
            log.warn("query not configured", function: "onProcessQuery()")
            let cId = copyString(id)
            cb(ztx, cId, nil, false, nil, nil, 0)
            freeString(cId)
            return
        }
        
        let strPath = path != nil ? String(cString: path!) : ""
        query(ZitiProcessContext(ztx, id, cb), strPath, Ziti.onProcessResponse)
    }
    
    static private let onProcessResponse:ZitiPostureChecks.ProcessResponse = { ctx, path, isRunning, hash, signers in
        let pCtx = ctx as! ZitiProcessContext
        guard let mySelf = Ziti.postureContexts[ctx.ztx] else {
            log.wtf("invalid context", function:"onProcessResponse()")
            return
        }
                
        mySelf?.perform {
            // C SDK didn't use `const` for strings, so need to copy 'em
            let cPath = copyString(path.cString(using: .utf8))
            let cHash = hash != nil ? copyString(hash!.cString(using: .utf8)) : nil
            
            if let signers = signers {
                withArrayOfCStrings(signers) { arr in
                    let cp = copyStringArray(arr, Int32(arr.count))
                    pCtx.cb(pCtx.ztx, ctx.id, cPath, isRunning, cHash, cp, Int32(signers.count))
                    freeStringArray(cp)
                }
            } else {
                pCtx.cb(pCtx.ztx, pCtx.id, cPath, isRunning, cHash, nil, 0)
            }
                    
            freeString(cPath)
            freeString(cHash)
        }
    }
    
    static private let onDomainQuery:ziti_pq_domain_cb = { ztx, id, cb in
        guard let ztx = ztx, let id = id, let cb = cb, let mySelf = Ziti.postureContexts[ztx] else {
            log.wtf("invalid context", function:"onDomainQuery()")
            return
        }
        guard let query = mySelf?.postureChecks?.domainQuery else {
            log.warn("query not configured", function: "onDomainQuery()")
            cb(ztx, id, nil)
            return
        }
        query(ZitiDomainContext(ztx, id, cb), Ziti.onDomainResponse)
    }
    
    static private let onDomainResponse:ZitiPostureChecks.DomainResponse = { ctx, domain in
        let dCtx = ctx as! ZitiDomainContext
        guard let mySelf = Ziti.postureContexts[ctx.ztx] else {
            log.wtf("invalid context", function:"onDomainResponse()")
            return
        }
                
        mySelf?.perform {
            // C SDK didn't use `const` for strings, so need to copy 'em
            let cDomain = domain != nil ? copyString(domain!.cString(using: .utf8)) : nil
            dCtx.cb(dCtx.ztx, dCtx.id, cDomain)
            freeString(cDomain)
        }
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
    
    static private let onServiceAvailable:ziti_service_cb = { ztx, zs, status, ctx in
        guard let req = zitiUnretained(ServiceAvailableRequest.self, ctx) else {
            log.wtf("invalid context", function:"onServiceAvaialble()")
            return
        }
        if let ziti = req.ziti {
            ziti.serviceAvaialbleRequests = ziti.serviceAvaialbleRequests.filter { $0 !== req }
        }
        req.cb(ztx, zs, status)
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

// from: https://github.com/apple/swift/blob/dfc3933a05264c0c19f7cd43ea0dca351f53ed48/stdlib/private/SwiftPrivate/SwiftPrivate.swift#L68
func withArrayOfCStrings<R>(
  _ args: [String],
  _ body: ([UnsafeMutablePointer<CChar>?]) -> R
) -> R {
  let argsCounts = Array(args.map { $0.utf8.count + 1 })
  let argsOffsets = [ 0 ] + scan(argsCounts, 0, +)
  let argsBufferSize = argsOffsets.last!

  var argsBuffer: [UInt8] = []
  argsBuffer.reserveCapacity(argsBufferSize)
  for arg in args {
    argsBuffer.append(contentsOf: arg.utf8)
    argsBuffer.append(0)
  }

  return argsBuffer.withUnsafeMutableBufferPointer {
    (argsBuffer) in
    let ptr = UnsafeMutableRawPointer(argsBuffer.baseAddress!).bindMemory(
      to: CChar.self, capacity: argsBuffer.count)
    var cStrings: [UnsafeMutablePointer<CChar>?] = argsOffsets.map { ptr + $0 }
    cStrings[cStrings.count - 1] = nil
    return body(cStrings)
  }
}

// from: https://github.com/apple/swift/blob/dfc3933a05264c0c19f7cd43ea0dca351f53ed48/stdlib/private/SwiftPrivate/SwiftPrivate.swift#L28
func scan<
  S : Sequence, U
>(_ seq: S, _ initial: U, _ combine: (U, S.Iterator.Element) -> U) -> [U] {
  var result: [U] = []
  result.reserveCapacity(seq.underestimatedCount)
  var runningResult = initial
  for element in seq {
    runningResult = combine(runningResult, element)
    result.append(runningResult)
  }
  return result
}

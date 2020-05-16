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
 * URLProtocol` that intercepts `http` and `https` URL requests and routes them over the `Ziti` overlay as configured in your `Ziti` controller.
 *
 * Call the `ZitiUrlProtocol.start()`method to register this `URLProtocol` and start the background processing thread for `Ziti` requests.
 */
@objc public class ZitiUrlProtocol: URLProtocol, ZitiUnretained {
    private static let log = ZitiLog(ZitiUrlProtocol.self)
    private let log = ZitiUrlProtocol.log
    
    var started = false
    var stopped = false
    var finished = false
    
    var req:UnsafeMutablePointer<um_http_req_t>? = nil
    var resp:HTTPURLResponse?
    
    var clientThread:Thread? // Thread that calls start/stopLoading, handles client notifications
    var modes:[String] = []
    
    // queue requests for uv_async_send (start/stop loading)
    // (also servs to hold the unretained reference to self used for uv callbacks until we're done with it)
    static let reqsLock = NSLock()
    static var reqs:[ZitiUrlProtocol] = []
    
    static var nf_opts:nf_options?
    static var nf_context:nf_context?
    static var nf_init_cond:NSCondition?
    static var nf_init_complete = false
    static var tls_context:UnsafeMutablePointer<tls_context>?
    
    static var loop:UnsafeMutablePointer<uv_loop_t>!
    
    // Usafe pointers since we need to cast 'em
    static var async_start_h = uv_async_t()
    static var async_stop_h = uv_async_t()
    
    static let tunCfgType = "ziti-tunneler-client.v1".cString(using: .utf8)!
    static let urlCfgType = "ziti-url-client.v1".cString(using: .utf8)!
    
    static var interceptsLock = NSLock()
    static var intercepts:[String:ZitiIntercept] = [:]
    
    static var idleTime:Int = 0;
    
    // MARK: - Register and start
    /**
     * Registers this protocol via `URLProtocol.registerClass` and starts the background thread for processing `Ziti` requests.
     *
     * - Returns: `true` on success
     *
     * - Parameters:
     *   - blocking: Wait until Ziti is fully initialized before registering as URLProtocol (recommended). Default=true
     *   - waitFor: TimeInterval to wait for Ziti to initialize before considering it an error condition. Default=10.0
     *   - idleTime: Time, in miliiseconds,  client attempts to keep-alive an idle connection before allowing it to close. Default=10000
     *
     * Note that in some cases `ZitiUrlProtocol` will beed to be configured in your `URLSession`'s configuration ala:
     *
     * ```
     * let configuration = URLSessionConfiguration.default
     * configuration.protocolClasses?.insert(ZitiUrlProtocol.self, at: 0)
     * urlSession = URLSession(configuration:configuration)
     * ```
     */
    @objc public class func start(
        _ blocking:Bool=true, _ waitFor:TimeInterval=TimeInterval(10.0), _ idleTime:Int=10000) -> Bool {
        
        loop = UnsafeMutablePointer<uv_loop_t>.allocate(capacity: 1)
        loop.initialize(to: uv_loop_t())
                
        let iStatus = uv_loop_init(loop)
        guard iStatus == 0 else {
            let errStr = String(cString: uv_strerror(iStatus))
            log.error("error starting uv loop: \(iStatus) \(errStr)")
            return false
        }
        
        ZitiUrlProtocol.idleTime = idleTime
        
        // condition for blocking if requested
        ZitiUrlProtocol.nf_init_cond = blocking ? NSCondition() : nil
        
        // Init the start/stop async send handles
        if uv_async_init(ZitiUrlProtocol.loop, &async_start_h, ZitiUrlProtocol.on_async_start) != 0 {
            log.error("unable to init async_start_h")
            return false
        }
        
        if uv_async_init(ZitiUrlProtocol.loop, &async_stop_h, ZitiUrlProtocol.on_async_stop) != 0 {
            log.error("unable to init async_stop_h")
            return false
        }
        
        // NF_init... TODO: whole enrollment dance (and use of keychain...)
        guard let cfgPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".netfoundry/id.json", isDirectory: false).path.cString(using: .utf8) else {
            log.error("unable to find Ziti identity file")
            return false
        }
        log.info("ziti id file: \(String(cString: cfgPath))", function:"start()")
        
        let cfgPtr = UnsafeMutablePointer<Int8>.allocate(capacity: cfgPath.count)
        cfgPtr.initialize(from: cfgPath, count: cfgPath.count)
        defer { cfgPtr.deallocate() } // just needs to live through call to NF_init_opts
        
        ZitiUrlProtocol.nf_opts = nf_options(config: cfgPtr,
                                             controller: nil,
                                             tls:nil,
                                             config_types: ziti_all_configs,
                                             init_cb: ZitiUrlProtocol.on_nf_init,
                                             service_cb: ZitiUrlProtocol.on_nf_service,
                                             refresh_interval: 30,
                                             ctx: nil)
        
        let initStatus = NF_init_opts(&(ZitiUrlProtocol.nf_opts!), ZitiUrlProtocol.loop, nil)
        guard initStatus == ZITI_OK else {
            let errStr = String(cString: ziti_errorstr(initStatus))
            log.error("unable to initialize Ziti, \(initStatus): \(errStr)", function:"start()")
            return false
        }
        
        // must be done after NF_init...
        //ziti_debug_level = 11
        uv_mbed_set_debug(5, stdout)
        
        // start thread for uv_loop
        let t = Thread(target: self, selector: #selector(ZitiUrlProtocol.doLoop), object: nil)
        t.name = "ziti_uv_loop"
        t.start()
        
        if let cond = ZitiUrlProtocol.nf_init_cond {
            cond.lock()
            while blocking && !ZitiUrlProtocol.nf_init_complete {
                if !cond.wait(until: Date(timeIntervalSinceNow: waitFor))  {
                    log.error("timed out waiting for Ziti intialization", function:"start()")
                    cond.unlock()
                    return false
                }
            }
            cond.unlock()
        }
        return true
    }
    
    @objc private class func doLoop() {
        
        let rStatus = uv_run(loop, UV_RUN_DEFAULT)
        guard rStatus == 0 else {
            let errStr = String(cString: uv_strerror(rStatus))
            log.error("error starting uv loop: \(rStatus) \(errStr)")
            return
        }
        
        let cStatus = uv_loop_close(loop)
        if cStatus != 0 {
            let errStr = String(cString: uv_strerror(cStatus))
            log.error("error closing uv loop: \(cStatus) \(errStr)")
            return
        }
        
        loop.deinitialize(count: 1)
        loop.deallocate()
    }
    
    //
    // MARK: - URLProtocol
    //
    override init(request: URLRequest, cachedResponse: CachedURLResponse?, client: URLProtocolClient?) {
        super.init(request: request, cachedResponse: cachedResponse, client: client)
        log.debug("init \(self), Thread: \(String(describing: Thread.current.name))")
    }
    
    deinit {
        log.debug("deinit \(self), Thread: \(String(describing: Thread.current.name))")
    }
    
    public override class func canInit(with request: URLRequest) -> Bool {
        var canIntercept = false;
        if let url = request.url, let scheme = url.scheme, let host = url.host {
            var port = url.port
            if port == nil { port = (scheme == "https") ? 443 : 80 }
            let key = "\(scheme)://\(host):\(port!)"
            
            ZitiUrlProtocol.interceptsLock.lock()
            if ZitiUrlProtocol.intercepts[key] != nil {
                canIntercept = true
            }
            ZitiUrlProtocol.interceptsLock.unlock()
        }
        log.info("*-*-*-*-* is\(canIntercept ? "" : " NOT") intercepting \(request.debugDescription)")
        return canIntercept
    }
    
    public override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }
    
    public override func startLoading() {
        
        // client callbacks need to run in client thread in any of its modes
        clientThread = Thread.current
        modes.append(RunLoop.Mode.default.rawValue)
        let cm = RunLoop.current.currentMode?.rawValue
        if cm != nil && cm! != RunLoop.Mode.default.rawValue {
            modes.append(cm!)
        }
        
        // queue the request for processing on the uv_loop
        ZitiUrlProtocol.reqsLock.lock()
        started = false
        ZitiUrlProtocol.reqs.append(self)
        ZitiUrlProtocol.reqsLock.unlock()
        
        // run the um_http code via async_send to avoid potential race condition
        if uv_async_send(&ZitiUrlProtocol.async_start_h) != 0 {
            log.error("request \(request) queued, but unable to trigger async send")
            return
        }
    }
    
    public override func stopLoading() {
        if uv_async_send(&ZitiUrlProtocol.async_stop_h) != 0 {
            log.error("request \(request) queued, but unable to trigger async send")
            return
        }
    }
        
    //
    // MARK: - um_http callbacks
    //
    static private let on_async_start:uv_async_cb = { h in
        
        // Grab any that are queued and not yet started
        ZitiUrlProtocol.reqsLock.lock()
        var reqs = ZitiUrlProtocol.reqs.filter { !($0.started) }
        ZitiUrlProtocol.reqsLock.unlock()
        
        // Send queued requests
        reqs.forEach { zup in
            zup.started = true
            let urlStr = zup.getUrlString()
            
            ZitiUrlProtocol.interceptsLock.lock()
            if var intercept = ZitiUrlProtocol.intercepts[urlStr] {
                zup.req = intercept.createRequest(zup, zup.getUrlPath(),
                                                  ZitiUrlProtocol.on_http_resp,
                                                  ZitiUrlProtocol.on_http_body,
                                                  zup.toVoidPtr())
            }
            ZitiUrlProtocol.interceptsLock.unlock()
        }
    }
    
    static private let on_http_resp:um_http_resp_cb = { resp, ctx in
        guard let resp = resp, let mySelf = zitiUnretained(ZitiUrlProtocol.self, ctx) else {
            log.wtf("unable to decode context")
            return
        }
        guard let reqUrl = mySelf.request.url else {
            log.wtf("unable to determine request URL")
            return
        }
        
        var hdrMap:[String:String] = [:]
        for i in 0..<resp.pointee.nh {
            let hdr = resp.pointee.headers[Int(i)]
            hdrMap[String(cString: hdr.name)] = String(cString: hdr.value)
        }
                        
        // On TLS handshake error getting a negative response code (-53), notifyDidReceive
        // nothing, so we end up waiting for timeout. So notifyDidFailWithError instead...
        let code = Int(resp.pointee.code)
        guard code > 0 else {
            let str = String(cString: uv_strerror(Int32(code)))
            log.error(str)
            let err = ZitiError(str, errorCode: code)
            mySelf.notifyDidFailWithError(ZitiError(str, errorCode: code))
            return
        }
        
        // attempt to follow re-directs
        var wasRedirected = false
        if code >= 300 && code <= 308 && code != 304 && code != 305 {
            if let location = hdrMap["Location"] {
                if let url = URL(string: location, relativeTo: mySelf.request.url) {
                    var newRequest = URLRequest(url: url)
                    newRequest.httpMethod = (code == 303 ? "GET" : mySelf.request.httpMethod)
                    newRequest.allHTTPHeaderFields = mySelf.request.allHTTPHeaderFields
                    newRequest.httpBody = mySelf.request.httpBody
                    
                    if var origResp = HTTPURLResponse(
                        url: url,
                        statusCode: Int(resp.pointee.code),
                        httpVersion: nil,
                        headerFields: hdrMap) {
                        
                        wasRedirected = true
                        mySelf.notifyWasRedirectedTo(newRequest, origResp)
                    }
                    
                }
            }
        }
        
        if !wasRedirected {
            mySelf.resp = HTTPURLResponse(url: reqUrl,
                                          statusCode: code,
                                          httpVersion: nil, // "HTTP/" + String(cString: resp.pointee.http_version)
                                          headerFields: hdrMap)
            guard let httpResp = mySelf.resp else {
                log.error("unable create response object for \(reqUrl)")
                return
            }
            mySelf.notifyDidReceive(httpResp)
        }
    }
    
    static private let on_http_body:um_http_body_cb = { req, body, len in
        guard let req = req, let mySelf = zitiUnretained(ZitiUrlProtocol.self ,req.pointee.data) else {
            log.wtf("unable to decode context")
            return
        }
        
        if uv_errno_t(Int32(len)) == UV_EOF {
            mySelf.notifyDidFinishLoading()
            mySelf.finished = true
        } else if len < 0 {
            let str = String(cString: uv_strerror(Int32(len)))
            let err = ZitiError(str, errorCode: len)
            mySelf.notifyDidFailWithError(err)
        } else {
            let data = Data(bytes: body!, count: len)
            mySelf.notifyDidLoad(data)
            mySelf.finished = true
        }
        
        // Filter out all that are stopped and finished
        // see also on_async_stop()
        ZitiUrlProtocol.reqsLock.lock()
        ZitiUrlProtocol.reqs = ZitiUrlProtocol.reqs.filter { !($0.stopped && $0.finished) }
        ZitiUrlProtocol.reqsLock.unlock()
    }
    
    static private let on_async_stop:uv_async_cb = { h in
        
        // We don't want to call um_http_close since we would rather just keep
        // using the um_http_t (e.g., for the next startLoading() for this server, especially
        // when http keep-alive is > 0). Also, there's no close callback on um_http_close,
        // so even then might be tough to know...
        //
        // Removing the ZitiUrlProtol from the reqs array here could cause an issue where
        // we keep getting callbacks from um_http after the ZitiUrlProtocol instance has
        // been released.
        //
        // So, we'll synchronize releasing the ZitiUrlProtocol only after stopLoading() *and*
        // on_http_body() indicates we won't get any more um_http callback.
        ZitiUrlProtocol.reqsLock.lock()
        ZitiUrlProtocol.reqs.forEach { zup in
            if zup.started { zup.stopped = true }
        }
        ZitiUrlProtocol.reqs = ZitiUrlProtocol.reqs.filter { !($0.stopped && $0.finished) }
        ZitiUrlProtocol.reqsLock.unlock()
    }
    
    //
    // MARK: - Client Notifications
    // Methods for forcing the client callbacks to run on the client thread
    // when called from uv_loop callbacks
    //
    @objc private func notifyDidFinishLoadingSelector(_ arg:Any?) {
        client?.urlProtocolDidFinishLoading(self)
    }
    private func notifyDidFinishLoading() {
        performOnClientThread(#selector(notifyDidFinishLoadingSelector), nil)
    }
    
    @objc private func notifyDidFailWithErrorSelector(_ err:Error) {
        client?.urlProtocol(self, didFailWithError: err)
    }
    private func notifyDidFailWithError(_ error:Error) {
        performOnClientThread(#selector(notifyDidFailWithErrorSelector), error)
    }
    
    @objc private func notifyDidLoadSelector(_ data:Data) {
        client?.urlProtocol(self, didLoad: data)
    }
    private func notifyDidLoad(_ data:Data) {
        performOnClientThread(#selector(notifyDidLoadSelector), data)
    }
    
    @objc private func notifyDidReceiveSelector(_ resp:HTTPURLResponse) {
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
    }
    private func notifyDidReceive(_ resp:HTTPURLResponse) {
        performOnClientThread(#selector(notifyDidReceiveSelector), resp)
    }
    
    @objc private func notifyWasRedirectedToSelector(_ arg:[Any]) {
        guard let req = arg[0] as? URLRequest, let resp = arg[1] as? URLResponse else { return }
        client?.urlProtocol(self, wasRedirectedTo: req, redirectResponse: resp)
    }
    private func notifyWasRedirectedTo(_ req:URLRequest, _ resp:URLResponse) {
        performOnClientThread(#selector(notifyWasRedirectedToSelector), [req, resp])
    }
    
    private func performOnClientThread(_ aSelector:Selector, _ arg:Any?) {
        perform(aSelector, on: clientThread!, with:arg, waitUntilDone:false, modes:modes)
    }
    
    // MARK: NF_ziti callbacks
    static private let on_nf_init:nf_init_cb = { nf_context, status, ctx in
        guard status == ZITI_OK else {
            let errStr = String(cString: ziti_errorstr(status))
            log.error("nf_init failure: \(errStr)")
            return
        }
        
        // save off nf_context
        ZitiUrlProtocol.nf_context = nf_context
                        
        // Register protocol
        URLProtocol.registerClass(ZitiUrlProtocol.self)
        log.info("ZitiUrlProcol registered", function:"on_nf_init()")
        
        // set init_complete flag and wait up the blocked start() method
        ZitiUrlProtocol.nf_init_cond?.lock()
        ZitiUrlProtocol.nf_init_complete = true
        ZitiUrlProtocol.nf_init_cond?.signal()
        ZitiUrlProtocol.nf_init_cond?.unlock()
    }
    
    static private let on_nf_service:nf_service_cb = { nf, zs, status, data in
        guard var zs = zs?.pointee else {
            log.wtf("unable to access service, status: \(status)")
            return
        }
        
        let svcName = String(cString: zs.name)
        if status == ZITI_SERVICE_UNAVAILABLE {
            ZitiUrlProtocol.interceptsLock.lock()
            ZitiUrlProtocol.intercepts = ZitiUrlProtocol.intercepts.filter { $0.value.name !=  svcName }
            ZitiUrlProtocol.interceptsLock.unlock()
        } else if status == ZITI_OK {
            
            // prefer urlCfgType, tunCfgType as fallback
            var foundUrlCfg = false
            if let cfg = ZitiIntercept.parseConfig(ZitiUrlConfig.self, &zs) {
                let urlStr = "\(cfg.scheme)://\(cfg.hostname):\(cfg.getPort())"
                
                ZitiUrlProtocol.interceptsLock.lock()
                if let curr = ZitiUrlProtocol.intercepts[urlStr] {
                    log.info("intercept \"\(urlStr)\" changing from \"\(curr.name)\" to \"\(svcName)\"", function:"on_nf_service()")
                    curr.close()
                }
                var intercept = ZitiIntercept(loop, svcName, urlStr)
                intercept.hdrs = cfg.headers ?? [:]
                ZitiUrlProtocol.intercepts[intercept.urlStr] = intercept
                
                log.info("Setting URL intercept svc \(svcName): \(urlStr)", function:"on_nf_service()")
                ZitiUrlProtocol.interceptsLock.unlock()
                
                foundUrlCfg = true
            }
            
            // fallback to tun config type
            if !foundUrlCfg, let cfg = ZitiIntercept.parseConfig(ZitiTunnelConfig.self, &zs) {
                let hostPort = "\(cfg.hostname):\(cfg.port)"
                   
                ZitiUrlProtocol.interceptsLock.lock()
                
                // issues with releasing these.  mark them for future cleanup
                if let curr = ZitiUrlProtocol.intercepts["http://\(hostPort)"] {
                    log.info("intercept \"http://\(hostPort)\" changing from \"\(curr.name)\" to \"\(svcName)\"", function:"on_nf_service()")
                    curr.close()
                }
                if let curr = ZitiUrlProtocol.intercepts["https://\(hostPort)"] {
                    log.info("intercept \"https://\(hostPort)\" changing from \"\(curr.name)\" to \"\(svcName)\"", function:"on_nf_service()")
                    curr.close()
                }
                
                if let scheme = (cfg.port == 80 ? "http" : (cfg.port == 443 ? "https" : nil)) {
                    var intercept = ZitiIntercept(loop, svcName, "\(scheme)://\(hostPort)")
                    ZitiUrlProtocol.intercepts[intercept.urlStr] = intercept
                    log.info("Setting TUN intercept svc \(scheme)://\(hostPort): \(hostPort)", function:"on_nf_service()")
                } else {
                    var intercept = ZitiIntercept(loop, svcName, "http://\(hostPort)")
                    ZitiUrlProtocol.intercepts[intercept.urlStr] = intercept
                    intercept = ZitiIntercept(loop, svcName, "https://\(hostPort)")
                    ZitiUrlProtocol.intercepts[intercept.urlStr] = intercept
                    log.info("Setting TUN intercept svc \(svcName): \(hostPort)", function:"on_nf_service()")
                }
                ZitiUrlProtocol.interceptsLock.unlock()
            }
        }
    }
        
    //
    // MARK: - Helpers
    // Helpers for manipulating URL to map to um_http calls
    //
    private func getUrlString() -> String {
        guard let url = request.url, let scheme = url.scheme, let host = url.host else {
            return ""
        }
        var port = url.port
        if port == nil { port = (scheme == "https") ? 443 : 80 }
        return "\(scheme)://\(host):\(port!)"
    }
    private func getUrlPath() -> String {
        guard let url = request.url else { return "/" }
        guard url.path.count > 0 else { return "/" }
        return url.query == nil ? url.path : "\(url.path)?\(url.query!)"
    }
}

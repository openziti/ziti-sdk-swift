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
@objc public class ZitiUrlProtocol: URLProtocol {
    var clt = um_http_t()
    var started = false
    var req:UnsafeMutablePointer<um_http_req_t>? = nil
    var resp:HTTPURLResponse?
    
    var clientThread:Thread? // Thread that calls start/stopLoading, handles client notifications
    var modes:[String] = []
    
    // queue requests for uv_async_send (start/stop loading)
    // (also servs to hold the unretained reference to self used for uv callbacks until we're done with it)
    static let reqsLock = NSLock()
    static var reqs:[ZitiUrlProtocol] = []
    
    static var loop = uv_default_loop()
    static var async_start_h = uv_async_t()
    static var async_close_h = uv_async_t()
    
    // MARK: - Register and start
    /**
     * Registers this protocol via `URLProtocol.registerClass` and starts the background thread for processing `Ziti` requests.
     *
     * - Returns: `true` on success
     *
     * Note that in some cases `ZitiUrlProtocol` will beed to be configured in your `URLSession`'s configuration ala:
     *
     * ```
     * let configuration = URLSessionConfiguration.default
     * configuration.protocolClasses?.insert(ZitiUrlProtocol.self, at: 0)
     * urlSession = URLSession(configuration:configuration)
     * ```
     */
    @objc public class func start() -> Bool {
        //uv_mbed_set_debug(5, stdout) // 6 is trace, 5 is verb, 4 is debug, 3 is info
        
        // Init the start/stop async send handles
        if uv_async_init(ZitiUrlProtocol.loop, &async_start_h, ZitiUrlProtocol.on_async_start) != 0 {
            NSLog("ZitiUrlProcol.start unable to init async_start_h")
            return false
        }
        if uv_async_init(ZitiUrlProtocol.loop, &async_close_h, ZitiUrlProtocol.on_async_close) != 0 {
            NSLog("ZitiUrlProcol.start unable to init async_close_h")
            return false
        }
        
        // Register protocol
        guard URLProtocol.registerClass(ZitiUrlProtocol.self) else {
            NSLog("ZitiUrlProcol.start Unable to register ZitiUrlProcol")
            return false
        }
        
        // start thread for uv_loop
        let t = Thread(target: self, selector: #selector(ZitiUrlProtocol.doLoop), object: nil)
        t.name = "ziti_uv_loop"
        t.start()
        return true
    }
    
    @objc private class func doLoop() {
        print("starting loop")
        let status = uv_run(loop, UV_RUN_DEFAULT)
        print("uv_run complete with status=\(status)")
        
        if uv_loop_close(loop) != 0 {
            NSLog("Error closing uv_loop")
        }
    }
    
    //
    // MARK: - URLProtocol
    //
    override init(request: URLRequest, cachedResponse: CachedURLResponse?, client: URLProtocolClient?) {
        super.init(request: request, cachedResponse: cachedResponse, client: client)
        print("init \(self), Thread: \(String(describing: Thread.current.name))")
    }
    
    deinit {
        print("deinit \(self), Thread: \(String(describing: Thread.current.name))")
    }
    
    public override class func canInit(with request: URLRequest) -> Bool {
        print("Checking if can handle \(request.debugDescription)")
        if let url = request.url, (url.scheme == "http" || url.scheme == "https") {
            return true // would check to see if we should intercept...
        } else if let url = request.url {
            NSLog("ZitiUrlProtocol unsupported scheme: \(url.scheme ?? "nil")")
        }
        return false
    }
    
    public override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }
    
    public override func startLoading() {
        print("*** start loading, Thread: \(String(describing: Thread.current.name))")
        
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
            NSLog("ZitiUrlProtocol.startLoading request \(request) queued, but unable to trigger async send")
            return
        }
    }
    
    public override func stopLoading() {
        print("*** stop loading, Thread: \(String(describing: Thread.current.name))")
        if uv_async_send(&ZitiUrlProtocol.async_close_h) != 0 {
            NSLog("ZitiUrlProtocol.stopLoading request \(request) queued, but unable to trigger async send")
            return
        }
    }
    
    //
    // MARK: - um_http callbacks
    //
    static private let on_async_start:uv_async_cb = { h in
        print("--- on_async_start, Thread: \(String(describing: Thread.current.name))")
        
        // Grab any that are queued and not yet started
        ZitiUrlProtocol.reqsLock.lock()
        var reqs = ZitiUrlProtocol.reqs.filter { !($0.started) }
        ZitiUrlProtocol.reqsLock.unlock()
        
        // Send queued requests
        reqs.forEach { zup in
            zup.started = true
            if um_http_init(ZitiUrlProtocol.loop, &zup.clt, zup.getUrlString().cString(using: .utf8)) != 0 {
                let str = "Unable to initialize ziti http client for \(zup.request)"
                NSLog("ZitiUrlProtocol \(str)")
                let err = HttpResponseError(code:-1, str:str)
                zup.notifyDidFailWithError(err)
            } else {
                zup.req = um_http_req(&zup.clt,
                                      zup.request.httpMethod ?? "GET",
                                      zup.getUrlPath().cString(using: .utf8),
                                      ZitiUrlProtocol.on_http_resp,
                                      zup.toVoidPtr())
                zup.req?.pointee.resp.body_cb = ZitiUrlProtocol.on_http_body
                
                if zup.req != nil {
                    // Add request headers 
                    print("--- Request Headers ---")
                    zup.request.allHTTPHeaderFields?.forEach { h in
                        print("\(h.key): \(h.value)")
                        let status = um_http_req_header(zup.req,
                                                        h.key.cString(using: .utf8),
                                                        h.value.cString(using: .utf8))
                        if (status != 0) {
                            let str = String(cString: uv_strerror(Int32(status)))
                            NSLog("ZitiUrlProtocol request header error ignored: \(str)")
                        }
                    }
                    print("--- End Request Headers ---")
                    
                    // Add body
                    if let body = zup.request.httpBody {
                        let ptr = UnsafeMutablePointer<Int8>.allocate(capacity: body.count)
                        var bytes:[Int8] = body.map{ Int8(bitPattern: $0) }
                        ptr.initialize(from: bytes, count: body.count)
                        um_http_req_data(zup.req, ptr, body.count, nil)
                        ptr.deallocate()
                    } else if let stream = zup.request.httpBodyStream {
                        // TODO: Check for no Content-Lenth and Transfer-Encoding:chunked.  If so, we'll need multiple sends...
                        // For now just log a warning that here's where things when south
                        if let clv = zup.request.allHTTPHeaderFields?["Content-Length"], let contentLen = Int(clv) {
                            var body = Data()
                            let ptr = UnsafeMutablePointer<UInt8>.allocate(capacity: contentLen)
                            stream.open()
                            while stream.hasBytesAvailable {
                                let n = stream.read(ptr, maxLength: contentLen)
                                body.append(ptr, count: n)
                            }
                            stream.close()
                            
                            _ = ptr.withMemoryRebound(to: Int8.self, capacity: body.count) {
                                um_http_req_data(zup.req, $0, body.count, nil)
                            }
                            ptr.deallocate()
                        } else {
                            NSLog("ZitiUrlProtocol - chunked encoding not yet supported :(")
                        }
                    }
                }
            }
        }
    }
    
    static private let on_http_resp:um_http_resp_cb = { resp, ctx in
        print("--- on_http_resp, Thread: \(String(describing: Thread.current.name))")
        guard let resp = resp, let mySelf = ZitiUrlProtocol.fromContext(ctx) else {
            NSLog("ZitiUrlProtocol.on_http_resp WTF unable to decode context")
            return
        }
        guard let reqUrl = mySelf.request.url else {
            NSLog("ZitiUrlProtocol.on_http_resp WTF unable to determine request URL")
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
            let err = HttpResponseError(code:Int32(code), str:str)
            mySelf.notifyDidFailWithError(err)
            return
        }
        
        mySelf.resp = HTTPURLResponse(url: reqUrl,
                                      statusCode: code,
                                      httpVersion: nil, // "HTTP/" + String(cString: resp.pointee.http_version)
                                      headerFields: hdrMap)
        guard let httpResp = mySelf.resp else {
            NSLog("ZitiUrlProtocol.on_http_resp unable create response object for \(reqUrl)")
            return
        }
        mySelf.notifyDidReceive(httpResp)
    }
    
    struct HttpResponseError : Error {
        var code:Int32
        var str:String?
    }
    static private let on_http_body:um_http_body_cb = { req, body, len in
        print("--- on_http_body (\(len), Thread: \(String(describing: Thread.current.name))")
        guard let req = req, let mySelf = ZitiUrlProtocol.fromContext(req.pointee.data) else {
            NSLog("ZitiUrlProtocol.on_http_body WTF unable to decode context")
            return
        }
        
        if uv_errno_t(Int32(len)) == UV_EOF {
            //request complete
            mySelf.notifyDidFinishLoading()
        } else if len < 0 {
            //error.  See uv_strerror(len)
            let str = String(cString: uv_strerror(Int32(len)))
            let err = HttpResponseError(code:Int32(len), str:str)
            mySelf.notifyDidFailWithError(err)
        } else {
            let data = Data(bytes: body!, count: len)
            mySelf.notifyDidLoad(data)
        }
    }
    
    static private let on_async_close:uv_async_cb = { h in
        print("--- on_async_close, Thread: \(String(describing: Thread.current.name))")
        
        // grab on in started state and remove them from list of requests
        ZitiUrlProtocol.reqsLock.lock()
        var toClose = ZitiUrlProtocol.reqs.filter { $0.started }
        ZitiUrlProtocol.reqs = ZitiUrlProtocol.reqs.filter { !($0.started) }
        ZitiUrlProtocol.reqsLock.unlock()
        
        // close 'em
        toClose.forEach { zup in
            print("... calling um_http_close")
            if um_http_close(&zup.clt) != 0 {
                NSLog("ZitiUrlProtocol error on um_http_close for \(zup.request)")
            }
        }
    }
    
    //
    // MARK: - Client Notifications
    // Methods for forcing the client callbacks to run on the client thread
    // when called from uv_loop callbacks
    //
    @objc private func notifyDidFinishLoadingSelector(_ arg:Any?) {
        print("*** notifyDidFinish, Thread: \(String(describing: Thread.current.name))")
        client?.urlProtocolDidFinishLoading(self)
    }
    private func notifyDidFinishLoading() {
        performOnClientThread(#selector(notifyDidFinishLoadingSelector), nil)
    }
    
    @objc private func notifyDidFailWithErrorSelector(_ err:Error) {
        print("*** notifyDidFail, Thread: \(String(describing: Thread.current.name))")
        client?.urlProtocol(self, didFailWithError: err)
    }
    private func notifyDidFailWithError(_ error:Error) {
        performOnClientThread(#selector(notifyDidFailWithErrorSelector), error)
    }
    
    @objc private func notifyDidLoadSelector(_ data:Data) {
        print("*** notifyDidLoad(\(data.count), Thread: \(String(describing: Thread.current.name))")
        client?.urlProtocol(self, didLoad: data)
    }
    private func notifyDidLoad(_ data:Data) {
        performOnClientThread(#selector(notifyDidLoadSelector), data)
    }
    
    @objc private func notifyDidReceiveSelector(_ resp:HTTPURLResponse) {
        print("*** notifyDidReceive (header), Thread: \(String(describing: Thread.current.name))")
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
    }
    private func notifyDidReceive(_ resp:HTTPURLResponse) {
        performOnClientThread(#selector(notifyDidReceiveSelector), resp)
    }
    
    private func performOnClientThread(_ aSelector:Selector, _ arg:Any?) {
        perform(aSelector, on: clientThread!, with:arg, waitUntilDone:true, modes:modes)
    }
    
    //
    // MARK: - Helpers
    // Helpers for manipulating URL to map to um_http calls
    //
    private func getUrlString() -> String {
        guard let url = request.url else { return "" }
        return (url.scheme ?? "http") + "://" + (url.host ?? "") + (url.port != nil ? ":\(url.port!)" : "")
    }
    private func getUrlPath() -> String {
        guard let url = request.url else { return "/" }
        guard url.path.count > 0 else { return "/" }
        return url.path
    }
    
    //
    // Helpers to translate 'self' to pointer to use as callback data
    //
    static private func fromContext(_ ctx:Optional<UnsafeMutableRawPointer>) -> ZitiUrlProtocol? {
        guard ctx != nil else { return nil }
        return Unmanaged<ZitiUrlProtocol>.fromOpaque(UnsafeMutableRawPointer(ctx!)).takeUnretainedValue()
    }
    private func toVoidPtr() -> UnsafeMutableRawPointer {
        return UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        //return UnsafeMutableRawPointer(Unmanaged.passRetained(self).toOpaque()) // force leak until matching takeRetained
    }
}

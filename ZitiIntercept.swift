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
import OSLog

class ZitiIntercept : NSObject, ZitiUnretained {
    private let log = OSLog(ZitiIntercept.self)
    
    var loop:UnsafeMutablePointer<uv_loop_t>?
    let name:String
    let urlStr:String
    var clt = um_http_t()
    var zs = um_http_src_t()
    var hdrs:[String:String]? = nil
    
    static var releasePending:[ZitiIntercept] = []
    var close_timer_h:UnsafeMutablePointer<uv_timer_t>?

    init(_ loop:UnsafeMutablePointer<uv_loop_t>?, _ name:String, _ urlStr:String) {
        self.name = name
        self.urlStr = urlStr
        ziti_src_init(loop, &zs, name.cString(using: .utf8), ZitiUrlProtocol.nf_context)
        um_http_init_with_src(loop, &clt, urlStr.cString(using: .utf8), &zs)
        um_http_idle_keepalive(&clt, ZitiUrlProtocol.idleTime)
        
        close_timer_h = UnsafeMutablePointer.allocate(capacity: 1)
        close_timer_h?.initialize(to: uv_timer_t())
        
        super.init()
        
        uv_timer_init(loop, close_timer_h)
        close_timer_h?.pointee.data = self.toVoidPtr()
        close_timer_h?.withMemoryRebound(to: uv_handle_t.self, capacity: 1) {
            uv_unref($0)
        }
    }
    
    static let on_close_timer:uv_timer_cb = { h in
        guard let ctx = h?.pointee.data, let mySelf = zitiUnretained(ZitiIntercept.self, ctx) else {
            return
        }
        ZitiIntercept.releasePending = ZitiIntercept.releasePending.filter { $0 != mySelf }
    }
    
    func close() {
        // This close sequence isn't great. If we release the mem, even after waiting for an
        // iteration of the loop, we run into memory issues.  For now will set a very long
        // timer and clean up when it expires (not that big of a deal, since intercepts usually
        // last lifetime of the app)
        ZitiIntercept.releasePending.append(self)
        um_http_close(&clt)
        uv_timer_start(close_timer_h, ZitiIntercept.on_close_timer, 5000, 0)
    }
    
    deinit {
        close_timer_h?.deinitialize(count: 1)
        close_timer_h?.deallocate()
    }
    
    static func parseConfig<T>(_ type: T.Type, _ zs: inout ziti_service) -> T? where T:Decodable, T:ZitiConfig {
        return T.parseConfig(type, &zs)
    }
    
    func createRequest(_ zup:ZitiUrlProtocol, _ urlPath:String,
                       _ on_resp:@escaping um_http_resp_cb,
                       _ on_body:@escaping um_http_body_cb,
                       _ ctx:UnsafeMutableRawPointer) -> UnsafeMutablePointer<um_http_req_t>? {
        
        var req:UnsafeMutablePointer<um_http_req_t>? = nil
        
        let method = zup.request.httpMethod ?? "GET"
        req = um_http_req(&clt, method, urlPath.cString(using: .utf8), on_resp, ctx)
        req?.pointee.resp.body_cb = on_body
        
        if req != nil {
            // Add request headers
            zup.request.allHTTPHeaderFields?.forEach { h in
                um_http_req_header(req,
                                   h.key.cString(using: .utf8),
                                   h.value.cString(using: .utf8))
            }
            
            // add any headers specified via service config
            if let hdrs = hdrs {
                hdrs.forEach { hdr in
                    um_http_req_header(req, hdr.key, hdr.value)
                }
            }
            
            // if no User-Agent add it
            if zup.request.allHTTPHeaderFields?["User-Agent"] == nil {
                var zv = "unknown-@unknown"
                if let nfv = NF_get_version()?.pointee {
                    zv = "\(String(cString: nfv.version))-@\(String(cString: nfv.revision))"
                }
                um_http_req_header(req,
                                   "User-Agent".cString(using: .utf8),
                                   "\(ZitiUrlProtocol.self); ziti-sdk-c/\(zv)".cString(using: .utf8))
            }
            
            // if no Accept, add it
            if zup.request.allHTTPHeaderFields?["Accept"] == nil {
                um_http_req_header(req,
                                   "Accept".cString(using: .utf8),
                                   "*/*".cString(using: .utf8))
            }
            
            // Add body
            if let body = zup.request.httpBody {
                let ptr = UnsafeMutablePointer<Int8>.allocate(capacity: body.count)
                let bytes:[Int8] = body.map{ Int8(bitPattern: $0) }
                ptr.initialize(from: bytes, count: body.count)
                um_http_req_data(req, ptr, body.count, nil)
                ptr.deallocate()
            } else if let stream = zup.request.httpBodyStream {
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
                        um_http_req_data(req, $0, body.count, nil)
                    }
                    ptr.deallocate()
                } else {
                    // TODO: Transfer-Encoding:chunked
                    let encoding = zup.request.allHTTPHeaderFields?["Transfer-Encoding"] ?? ""
                    log.error("Content-Length required, \(encoding) encoding not yet supported :(")
                }
            }
        }
        return req
    }
}

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

class ZitiIntercept : NSObject {
    let name:String
    let urlStr:String
    var clt = um_http_t()
    var zs = um_http_src_t()
    var hdrs:[String:String]? = nil

    init(name:String, urlStr:String) {
        self.name = name
        self.urlStr = urlStr
        ziti_src_init(ZitiUrlProtocol.loop, &zs, name.cString(using: .utf8), ZitiUrlProtocol.nf_context)
        um_http_init_with_src(ZitiUrlProtocol.loop, &clt, urlStr.cString(using: .utf8), &zs)
        um_http_idle_keepalive(&clt, ZitiUrlProtocol.idleTime)
        
        super.init()
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
                let status = um_http_req_header(req,
                                                h.key.cString(using: .utf8),
                                                h.value.cString(using: .utf8))
                if (status != 0) {
                    let str = String(cString: uv_strerror(Int32(status)))
                    NSLog("ZitiUrlProtocol request header error ignored: \(str)")
                }
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
                    NSLog("ZitiUrlProtocol - Content-Length required, \(encoding) encoding not yet supported :(")
                }
            }
        }
        return req
    }
}

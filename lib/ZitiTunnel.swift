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

public protocol ZitiTunnelProvider {
    func addRoute(_ dest:String) -> Int32
    func deleteRoute(_ dest:String) -> Int32
    
    func applyDns(_ host:String, _ ip:String) -> Int32
    
    func writePacket(_ data:Data)
}

public class ZitiTunnel : NSObject, ZitiUnretained {
    private static let log = ZitiLog(ZitiTunnel.self)
    private let log = ZitiTunnel.log
    
    var tnlr_ctx:tunneler_context?
    var tunneler_opts:UnsafeMutablePointer<tunneler_sdk_options>!
    var dns:UnsafeMutablePointer<dns_manager>!
    let netifDriver:NetifDriver
        
    public init(_ tunnelProvider:ZitiTunnelProvider, _ loop:UnsafeMutablePointer<uv_loop_t>) {
        netifDriver = NetifDriver(tunnelProvider: tunnelProvider)
        super.init()
        
        tunneler_opts = UnsafeMutablePointer<tunneler_sdk_options>.allocate(capacity: 1)
        tunneler_opts.initialize(to: tunneler_sdk_options(
            netif_driver: self.netifDriver.open(),
            ziti_dial: ziti_sdk_c_dial,
            ziti_close: ziti_sdk_c_close,
            ziti_close_write: ziti_sdk_c_close_write,
            ziti_write: ziti_sdk_c_write,
            ziti_host: ziti_sdk_c_host))
        tnlr_ctx = ziti_tunneler_init(tunneler_opts, loop)
        
        dns = UnsafeMutablePointer<dns_manager>.allocate(capacity: 1)
        dns.initialize(to: dns_manager(
                        apply: ZitiTunnel.apply_dns_cb,
                        data: self.toVoidPtr()))
        ziti_tunneler_set_dns(tnlr_ctx, dns)
    }
    
    deinit {
        dns.deinitialize(count: 1)
        dns.deallocate()
        tunneler_opts.deinitialize(count: 1)
        tunneler_opts.deallocate()
    }
    
    public func queuePacket(_ data:Data) {
        netifDriver.queuePacket(data)
    }
    
    public func onService(_ ztx:ziti_context, _ svc: inout ziti_service, _ status:Int32) {
        _ = ziti_sdk_c_on_service_wrapper(ztx, &svc, status, tnlr_ctx)
    }
    
    static let apply_dns_cb:apply_cb = { dns, host, ip in
        guard let mySelf = zitiUnretained(ZitiTunnel.self, dns?.pointee.data) else {
            log.wtf("invalid context", function: "apply_dns_cb()")
            return -1
        }
        
        let hostStr = host != nil ? String(cString: host!) : ""
        let ipStr = ip != nil ? String(cString: ip!) : ""
        return mySelf.netifDriver.tunnelProvider?.applyDns(hostStr, ipStr) ?? -1
    }
}

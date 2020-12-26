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
    func writePacket(_ data:Data)
    func readCompleteCallback(_ len:Int)
}

public class ZitiTunnel : NSObject, ZitiUnretained {
    private static let log = ZitiLog(ZitiTunnel.self)
    private let log = ZitiTunnel.log
    
    var tnlr_ctx:tunneler_context?
    var tunneler_opts:UnsafeMutablePointer<tunneler_sdk_options>!
    let netifDriver:NetifDriver
    
    var bcc:UnsafeMutablePointer<bytes_consumed_cb_context>!
    
    public init(_ tunnelProvider:ZitiTunnelProvider, _ loop:UnsafeMutablePointer<uv_loop_t>) {
        netifDriver = NetifDriver(tunnelProvider: tunnelProvider)
        tunneler_opts = UnsafeMutablePointer<tunneler_sdk_options>.allocate(capacity: 1)
        tunneler_opts.initialize(to: tunneler_sdk_options(
            netif_driver: self.netifDriver.open(),
            ziti_dial: ziti_sdk_c_dial,
            ziti_close: ziti_sdk_c_close,
            ziti_write: ziti_sdk_c_write_wrapper,
            ziti_host_v1: ziti_sdk_c_host_v1_wrapper))
        tnlr_ctx = ziti_tunneler_init(tunneler_opts, loop)
        super.init()
        
        // Hack until tunnel-sdk-c supports throttling uploads
        bcc = UnsafeMutablePointer<bytes_consumed_cb_context>.allocate(capacity: 1)
        bcc.initialize(to: bytes_consumed_cb_context(cb: ZitiTunnel.bcCallback, user_data: self.toVoidPtr()))
        set_bytes_consumed_cb(bcc)
    }
    
    deinit {
        tunneler_opts.deinitialize(count: 1)
        tunneler_opts.deallocate()
        bcc.deinitialize(count: 1)
        bcc.deallocate()
    }
    
    static let bcCallback:bytes_consumed_cb = { len, ctx in
        guard let mySelf = zitiUnretained(ZitiTunnel.self, ctx) else {
            log.wtf("invalid ctx")
            return
        }
        log.warn("consumed \(len) bytes")
    }
    
    static let xziti_sdk_c_write_wrapper:ziti_sdk_write_cb = { io_ctx, write_ctx, data, len in
        let _ziti_io_ctx = io_ctx?.assumingMemoryBound(to: ziti_io_context.self)
        var _data = data?.assumingMemoryBound(to: UnsafeMutablePointer<UInt8>.self)
        log.warn("writing \(len)")
        return Int(ziti_write(_ziti_io_ctx!.pointee.ziti_conn, _data!.pointee, len, ZitiTunnel.on_ziti_write, write_ctx))
    }
    
    static let on_ziti_write:ziti_write_cb = { ziti_conn, len, ctx in
        let _ctx = ctx?.assumingMemoryBound(to: OpaquePointer.self)
        ziti_tunneler_ack(_ctx?.pointee)
        log.warn("wrote \(len)")
    }
    
    public func queuePacket(_ data:Data) {
        netifDriver.queuePacket(data)
    }
    
    public func v1Host(_ ziti_ctx: ziti_context?, _ service_name: UnsafePointer<Int8>!, _ proto: UnsafePointer<Int8>!, _ hostname: UnsafePointer<Int8>!, _ port: Int32) -> Int32 {
        return ziti_tunneler_host_v1(tnlr_ctx, UnsafeRawPointer(ziti_ctx), service_name, proto, hostname, port)
    }
    
    public func v1Intercept(_ ziti_ctx: ziti_context?, _ service_id: UnsafePointer<Int8>!, _ service_name: UnsafePointer<Int8>!, _ hostname: UnsafePointer<Int8>!, _ port: Int32) -> Int32 {
        return ziti_tunneler_intercept_v1(tnlr_ctx, UnsafeRawPointer(ziti_ctx), service_id, service_name, hostname, port)
    }
    
    public func v1StopIntercepting(_ service_id: UnsafePointer<Int8>!) {
        ziti_tunneler_stop_intercepting(tnlr_ctx, service_id)
    }
}

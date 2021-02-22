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
    func fallbackDns(_ name:String) -> String?
    
    func writePacket(_ data:Data)
}

public class ZitiTunnel : NSObject, ZitiUnretained {
    private static let log = ZitiLog(ZitiTunnel.self)
    private let log = ZitiTunnel.log
    
    var tunnelProvider:ZitiTunnelProvider?
    var tnlr_ctx:tunneler_context?
    var tunneler_opts:UnsafeMutablePointer<tunneler_sdk_options>!
    var dns:UnsafeMutablePointer<dns_manager>!
    let netifDriver:NetifDriver
        
    public init(_ tunnelProvider:ZitiTunnelProvider, _ loop:UnsafeMutablePointer<uv_loop_t>,
                _ ipAddress:String, _ subnetMask:String,
                _ ipDNS:String) {
        self.tunnelProvider = tunnelProvider
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
        
        // TODO: change this to `get_tunneler_dns(uv_loop_t *l, uint32_t dns_ip, dns_fallback_cb cb, void *ctx)` to use T SDK's dns...
        dns = UnsafeMutablePointer<dns_manager>.allocate(capacity: 1)
        dns.initialize(to: dns_manager(
                        internal_dns: false,
                        dns_ip: ipStrToUInt32(ipDNS),
                        dns_port: 53,
                        apply: ZitiTunnel.apply_dns_cb,
                        query: ZitiTunnel.dns_query_cb,
                        loop: loop,
                        fb_cb: ZitiTunnel.dns_fallback_cb,
                        fb_ctx: self.toVoidPtr(),
                        data: self.toVoidPtr()))
        
        let (mask, bits) = calcMaskAndBits(ipAddress, subnetMask)
        if mask != 0 && bits != 0 {
            ziti_tunneler_init_dns(mask, bits)
        }
        ziti_tunneler_set_dns(tnlr_ctx, dns)
    }
    
    deinit {
        dns.deinitialize(count: 1)
        dns.deallocate()
        tunneler_opts.deinitialize(count: 1)
        tunneler_opts.deallocate()
    }
    
    private func isValidIpV4Address(_ parts:[String]) -> Bool {
        let nums = parts.compactMap { Int($0) }
        return parts.count == 4 && nums.count == 4 && nums.filter { $0 >= 0 && $0 < 256}.count == 4
    }
    
    private func ipStrToUInt32(_ str:String) -> UInt32 {
        let parts = str.components(separatedBy: ".")
        guard isValidIpV4Address(parts) else {
            log.error("Unable to convert \"\(str)\" to IP address")
            return 0
        }
        return (UInt32(parts[0])! << 24) | (UInt32(parts[1])! << 16) | (UInt32(parts[2])! << 8) | UInt32(parts[3])!
    }
    
    private func calcMaskAndBits(_ ipAddress:String, _ subnetMask:String) -> (UInt32, Int32) {
        var mask:UInt32 = 0
        var bits:Int32 = 0
        
        let ipParts = ipAddress.components(separatedBy: ".")
        let maskParts = subnetMask.components(separatedBy: ".")
        guard isValidIpV4Address(ipParts) && isValidIpV4Address(maskParts) else {
            log.error("Invalid IP address (\(ipAddress) and/or subnetMask (\(subnetMask)")
            return (0, 0)
        }
        
        let maskedIP = [
            UInt32(ipParts[0])! & UInt32(maskParts[0])!,
            UInt32(ipParts[1])! & UInt32(maskParts[1])!,
            UInt32(ipParts[2])! & UInt32(maskParts[2])!,
            UInt32(ipParts[3])! & UInt32(maskParts[3])!
        ]
        mask = (maskedIP[0] << 24) | (maskedIP[1] << 16) | (maskedIP[2] << 8) | maskedIP[3]
        log.debug("Converted ipAddress \(ipAddress) to mask \(String(format:"0x%02X", mask))")
        
        // count the leading bits
        for part in maskParts {
            var byte = UInt8(part)!
            let lastByte = byte != 0xff
            while byte & 0x80 != 0 {
                bits += 1
                byte = byte << 1
            }
            if lastByte { break }
        }
        log.debug("Converted subnetMask \(subnetMask) to \(bits) bits")
        
        return (mask, bits)
    }
    
    public func queuePacket(_ data:Data) {
        netifDriver.queuePacket(data)
    }
    
    public func onService(_ ztx:ziti_context, _ svc: inout ziti_service, _ status:Int32) {
        _ = ziti_sdk_c_on_service_wrapper(ztx, &svc, status, tnlr_ctx)
    }
    
    static let apply_dns_cb:apply_cb = { dns, host, ip in
        guard let mySelf = zitiUnretained(ZitiTunnel.self, dns?.pointee.data) else {
            log.wtf("invalid context")
            return -1
        }
        
        let hostStr = host != nil ? String(cString: host!) : ""
        let ipStr = ip != nil ? String(cString: ip!) : ""
        return mySelf.tunnelProvider?.applyDns(hostStr, ipStr) ?? -1
    }
    
    static let dns_query_cb:dns_query = { dns_manager, q_packet, q_len, cb, ctx in
        log.wtf("Unexpected call to unimplemented function")
        return -1
    }
    
    static let dns_fallback_cb:dns_fallback_cb = { name, ctx, addr in
        guard let mySelf = zitiUnretained(ZitiTunnel.self, ctx), let name = name, let addr = addr else {
            log.wtf("invalid context")
            return 3 // NXDOMAIN
        }
        
        let nameStr = String(cString: name)
        if let ipStr = mySelf.tunnelProvider?.fallbackDns(nameStr), let cStr = ipStr.cString(using: .utf8) {
            addr.pointee.s_addr = inet_addr(cStr)
            return 0 // NO_ERROR
        }        
        return 3 // NXDOMAIN
    }
}

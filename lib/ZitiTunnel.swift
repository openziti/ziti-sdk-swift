/*
Copyright NetFoundry Inc.

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
import Dispatch
import CZitiPrivate

/// Protocol for delegate of ZitiTunnel that handles routes, writing packets, and tunnel events
public protocol ZitiTunnelProvider : AnyObject {
    
    /// Indicates the specified route should be intercepted
    func addRoute(_ dest:String) -> Int32
    
    /// Indicates the specified route should no longer be intercepted
    func deleteRoute(_ dest:String) -> Int32
    
    /// Indicates router to never intercept, ragarless of service configation (e.g., addresses of Ziti controllers and routers)
    func excludeRoute(_ dest:String, _ loop:OpaquePointer?) -> Int32
    
    /// Indicates a set of routes have been added of deleted and can be commited to the network interface
    func commitRoutes(_ loop:OpaquePointer?) -> Int32
    
    /// Indicates a packet should be written to the tunnel interface
    func writePacket(_ data:Data)
    
    /// Callback invoked for each Ziti instance once its initialization is complete
    func initCallback(_ ziti:Ziti, _ error:ZitiError?)
    
    /// Callback invoked when tunnel events are received
    func tunnelEventCallback(_ event:ZitiTunnelEvent)
}

/// Class providing a Swift wrapper for Ziti Tunnel SDK C
public class ZitiTunnel : NSObject, ZitiUnretained {
    private static let log = ZitiLog(ZitiTunnel.self)
    private let log = ZitiTunnel.log
    
    var loopPtr = Ziti.ZitiRunloop()
    weak var tunnelProvider:ZitiTunnelProvider?
    let netifDriver:NetifDriver
    var tunneler_opts:UnsafeMutablePointer<tunneler_sdk_options>!
    var tnlr_ctx:tunneler_context?
    
    private let uvDG = DispatchGroup()
    private var loopKeepAliveHandle:UnsafeMutablePointer<uv_async_t>?
    
    /// instance of Ziti that can be used for general purpose calls for performing operations, timers
    public let opsZiti:Ziti
    
    static let KEY_ZITI_INSTANCE = "ZitiTunnel.zitiInstance."
    static let KEY_GOT_SERVICES = "ZitiTunnel.gotServices."
    
    /// Starting the tunnel will delay up to `SERVICE_WAIT_TIMEOUT` seconds waitig for services to be retrieved before calling the `IdentitiesLoadedCallback`
    /// This is done to allow the `ZitiTunnelProvider` to configure any intercepted routes on the interface before it is started (important when extending an
    ///  `NEPacketTunnelProvider`)
    public static var SERVICE_WAIT_TIMEOUT = 20.0
    static let ZITI_SHUTDOWN_TIMEOUT = 5.0
    
    /// Type defintion of callback invoked when all identities have loaded (or timed-out)
    public typealias IdentitiesLoadedCallback = (_ error:ZitiError?) -> Void
    
    class RunArgs : NSObject {
        var zids:[ZitiIdentity]
        var postureChecks:ZitiPostureChecks?
        var loadedCb:IdentitiesLoadedCallback
        
        init(_ zids:[ZitiIdentity], _ postureChecks:ZitiPostureChecks?, _ loadedCb: @escaping IdentitiesLoadedCallback) {
            self.zids = zids
            self.postureChecks = postureChecks
            self.loadedCb = loadedCb
        }
    }
    
    // Support for waiting for identities to load
    let zidsLoadedCond = NSCondition()
    var zidsToLoad = 0
    
    // event_cb has no user data, so we'll lookup ZitiTunnel instnance by identifier
    private static var zitiDict:[String:Ziti] = [:]
    
    /// Class encapsulating an IPv4 route
    public class Route : NSObject {
        /// base address
        public var addr:String
        
        /// subnet mask
        public var mask:String
        
        init(_ addr:String, mask:String) { self.addr = addr; self.mask = mask }
    }
    
    /// Initialize a `ZitiTunnel` instance
    ///  - Parameters:
    ///     - tunnelProvider: Delegate for adding/removing routes, writing packets, and handling events
    ///     - ipAddress: Address of the tunnel interface
    ///     - subnetMask: Mask of the `ipAddress` for routes to the tunnel interface
    ///     - ipDNS: Address for DNS queries
    public init(_ tunnelProvider:ZitiTunnelProvider?,
                _ ipAddress:String, _ subnetMask:String, _ ipDNS:String) {

        set_tunnel_logger()

        opsZiti = Ziti(zid: ZitiIdentity(id: "--- ops Ziti ---", ztAPI: ""), loopPtr: loopPtr)
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
        tnlr_ctx = ziti_tunneler_init(tunneler_opts, loopPtr.loop)
        
        let (_, bits) = calcMaskAndBits(ipAddress, subnetMask)
        let dnsCidr = "\(ipAddress)/\(bits)"
        log.debug("dnsCidr = \(dnsCidr)")
        ziti_dns_setup(tnlr_ctx, ipDNS.cString(using: .utf8), dnsCidr.cString(using: .utf8))
        
        loopKeepAliveHandle = UnsafeMutablePointer<uv_async_t>.allocate(capacity: 1)
        loopKeepAliveHandle?.initialize(to: uv_async_t())
        uv_async_init(loopPtr.loop, loopKeepAliveHandle, ZitiTunnel.onLoopKeepAlive)
    }
    
    deinit {
        tunneler_opts.deinitialize(count: 1)
        tunneler_opts.deallocate()
        loopKeepAliveHandle?.deinitialize(count: 1)
        loopKeepAliveHandle?.deallocate()
    }
    
    /// Set upstream DNS address
    /// - Parameter ipUpstreamDNS: hostname (and optional port) for upstream DNS requests
    /// - Returns: Returns 0 on success
    public func setUpstreamDns(_ ipUpstreamDNS:String) -> Int32 {
        var upDNS = ipUpstreamDNS
        var upPort:UInt16 = 53
        if upDNS.contains(where: { $0 == ":" }) {
            let parts = upDNS.split(separator: ":")
            upDNS = String(parts[0])
            upPort = UInt16(parts[1]) ?? upPort
        }
        log.debug("upStreamDNS=\(upDNS), port=\(upPort)")
        return ziti_dns_set_upstream(loopPtr.loop, upDNS.cString(using: .utf8), upPort)
    }
    
    /// Perform on operation on the uv_loop managed by this class
    /// - Parameter op: operation to perform
    public func perform(_ op: @escaping Ziti.PerformCallback) {
        opsZiti.perform(op)
    }
    
    func setZitiInstance(_ identifier:String, _ zitiCtx:ziti_context, _ zitiCfg:UnsafeMutablePointer<ziti_config>, _ zitiOpts:UnsafeMutablePointer<ziti_options>) {
        var zi:UnsafeMutablePointer<ziti_instance_s>?
        zi = new_ziti_instance(identifier.cString(using: .utf8))

        // use the context and options that the caller provided
        zi?.pointee.ztx = zitiCtx
        init_ziti_instance(zi, zitiCfg, zitiOpts) // todo check return

        set_ziti_instance(identifier.cString(using: .utf8), zi)
        
        guard let ziti = ZitiTunnel.zitiDict[identifier] else {
            log.wtf("Unable to locate Ziti instance for identifier \(identifier)")
            return
        }
        
        let key = "\(ZitiTunnel.KEY_ZITI_INSTANCE)\(ziti.id.id)"
        ziti.userData[key] = zi
    }
    
    @objc func loadAndRunZiti(_ args:RunArgs) {
        // store self pointer for each identity to lookup ourself in onEventCallback
        args.zids.forEach { zid in
            let z = Ziti(zid: zid, zitiTunnel: self)
            ZitiTunnel.zitiDict[zid.id] = z
        }
        
        // Initialize the tunneler SDK CMDs
        _ = ziti_tunnel_init_cmd(loopPtr.loop, tnlr_ctx, ZitiTunnel.onEventCallback)
        
        // run the identities
        zidsToLoad = args.zids.count
        for (identifier, ziti) in ZitiTunnel.zitiDict {
            log.info("Starting \(identifier):\"\(String(describing: ziti.id.name))\" at \(ziti.id.ztAPI)")
            ziti.run(args.postureChecks) { [weak self] zErr in
                if zErr != nil {
                    // dec the count (otherwise will need to wait for condition to timeout)
                    self?.zidsLoadedCond.lock()
                    self?.zidsToLoad -= 1
                    self?.zidsLoadedCond.signal()
                    self?.zidsLoadedCond.unlock()
                }
                self?.tunnelProvider?.initCallback(ziti, zErr)
            }
        }
        
        // Start up the run loop in its own thread.  All callbacks to the tunnel provider are called from the run loop
        DispatchQueue.global().async {
            self.uvDG.enter()
            _ = Ziti.executeRunloop(loopPtr: self.loopPtr)
            self.uvDG.leave()
        }
                
        // wait for services to be reported...
        zidsLoadedCond.lock()
        while zidsToLoad > 0 {
            if !zidsLoadedCond.wait(until: Date(timeIntervalSinceNow: TimeInterval(ZitiTunnel.SERVICE_WAIT_TIMEOUT))) {
                log.warn("Timed out waiting for zidToLoad == 0 (\(zidsToLoad) of \(args.zids.count) identities have not returned any services")
                break
            }
        }
        zidsLoadedCond.unlock()
        
        // trigger caller that zids have loaded. Make it run on the uv_loop via a any identity...
        self.perform { args.loadedCb(nil) }
    }
    
    /// Connect to Ziti and begin processing for the specified identites
    /// - Parameters:
    ///     - zids: List of Ziti identities
    ///     - postureChecks: Handler for posture checks
    ///     - loadedCb: Callback invoked when identites are loaded (services have been received or timed-out)
    public func startZiti(_ zids:[ZitiIdentity], _ postureChecks:ZitiPostureChecks?, _ loadedCb: @escaping IdentitiesLoadedCallback) {
        let args = RunArgs(zids, postureChecks, loadedCb)
        Thread(target: self, selector: #selector(self.loadAndRunZiti), object: args).start()
    }
    
    /// Shutdown Ziti
    /// - Parameters:
    ///     - completionHandler: Callback invoked when shutodwn compete
    public func shutdownZiti(_ completionHandler: @escaping ()->Void) {
        self.perform {
            // remove reference to loopKeepAliveHandle
            self.loopKeepAliveHandle?.withMemoryRebound(to: uv_handle_t.self, capacity: 1) {
                uv_unref($0)
            }
            
            for (identifier, ziti) in ZitiTunnel.zitiDict {
                guard let ztx = ziti.ztx else {
                    self.log.error("Invalid ztx for identifier \(identifier)")
                    continue
                }
                self.log.info("Shutting down \(identifier)")
                ziti_shutdown(ztx)
            }
        }
        
        DispatchQueue.global().async {
            let res = self.uvDG.wait(timeout: DispatchTime.now() + ZitiTunnel.ZITI_SHUTDOWN_TIMEOUT)
            
            if res == .timedOut {
                self.log.error("Timed out waiting for Ziti shutdowns to complete")
            } else {
                self.log.info("Ziti shutdown complete, status=\(res)")
            }
            completionHandler()
        }
    }
    
    static private let onEventCallback:event_cb = { cEvent in
        guard let cEvent = cEvent, let cid = cEvent.pointee.identifier else {
            log.error("Invalid base event identifier")
            return
        }
        let id:String = String(cString: cid)
        guard let ziti = zitiDict[id], let mySelf = ziti.zitiTunnel else {
            log.wtf("invalid context")
            return
        }
        
        // Update ztx (not available until loop is running...), call initCallback
        let key = "\(KEY_ZITI_INSTANCE)\(ziti.id.id)"
        if ziti.ztx == nil, let zi = ziti.userData[key] as? UnsafeMutablePointer<ziti_instance_s>, let ztx = zi.pointee.ztx {
            ziti.ztx = ztx
            Ziti.postureContexts[ztx] = ziti
            mySelf.tunnelProvider?.initCallback(ziti, nil)
        }
        
        // always update the zid name
        if let ztx = ziti.ztx, let czid = ziti_get_identity(ztx), czid.pointee.name != nil {
            let name = String(cString: czid.pointee.name)
            if ziti.id.name != name {
                log.info("zid name updated to: \(name)")
                ziti.id.name = name
            }
        }
        
        switch cEvent.pointee.event_type.rawValue {
        case TunnelEvents.ContextEvent.rawValue:
            var cCtxEvent = UnsafeRawPointer(cEvent).bindMemory(to: ziti_ctx_event.self, capacity: 1)
            let zEvent = ZitiTunnelContextEvent(ziti, cCtxEvent)
            mySelf.tunnelProvider?.tunnelEventCallback(zEvent)
            
            if zEvent.code == ZITI_CONTROLLER_UNAVAILABLE || zEvent.code == ZITI_DISABLED {
                mySelf.zidsLoadedCond.lock()
                mySelf.zidsToLoad -= 1
                mySelf.zidsLoadedCond.signal()
                mySelf.zidsLoadedCond.unlock()
            }
        case TunnelEvents.ServiceEvent.rawValue:
            var cServiceEvent = UnsafeRawPointer(cEvent).bindMemory(to: service_event.self, capacity: 1)
            mySelf.tunnelProvider?.tunnelEventCallback(ZitiTunnelServiceEvent(ziti, cServiceEvent))
            
            let key = "\(KEY_GOT_SERVICES)\(ziti.id.id)"
            var gotServices = ziti.userData[key] as? Bool ?? false
            if !gotServices {
                ziti.userData[key] = true
                mySelf.zidsLoadedCond.lock()
                mySelf.zidsToLoad -= 1
                mySelf.zidsLoadedCond.signal()
                mySelf.zidsLoadedCond.unlock()
            }
        case TunnelEvents.MFAEvent.rawValue:
            var cMfaAuthEvent = UnsafeRawPointer(cEvent).bindMemory(to: mfa_event.self, capacity: 1)
            mySelf.tunnelProvider?.tunnelEventCallback(ZitiTunnelMfaEvent(ziti, cMfaAuthEvent))
        case TunnelEvents.APIEvent.rawValue:
            var cApiEvent = UnsafeRawPointer(cEvent).bindMemory(to: api_event.self, capacity: 1)
            let event = ZitiTunnelApiEvent(ziti, cApiEvent)
            ziti.id.ztAPI = event.newControllerAddress
            mySelf.tunnelProvider?.tunnelEventCallback(event)
        default:
            log.warn("Unrecognized event type \(cEvent.pointee.event_type.rawValue)")
            return
        }
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
        
        let arr = parts.map { return UInt32($0)! }
        let n = (arr[0] << 24) | (arr[1] << 16) | (arr[2] << 8) | arr[3]
        log.debug("Converted IP string \"\(str)\" to \(arr) to \(String(format:"0x%02X", n))")
        return n
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
    
    static private let onLoopKeepAlive:uv_async_cb = { _ in
        // noop
    }
    
    /// Queue a packet received from the tunnel interface for processing (e.g., for intercepted services or DNS requests)
    /// - Parameters:
    ///     - data: IP packet received from the tunnel interface
    public func queuePacket(_ data:Data) {
        netifDriver.queuePacket(data)
    }
}

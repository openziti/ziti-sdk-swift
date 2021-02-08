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

class QueuedPacket : NSObject {
    let ptr:UnsafeMutablePointer<UInt8>
    let len:Int
    
    init(_ data:Data) {
        len = data.count
        ptr = UnsafeMutablePointer<UInt8>.allocate(capacity: len)
        ptr.initialize(from: [UInt8](data), count: len)
        super.init()
    }
    deinit {
        ptr.deallocate()
    }
}

class NetifDriver : NSObject, ZitiUnretained {
    private static let log = ZitiLog(NetifDriver.self)
    private let log = NetifDriver.log
    
    var tunnelProvider:ZitiTunnelProvider?
    
    var driver:UnsafeMutablePointer<netif_driver_t>!
    var packetCallback:packet_cb?
    var netif:UnsafeMutableRawPointer?
    
    var readQueue:[QueuedPacket] = []
    var queueLock = NSLock()
    var asyncHandle:uv_async_t?
    
    init(tunnelProvider:ZitiTunnelProvider) {
        self.tunnelProvider = tunnelProvider
        driver = UnsafeMutablePointer<netif_driver_t>.allocate(capacity: 1)
        driver.initialize(to: netif_driver_t())
        super.init()
    }
    
    func open() -> UnsafeMutablePointer<netif_driver_t> {
        let driver = UnsafeMutablePointer<netif_driver_t>.allocate(capacity: 1)
        driver.initialize(to: netif_driver_t())
        
        driver.pointee.handle = OpaquePointer(self.toVoidPtr())
        driver.pointee.setup = NetifDriver.setup_cb
        driver.pointee.uv_poll_init = nil // keep this nil (tunneler sdk will use setup if it exists, poll only if it doesn't)
        driver.pointee.read = NetifDriver.read_cb // empty with log message.  should never be called
        driver.pointee.write = NetifDriver.write_cb
        driver.pointee.close = NetifDriver.close_cb
        driver.pointee.add_route = NetifDriver.add_route_cb
        driver.pointee.delete_route = NetifDriver.delete_route_cb
                
        return driver
    }
    
    func close() {
        driver.deinitialize(count: 1)
        driver.deallocate()
    }
    
    func queuePacket(_ data:Data) {
        queueLock.lock()
        readQueue.append(QueuedPacket(data))
        queueLock.unlock()
        
        if asyncHandle != nil {
            uv_async_send(&(asyncHandle!))
        }
    }
    
    static let setup_cb:setup_packet_cb = { handle, loop, cb, netif in
        guard let mySelf = zitiUnretained(NetifDriver.self, UnsafeMutableRawPointer(handle)) else {
            log.wtf("invalid handle", function: "setup_cb()")
            return -1
        }
        
        mySelf.asyncHandle = uv_async_t()
        uv_async_init(loop, &(mySelf.asyncHandle!), NetifDriver.async_cb)
        mySelf.asyncHandle?.data = mySelf.toVoidPtr()
        
        mySelf.packetCallback = cb
        mySelf.netif = netif
        
        return Int32(0)
    }
    
    static let async_cb:uv_async_cb = { ctx in
        guard let mySelf = zitiUnretained(NetifDriver.self, ctx?.pointee.data) else {
            log.wtf("invalid ctx", function: "async_cb()")
            return
        }
        
        mySelf.queueLock.lock()
        let q = mySelf.readQueue
        mySelf.readQueue = []
        mySelf.queueLock.unlock()
        
        q.forEach { pkt in
            pkt.ptr.withMemoryRebound(to: Int8.self, capacity: pkt.len) {
                mySelf.packetCallback?($0, pkt.len, mySelf.netif)
            }
        }
    }
    
    static let read_cb:netif_read_cb = { handle, buf, len in
        log.error("NetifDriver Unexpected read callback for non-poll driver", function:"read_cb")
        return Int(0)
    }
    
    static let write_cb:netif_write_cb = { handle, buf, len in
        guard let mySelf = zitiUnretained(NetifDriver.self, UnsafeMutableRawPointer(handle)) else {
            log.wtf("invalid handle", function: "write_cb()")
            return -1
        }
        guard let tunnelProvider = mySelf.tunnelProvider else {
            log.wtf("invalid tunnelProvider", function: "write_cb()")
            return -1
        }
        autoreleasepool {
            if let ptr = UnsafeMutableRawPointer(mutating: buf) {
                let data = Data(bytesNoCopy: ptr, count: len, deallocator: .none)
                tunnelProvider.writePacket(data)
            }
        }
        return len
    }
    
    static let close_cb:netif_close_cb = { handle in
        guard let mySelf = zitiUnretained(NetifDriver.self, UnsafeMutableRawPointer(handle)) else {
            log.wtf("invalid handle", function: "close_cb()")
            return -1
        }
        mySelf.close()
        return Int32(0)
    }
    
    static let add_route_cb:add_route_cb = { handle, dest in
        guard let mySelf = zitiUnretained(NetifDriver.self, UnsafeMutableRawPointer(handle)) else {
            log.wtf("invalid handle", function: "add_route_cb()")
            return -1
        }
        guard let tunnelProvider = mySelf.tunnelProvider else {
            log.wtf("invalid tunnelProvider", function: "add_route_cb()")
            return -1
        }
        guard let destStr = dest != nil ? String(cString: dest!) : nil else {
            log.error("Invalid dest paramater", function: "add_route_cb()")
            return -1
        }
        return tunnelProvider.addRoute(destStr)
    }
    
    static let delete_route_cb:delete_route_cb = { handle, dest in
        guard let mySelf = zitiUnretained(NetifDriver.self, UnsafeMutableRawPointer(handle)) else {
            log.wtf("invalid handle", function: "delete_route_cb()")
            return -1
        }
        guard let tunnelProvider = mySelf.tunnelProvider else {
            log.wtf("invalid tunnelProvider", function: "delete_route_cb()")
            return -1
        }
        guard let destStr = dest != nil ? String(cString: dest!) : nil else {
            log.error("Invalid dest paramater", function: "delete_route_cb()")
            return -1
        }
        return tunnelProvider.deleteRoute(destStr)
    }
}

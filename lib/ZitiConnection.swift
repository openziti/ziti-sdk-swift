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
import CZitiPrivate

/// Create `ZitiConnection`s from an instance of `Ziti` and use to commuicate with services over a Ziti network
@objc public class ZitiConnection : NSObject, ZitiUnretained {
    private static let log = ZitiLog(ZitiConnection.self)
    private let log = ZitiConnection.log
    
    weak var ziti:Ziti?
    var zConn:ziti_connection?
    
    var onConn:ConnCallback?
    var onListen:ListenCallback?
    var onData:DataCallback?
    var onClient:ClientCallback?
    var onClose:CloseCallback?
    
    init(_ ziti:Ziti, _ zConn:ziti_connection?) {
        self.ziti = ziti
        self.zConn = zConn
        super.init()
        ziti_conn_set_data(zConn, self.toVoidPtr())
        log.debug("init \(self)")
    }
    
    deinit {
        log.debug("deinit \(self)")
    }
    
    
    /// Connection callback
    ///
    /// This callback is invoked after `dial(_:_:_:)` or `accept(_:_:)` is completed. The result of the function may be an error condition so it is
    /// important to verify the status code in this callback. If successful the status will be set to `ZITI_OK`
    ///
    /// - Parameters:
    ///     - conn: refernce to `ZitiConnection`
    ///     - status: `ZITI_OK` on success, else Ziti error code
    public typealias ConnCallback = (_ conn:ZitiConnection, _ status:Int32) -> Void
    
    /// Listen callback
    ///
    /// This callback is invoked after `listen(_:_:_:)` and is aliased to `ConnCallback` as a convenience for human readability
    public typealias ListenCallback = ConnCallback
    
    /// Data callback
    ///
    /// This callback is invoked when data arrives from `Ziti`, either as a response from `dial(_:_:_:)` or from `accept(_:_:)`
    /// Return value should indicate how much data was consumed by the application. This callback will be called again at some later
    /// time and as many times as needed for application to accept the all of the data
    ///
    /// - Parameters:
    ///     - conn: the connection
    ///     - data: the incoming data
    ///     - status: size of the data or a Ziti error code, `ZITI_EOF` when connection has closed
    public typealias DataCallback = (_ conn:ZitiConnection, _ data:Data?, _ status:Int) -> Int
    
    /// Client callback
    ///
    /// This callback is invoked when a client connects to the service specified in `listen(_:_:_:)` call. The result of the status may be an error condition so it is
    /// important to verify the status code in this callback. If successful the status will be set to `ZITI_OK`
    ///
    /// Generally this callback is used for any preparations necessary before accepting incoming data from the Ziti network.
    ///
    /// - Parameters:
    ///     - server: server connection
    ///     - client: client connection, generally used to `accept()`the connection in this callback
    ///     - status: `ZITI_OK` or error code
    ///
    public typealias ClientCallback = (_ server:ZitiConnection, _ client:ZitiConnection, _ status:Int32) -> Void
    
    /// Write callback
    ///
    /// This callback is invoked after a call the `write(_:_:)` completes. The result of the `write(_:_:)` may be an error condition so it is
    /// important to verify the provided status code in this callback.
    ///
    /// This callback is often used to free or reinitialize the buffer associated with the `write(_:_:)`. It is important to not free this memory
    /// until after data has been written to the wire else the results of the write operation may be unexpected.
    ///
    /// - Parameters:
    ///     - status: amount of data written or Ziti error code
    public typealias WriteCallback = (_ conn:ZitiConnection, _ status:Int) -> Void
    
    /// Close callback
    ///
    /// This callback is invoked after a call the `close(_:)` completes.
    ///
    /// - Parameters:
    ///     - status: amount of data written or Ziti error code
    public typealias CloseCallback = () -> Void
    
    /// Established a connection to a `Ziti` service.
    ///
    /// Before any bytes can be sent over a `Ziti`service a connection must be established. This method will attempt to establish a connection
    /// by dialiing the service with the given name. The result of the `dial()` attempt is included in the specified `ConnCallback`.
    ///
    /// If the `dial` succeeds, the provided `DataCallback` is invoked to handle data returned from the service. If the `dial` fails, only
    /// the `ConnCallback` will be invoked with the corresponding error code
    ///
    /// - Parameters:
    ///     - service: name of the service to dial
    ///     - onConn: callback invoked after `dial` attempt completes
    ///     - onData: callback invoked after a successful `dial` attempt with data received over the connection
    @objc public func dial(_ service:String, _ onConn: @escaping ConnCallback, _ onData: @escaping DataCallback) {
        guard let ziti = self.ziti else {
            log.wtf("invalid (nil) ziti reference")
            return
        }
        ziti.perform {
            self.onConn = onConn
            self.onData = onData
            
            let status = ziti_dial(self.zConn, service.cString(using: .utf8), ZitiConnection.onConn, ZitiConnection.onData)
            guard status == ZITI_OK else {
                self.log.error("\(status): " + String(cString: ziti_errorstr(status)))
                onConn(self, status)
                return
            }
        }
    }
    
    /// Start accepting `Ziti` client connections
    ///
    /// This function is invoked to tell the `Ziti` to  accept connections from other `Ziti` clients for the provided service name.
    ///
    /// - Parameters:
    ///     - service: name of the service to be hosted
    ///     - onListen: callback invoked indicating success or failure of `listen` attempt
    ///     - onClient: callback invoked when client attempts to dial this service
    @objc public func listen(_ service:String, _ onListen: @escaping ListenCallback, _ onClient: @escaping ClientCallback) {
        guard let ziti = self.ziti else {
            log.wtf("invalid (nil) ziti reference")
            return
        }
        ziti.perform {
            self.onListen = onListen
            self.onClient = onClient
            
            let status = ziti_listen(self.zConn, service.cString(using: .utf8), ZitiConnection.onListen, ZitiConnection.onClient)
            guard status == ZITI_OK else {
                self.log.error("\(status): " + String(cString: ziti_errorstr(status)))
                onListen(self, status)
                return
            }
        }
    }
    
    /// Completes a client connection
    ///
    /// After a client connects to a hosted Ziti service this method is invoked to finish  connection establishment, establishing
    /// the callbacks necessary to send data to the connecting client or to process data sent by the client.
    ///
    /// - Parameters:
    ///     - onConn:invoked when `accept` completes indicating status of the attempt
    ///     - onData: invoked each time the client sends data
    @objc public func accept(_ onConn: @escaping ConnCallback, _ onData: @escaping DataCallback) {
        guard let ziti = self.ziti else {
            log.wtf("invalid (nil) ziti reference")
            return
        }
        ziti.perform {
            self.onConn = onConn
            self.onData = onData
            
            let status = ziti_accept(self.zConn, ZitiConnection.onConn, ZitiConnection.onData)
            guard status == ZITI_OK else {
                self.log.error("\(status): " + String(cString: ziti_errorstr(status)))
                onConn(self, status)
                return
            }
        }
    }
    
    /// Get the identity of the client that initiated the Ziti connection
    ///
    /// - Returns: Source ID or empty String
    ///
    @objc public func getSourceIdentity() -> String {
        var id = ""
        if let source_id = ziti_conn_source_identity(self.zConn) {
            id = String(cString: source_id)
        }
        return id
    }
    
    /// Send data to the connection peer
    ///
    /// - Parameters:
    ///     - data: the data to send
    ///     - onWrite:callback invoked after the `write` completes
    ///
    @objc public func write(_ data:Data, _ onWrite: @escaping WriteCallback) {
        guard let ziti = self.ziti else {
            log.wtf("invalid (nil) ziti reference")
            return
        }
        ziti.perform {
            let writeReq = WriteRequest(self, onWrite, data)
            let status = ziti_write(self.zConn, writeReq.ptr, writeReq.len, ZitiConnection.onWrite, writeReq.toVoidPtr())
            guard status == ZITI_OK else {
                self.log.error("\(status): " + String(cString: ziti_errorstr(status)))
                onWrite(self, Int(status))
                return
            }
            self.writeRequests.append(writeReq)
        }
    }
    
    /// Close this connection
    ///
    /// When no longer needed the connection should be closed to gracefully disconnect. This method should be invoked after any status is returned
    /// which indicates an error situation.
    ///
    /// - Parameters:
    ///     - onClose: called when connection is completely closed
    ///
    @objc public func close(_ onClose: CloseCallback? = nil) {
        ziti?.perform {
            self.onClose = onClose
            ziti_close(self.zConn, ZitiConnection.onClose)
            self.ziti?.releaseConnection(self)
        }
    }
    
    // MARK: - Static C callbacks
    static private let onConn:ziti_conn_cb = { conn, status in
        guard let conn = conn, let ctx = ziti_conn_data(conn), let mySelf = zitiUnretained(ZitiConnection.self, ctx) else {
            log.wtf("invalid context", function:"onConn()")
            return
        }
        mySelf.onConn?(mySelf, status)
    }
    
    static private let onClose:ziti_close_cb = { conn in
        guard let conn = conn, let ctx = ziti_conn_data(conn), let mySelf = zitiUnretained(ZitiConnection.self, ctx) else {
            log.wtf("invalid context", function:"onClose()")
            return
        }
        mySelf.onClose?()
    }
    
    static private let onData:ziti_data_cb = { conn, buf, len in
        guard let conn = conn, let ctx = ziti_conn_data(conn), let mySelf = zitiUnretained(ZitiConnection.self, ctx) else {
            log.wtf("invalid context", function:"onConn()")
            return 0
        }
        
        var status:Int
        if len > 0 && buf != nil {
            let data = Data(bytes: buf!, count: len)
            status = mySelf.onData?(mySelf, data, len) ?? 0
        } else {
            log.info(String(cString: ziti_errorstr(Int32(len))), function:"onData()")
            status = mySelf.onData?(mySelf, Data(), len) ?? 0
        }
        return status
    }
    
    static private let onListen:ziti_listen_cb = { conn, status in
        guard let conn = conn, let ctx = ziti_conn_data(conn), let mySelf = zitiUnretained(ZitiConnection.self, ctx) else {
            log.wtf("invalid context", function:"onListen()")
            return
        }
        mySelf.onListen?(mySelf, status)
    }
    
    static private let onClient:ziti_client_cb = { svr, client, status, _ in
        guard let svr = svr, let ctx = ziti_conn_data(svr), let mySelf = zitiUnretained(ZitiConnection.self, ctx) else {
            log.wtf("invalid context", function:"onClient()")
            return
        }
        guard let ziti = mySelf.ziti else {
            log.wtf("invalid ziti reference", function:"onClient()")
            return
        }
        let zc = ZitiConnection(ziti, client)
        ziti.retainConnection(zc)
        mySelf.onClient?(mySelf, zc, status)
    }
    
    static private let onWrite:ziti_write_cb = { conn, len, ctx in
        guard let ctx = ctx, let req = zitiUnretained(WriteRequest.self, ctx) else {
            log.wtf("invalid ctx", function:"onWrite()")
            return
        }
        if let zitiConn = req.zitiConn {
            zitiConn.writeRequests = zitiConn.writeRequests.filter() { $0 !== req }
            req.onWrite(zitiConn, len)
        }
    }
    
    // MARK: - Helpers
    class WriteRequest : ZitiUnretained {
        weak var zitiConn:ZitiConnection?
        let onWrite:WriteCallback
        let ptr:UnsafeMutablePointer<UInt8>
        let len:Int
        init(_ zitiConn:ZitiConnection, _ onWrite: @escaping WriteCallback, _ data:Data) {
            len = data.count
            ptr = UnsafeMutablePointer<UInt8>.allocate(capacity: len)
            ptr.initialize(from: [UInt8](data), count: len)
            self.zitiConn = zitiConn
            self.onWrite = onWrite
            ZitiConnection.log.debug("init \(self). len: \(len)")
        }
        deinit {
            ZitiConnection.log.debug("deinit \(self). len: \(len)")
            ptr.deinitialize(count: len)
            ptr.deallocate()
        }
    }
    var writeRequests:[WriteRequest] = []
}

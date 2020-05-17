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

/// Create `ZitiConnection`s from an instance of `Ziti` and use to commuicate with services over a Ziti network
@objc public class ZitiConnection : NSObject, ZitiUnretained {
    private static let log = ZitiLog(ZitiConnection.self)
    private let log = ZitiConnection.log
    
    weak var ziti:Ziti?
    var nfConn:nf_connection?
    
    var onConn:ConnCallback?
    var onListen:ListenCallback?
    var onData:DataCallback?
    var onClient:ClientCallback?
    
    init(_ ziti:Ziti, _ nfConn:nf_connection?) {
        self.ziti = ziti
        self.nfConn = nfConn
        super.init()
        NF_conn_set_data(nfConn, self.toVoidPtr())
        log.debug("init \(self)")
    }
    
    deinit {
        log.debug("deinit \(self)")
    }
    
    
    /// Connection callback
    ///
    /// This callback is invoked after `dial()` or `accept()` is completed. The result of the function may be an error condition so it is
    /// important to verify the status code in this callback. If successful the status will be set to `ZITI_OK`
    ///
    /// - Parameters:
    ///     - status: `ZITI_OK` on success, else Ziti error code
    public typealias ConnCallback = (_ status:Int32) -> Void
    
    /// Listen callback
    ///
    /// This callback is invoked after `listen()` and is aliased to `ConnCallback` as a convenience for human readability
    public typealias ListenCallback = ConnCallback
    
    /// Data callback
    ///
    /// This callback is invoked when data arrives from `Ziti`, either as a response from `dial()` or from `accept()`
    /// Return value should indicate how much data was consumed by the application. This callback will be called again at some later
    /// time and as many times as needed for application to accept the all of the data
    ///
    /// - Parameters:
    ///     - data: the incoming data
    ///     - status: size of the data or a Ziti error code, `ZITI_EOF` when connection has closed
    public typealias DataCallback = (_ data:Data?, _ status:Int) -> Int
    
    /// Client callback
    ///
    /// This callback is invoked when a client connects to the service specified in `listen()` call. The result of the status may be an error condition so it is
    /// important to verify the status code in this callback. If successful the status will be set to `ZITI_OK`
    ///
    /// Generally this callback is used for any preparations necessary before accepting incoming data from the Ziti network.
    ///
    /// - Parameters:
    ///     - client: client connection, generally used to `accept()`the connection in this callback
    ///     - status: `ZITI_OK` or error code
    ///
    public typealias ClientCallback = (_ client:ZitiConnection?, _ status:Int32) -> Void
    
    /// Write callback
    ///
    /// This callback is invoked after a call the `write()` completes. The result of the `write()` may be an error condition so it is
    /// important to verify the provided status code in this callback.
    ///
    /// This callback is often used to free or reinitialize the buffer associated with the `write()`. It is important to not free this memory
    /// until after data has been written to the wire else the results of the write operation may be unexpected.
    ///
    /// - Parameters:
    ///     - status: amount of data written or Ziti error code
    public typealias WriteCallback = (_ status:Int) -> Void
    
    /// Established a connection to a `Ziti` service.
    ///
    /// Before any bytes can be sent over a `Ziti`service a connection must be established. This method will attempt to establish a connection
    /// by dialiing the service with the given name. The result of the `dial()` attempt is included in the specified `ConnCallback`.
    ///
    /// If the `dial()` succeeds, the provided `DataCallback` is invoked to handle data returned from the service. If the `dial()` fails, only
    /// the `ConnCallback` will be invoked with the corresponding error code
    ///
    /// - Parameters:
    ///     - service: name of the service to dial
    ///     - onConn: callback invoked after `dial()` attempt completes
    ///     - onData: callback invoked after a successful `dial()` attempt with data received over the connection
    @objc public func dial(_ service:String, _ onConn: @escaping ConnCallback, _ onData: @escaping DataCallback) {
        guard let ziti = self.ziti else {
            log.wtf("invalid (nil) ziti reference")
            return
        }
        ziti.perform {
            self.onConn = onConn
            self.onData = onData
            
            let status = NF_dial(self.nfConn, service.cString(using: .utf8), ZitiConnection.onConn, ZitiConnection.onData)
            guard status == ZITI_OK else {
                self.log.error("\(status): " + String(cString: ziti_errorstr(status)))
                onConn(status)
                return
            }
        }
    }
    
    /// Start accepting `Ziti` client connections
    ///
    /// This function is invoked to tell the `Ziti`to  accept connections from other `Ziti` clients for the provided service name.
    ///
    /// - Parameters:
    ///     - service: name of the service to be hosted
    ///     - onListen: callback invoked indicating success or failure of `listen()` attempt
    ///     - onClient: callback invoked when client attempts to dial this service
    @objc public func listen(_ service:String, _ onListen: @escaping ListenCallback, _ onClient: @escaping ClientCallback) {
        guard let ziti = self.ziti else {
            log.wtf("invalid (nil) ziti reference")
            return
        }
        ziti.perform {
            self.onListen = onListen
            self.onClient = onClient
            
            let status = NF_listen(self.nfConn, service.cString(using: .utf8), ZitiConnection.onListen, ZitiConnection.onClient)
            guard status == ZITI_OK else {
                self.log.error("\(status): " + String(cString: ziti_errorstr(status)))
                onListen(status)
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
    ///     - onConn:invoked when `accept()` completes indicating status of the attempt
    ///     - onData: invoked each time the client sends data
    @objc public func accept(_ onConn: @escaping ConnCallback, _ onData: @escaping DataCallback) {
        guard let ziti = self.ziti else {
            log.wtf("invalid (nil) ziti reference")
            return
        }
        ziti.perform {
            self.onConn = onConn
            self.onData = onData
            
            let status = NF_accept(self.nfConn, ZitiConnection.onConn, ZitiConnection.onData)
            guard status == ZITI_OK else {
                self.log.error("\(status): " + String(cString: ziti_errorstr(status)))
                onConn(status)
                return
            }
        }
    }
    
    /// Send data to the connection peer
    ///
    /// - Parameters:
    ///     - data: the data to send
    ///     - onWrite:callback invoked after the `write()` completes
    ///
    @objc public func write(_ data:Data, _ onWrite: @escaping WriteCallback) {
        guard let ziti = self.ziti else {
            log.wtf("invalid (nil) ziti reference")
            return
        }
        ziti.perform {
            let writeReq = WriteRequest(self, onWrite, data)
            let status = NF_write(self.nfConn, writeReq.ptr, writeReq.len, ZitiConnection.onWrite, writeReq.toVoidPtr())
            guard status == ZITI_OK else {
                self.log.error("\(status): " + String(cString: ziti_errorstr(status)))
                onWrite(Int(status))
                return
            }
            self.writeRequests.append(writeReq)
        }
    }
    
    /// Close this connection
    ///
    /// When no longer needed the connection should be closed to gracefully disconnect. This method should be invoked after any status is returned
    /// which indicates an error situation.
    @objc public func close() {
        ziti?.perform {
            NF_close(&self.nfConn)
        }
    }
    
    // MARK: - Static C callbacks
    static private let onConn:nf_conn_cb = { conn, status in
        guard let conn = conn, let ctx = NF_conn_data(conn), let mySelf = zitiUnretained(ZitiConnection.self, ctx) else {
            log.wtf("invalid context", function:"onConn()")
            return
        }
        mySelf.onConn?(status)
    }
    
    static private let onData:nf_data_cb = { conn, buf, len in
        guard let conn = conn, let ctx = NF_conn_data(conn), let mySelf = zitiUnretained(ZitiConnection.self, ctx) else {
            log.wtf("invalid context", function:"onConn()")
            return 0
        }
        
        var status:Int
        if len > 0 && buf != nil {
            let data = Data(bytes: buf!, count: len)
            status = mySelf.onData?(data, len) ?? 0
        } else {
            log.info(String(cString: ziti_errorstr(Int32(len))), function:"onData()")
            status = mySelf.onData?(Data(), len) ?? 0
        }
        return status
    }
    
    static private let onListen:nf_listen_cb = { conn, status in
        guard let conn = conn, let ctx = NF_conn_data(conn), let mySelf = zitiUnretained(ZitiConnection.self, ctx) else {
            log.wtf("invalid context", function:"onListen()")
            return
        }
        mySelf.onListen?(status)
    }
    
    static private let onClient:nf_client_cb = { svr, client, status in
        guard let svr = svr, let ctx = NF_conn_data(svr), let mySelf = zitiUnretained(ZitiConnection.self, ctx) else {
            log.wtf("invalid context", function:"onClient()")
            return
        }
        guard let ziti = mySelf.ziti else {
            log.wtf("invalid ziti reference", function:"onClient()")
            return
        }
        let zitiConn = ZitiConnection(ziti, client)
        mySelf.onClient?(zitiConn, status)
    }
    
    static private let onWrite:nf_write_cb = { conn, len, ctx in
        guard let ctx = ctx, let req = zitiUnretained(WriteRequest.self, ctx) else {
            log.wtf("invalid ctx", function:"onWrite()")
            return
        }
        if let zitiConn = req.zitiConn {
            zitiConn.writeRequests = zitiConn.writeRequests.filter() { $0 !== req }
        }
        req.onWrite(len)
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

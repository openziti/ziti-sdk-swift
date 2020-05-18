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
import ZitiUrlProtocol

var ziti:Ziti?

// Server callbacks
let onListen:ZitiConnection.ListenCallback = { serv, status in
    let statMsg = String(cString: ziti_errorstr(status))
    if (status == ZITI_OK) {
        print("Byte Counter is ready! \(status)(\(statMsg))")
    }
    else {
        fputs("ERROR The Byte Counter could not be started: \(status)(\(statMsg))\n", stderr)
        serv.close()
    }
}

let onAccept:ZitiConnection.ConnCallback = { conn, status in
    guard status == ZITI_OK else {
        let errStr = String(cString: ziti_errorstr(status))
        fputs("Client accept error: \(status)(\(errStr))\n", stderr)
        return
    }
    
    if var msg = String("Hello from byte counter!\n").data(using: .utf8) {
        msg.append(0) // TODO: needed?
        conn.write(msg) { _, len in
            guard len >= 0 else {
                let errStr = String(cString: ziti_errorstr(Int32(len)))
                fputs("Connected client write error: \(len)(\(errStr)\n", stderr)
                return
            }
            print("Sent \(len) bytes to connected client")
        }
    }
}

let onDataFromClient:ZitiConnection.DataCallback = { conn, data, len in
    guard len > 0 else {
        let errStr = String(cString: ziti_errorstr(Int32(len)))
        fputs("onDataFromClient: \(len)(\(errStr)\n", stderr)
        return 0
    }
    
    let msg = data != nil ? (String(data: data!, encoding: .utf8) ?? "") : ""
    print("client sent us \(len) bytes, msg: \(msg)")
    
    // write back num bytes conn.write(...)
    if var response = String("\(len)").data(using: .utf8) {
        response.append(0) // TODO: needed?
        print("Responding to client with \(len)")
        conn.write(response) { _, len in
            guard len >= 0 else {
                let errStr = String(cString: ziti_errorstr(Int32(len)))
                fputs("Error writing to client: \(len)(\(errStr)\n", stderr)
                return
            }
            print("Sent \(len) bytes to client")
        }
    }
    return data?.count ?? 0
}

// Client callbacks
let onDial:ZitiConnection.ConnCallback = { conn, status in
    guard status == ZITI_OK else {
        let errStr = String(cString: ziti_errorstr(status))
        fputs("onDial :\(status)(\(errStr)", stderr)
        return
    }
    
    if var msg = String("hello").data(using: .utf8) {
        msg.append(0) // TODO: needed?
        conn.write(msg) { _, len in
            guard len >= 0 else {
                let errStr = String(cString: ziti_errorstr(Int32(len)))
                fputs("Dialed connection write error: \(len)(\(errStr)\n", stderr)
                return
            }
            print("Sent \(len) bytes to server")
        }
    }
}

let onDataFromServer:ZitiConnection.DataCallback = { conn, data, len in
    guard len > 0 else {
        let errStr = String(cString: ziti_errorstr(Int32(len)))
        fputs("onDataFromServer: \(len)\(errStr)", stderr)
        conn.close()
        ziti?.shutdown()
        return 0
    }
    
    let msg = data != nil ? (String(data: data!, encoding: .utf8) ?? "") : ""
    print("Server sent us \(len) bytes, msg: \(msg)")
    return data?.count ?? 0
}

// Parse command line
let args = CommandLine.arguments
if CommandLine.argc != 4 {
    fputs("Usage: \(args[0]) <client|server> <config-file> <service-name>\n", stderr);
    exit(1);
}

let isServer = (args[1] == "server")
print("Running as \(isServer ? "server" : "client")")

let zidFile = args[2]
let service = args[3]

// Load ziti instance from zid file
ziti = Ziti(fromFile: zidFile)
guard let ziti = ziti  else {
    fputs("Unable to load Ziti from zid file \(zidFile)\n", stderr)
    exit(1)
}

// Run ziti
ziti.run { zErr in
    guard zErr == nil else {
        fputs("Unable to run ziti \(String(describing: zErr))\n", stderr)
        exit(1)
    }
    guard let conn = ziti.createConnection() else {
        fputs("Unable to create connection\n", stderr)
        exit(1)
    }
    
    if isServer {
        conn.listen(service, onListen) { server, client, status in
            guard status == ZITI_OK else {
                fputs("onClient \(status): \(String(cString: ziti_errorstr(status)))", stderr)
                return
            }
            client.accept(onAccept, onDataFromClient)
        }
    } else {
        conn.dial(service, onDial, onDataFromServer)
    }
}

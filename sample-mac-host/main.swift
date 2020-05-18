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

// Commandline
let args = CommandLine.arguments
if CommandLine.argc != 4 {
    fputs("Usage: \(args[0]) <client|server> <config-file> <service-name>\n", stderr);
    exit(1);
}

let isServer = (args[1] == "server")
print("Running as \(isServer ? "server" : "client")")

let zidFile = args[2]
let service = args[3]

// load ziti instance from zid file
guard let ziti = Ziti(fromFile: zidFile) else {
    fputs("Unable to load Ziti from zid file \(zidFile)\n", stderr)
    exit(1)
}

// connection callbacks
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

let onClientAccept:ZitiConnection.ConnCallback = { conn, status in
    guard status == ZITI_OK else {
        let errStr = String(cString: ziti_errorstr(status))
        fputs("client accept error \(status): \(errStr)", stderr)
        return
    }
    
    if var msg = String("Hello from byte counter!\n").data(using: .utf8) {
        msg.append(0) // TODO: needed?
        conn.write(msg) { _, len in
            guard len >= 0 else {
                let errStr = String(cString: ziti_errorstr(Int32(len)))
                fputs("connected client write error \(len): \(errStr)", stderr)
                return
            }
            print("sent \(len) bytes to connected client")
        }
    }
}

let onDial:ZitiConnection.ConnCallback = { conn, status in
    guard status == ZITI_OK else {
        let errStr = String(cString: ziti_errorstr(status))
        fputs("onDial error \(status): \(errStr)", stderr)
        return
    }
    
    if var msg = String("hello").data(using: .utf8) {
        msg.append(0) // TODO: needed?
        conn.write(msg) { _, len in
            guard len >= 0 else {
                let errStr = String(cString: ziti_errorstr(Int32(len)))
                fputs("dialed connection write error \(len): \(errStr)", stderr)
                return
            }
            print("sent \(len) bytes over dialed connection")
        }
    }
}

// run ziti
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
            client.accept(onClientAccept) { conn, data, len in
                guard len > 0 else {
                    let errStr = String(cString: ziti_errorstr(Int32(len)))
                    fputs("accepted client onData \(len): \(errStr)", stderr)
                    return 0
                }
                
                let msg = data != nil ? (String(data: data!, encoding: .utf8) ?? "nil string") : "nil data"
                print("accepted client sent us \(len) bytes, msg: \(msg)")
                
                // write back num bytes conn.write(...)
                if var response = String("\(len)").data(using: .utf8) {
                    response.append(0) // TODO: needed?
                    print("responding to client with \(len)")
                    conn.write(response) { _, len in
                        guard len >= 0 else {
                            let errStr = String(cString: ziti_errorstr(Int32(len)))
                            fputs("write error to accepted client \(len): \(errStr)", stderr)
                            return
                        }
                        print("sent \(len) bytes over accepted connection")
                    }
                    
                }
                return data?.count ?? 0
            }
        }
    } else {
        conn.dial(service, onDial) { conn, data, len in
            guard len > 0 else {
                let errStr = String(cString: ziti_errorstr(Int32(len)))
                fputs("dialed client onData \(len): \(errStr)", stderr)
                conn.close()
                ziti.shutdown()
                return 0
            }
            
            let msg = data != nil ? (String(data: data!, encoding: .utf8) ?? "") : ""
            print("dialed connection sent us \(len) bytes, msg: \(msg)")
            return data?.count ?? 0
        }
    }
}

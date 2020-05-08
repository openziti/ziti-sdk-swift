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

// CommandLine
let args = CommandLine.arguments
guard CommandLine.argc == 2 else {
    let nm = URL(fileURLWithPath: args[0]).lastPathComponent
    print("Usage: \(nm) file.jwt")
    exit(-1)
}

// Enroll
let loop = uv_default_loop()
let enroller = ZitiEnroller()

enroller.enroll(loop: loop, jwtFile: args[1]) { resp, subj, err in
    guard let resp = resp, let subj = subj else {
        print("Invalid enrollment response, \(String(describing: err))")
        exit(-3)
    }
    
    #if false
    print("Identity JSON:" +
        "\nsubj: \(subj)" +
        "\nztAPI: \(resp.ztAPI)" +
        "\nid.key: \(resp.id.key)" +
        "\nid.cert: \(resp.id.cert)" +
        "\nid.ca: \(resp.id.ca ?? "")" +
        "\n")
    #endif
    
    // update keychain for this identity
    
    // tell the user the id...
    print("Successfully enrolled id \"\(subj)\" with controller \"\(resp.ztAPI)\"")
}

// start the loop, exit when processing complete
ziti_debug_level = 3
exit(uv_run(loop, UV_RUN_DEFAULT))



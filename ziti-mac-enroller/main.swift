//
//  main.swift
//  ziti-mac-enroller
//
//  Created by David Hart on 5/7/20.
//

import Foundation
import ZitiUrlProtocol

let args = CommandLine.arguments
guard CommandLine.argc == 2 else {
    let nm = URL(fileURLWithPath: args[0]).lastPathComponent
    print("Usage: \(nm) file.jwt")
    exit(-1)
}

let jwtFile = args[1]
let loop = uv_default_loop()
let enroller = ZitiEnroller()

enroller.enroll(loop: loop, jwtFile: jwtFile) { resp, err in
    guard let resp = resp else {
        print("Invalid enrollment response, \(String(describing: err))")
        exit(-2)
    }
    
    print("Identity JSON:" +
        "\nztAPI: \(resp.ztAPI)" +
        "\nid.key: \(resp.id.key)" +
        "\nid.cert: \(resp.id.cert)" +
        "\nid.ca: \(resp.id.ca ?? "")" +
        "\n")
    
    // TODO: update keychain for this identity
}

ziti_debug_level = 4
let status = uv_run(loop, UV_RUN_DEFAULT)
exit(status)



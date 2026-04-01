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
import CZiti

ZitiLog.setLogLevel(.INFO)

let args = CommandLine.arguments
let nm = URL(fileURLWithPath: args[0]).lastPathComponent

func usage() {
    print("Usage:")
    print("  \(nm) file.jwt out.zid [--trustca]       Enroll with JWT (OTT or network)")
    print("  \(nm) --url <url> out.zid [--trustca]     Enroll with controller URL (public CA)")
}

// Parse --url mode vs JWT mode
var isUrlMode = false
var urlStr:String?
var jwtFile:String?
var outFile:String?
var trustCa = false

if CommandLine.argc >= 3 && args[1] == "--url" {
    isUrlMode = true
    guard CommandLine.argc >= 4 else { usage(); exit(-1) }
    urlStr = args[2]
    outFile = args[3]
    trustCa = (CommandLine.argc >= 5 && args[4] == "--trustca")
} else {
    guard CommandLine.argc >= 3 else { usage(); exit(-1) }
    jwtFile = args[1]
    outFile = args[2]
    if CommandLine.argc == 4 && args[3] != "--trustca" { usage(); exit(-1) }
    trustCa = (CommandLine.argc == 4)
}

func trustCaIfNeeded(_ zid:ZitiIdentity) {
    guard trustCa, let ca = zid.ca else {
        exit(0)
        return
    }
    let zkc = ZitiKeychain(tag: zid.id)
    let certs = zkc.extractCerts(ca)

    let dispQueue = DispatchQueue.main
    let dispGroup = DispatchGroup()

    dispGroup.enter()
    dispQueue.async {
        print("Evaluating trust for CA")
        let status = zkc.evalTrustForCertificates(certs, dispQueue) { secTrust, isTrusted, err in
            defer { dispGroup.leave() }

            print("CA already trusted? \(isTrusted)")

            if !isTrusted {
                guard zkc.addCaPool(ca) else {
                    fputs("Unable to add CA pool to keychain\n", stderr)
                    return
                }
                print("Added CA pool to Keychain")

                if let rootCA = zkc.extractRootCa(ca) {
                    let status = zkc.addTrustForCertificate(rootCA)
                    if status != errSecSuccess {
                        let errStr = SecCopyErrorMessageString(status, nil) as String? ?? "\(status)"
                        fputs("Unable to add trust for CA: \(errStr)\n", stderr)
                    } else {
                        print("User has allowed trust of CA")
                    }
                }
            }
        }
        guard status == errSecSuccess else {
            let errStr = SecCopyErrorMessageString(status, nil) as String? ?? "\(status)"
            fputs("Unable to evaluate trust for ca, err: \(status), \(errStr)\n", stderr)
            exit(status)
        }
    }

    dispGroup.notify(queue: dispQueue) {
        exit(0)
    }
    dispatchMain()
}

if isUrlMode {
    // EnrollToCert via controller URL (requires public CA)
    Ziti.enrollToCert(controllerURL: urlStr!, onAuth: { url in
        print("Authenticate at: \(url)")
    }) { zid, zErr in
        guard let zid = zid else {
            fputs("EnrollToCert failed, \(String(describing: zErr))\n", stderr)
            exit(-1)
        }
        guard zid.save(outFile!) else {
            fputs("Unable to save to file \(outFile!)\n", stderr)
            exit(-1)
        }

        print("Successfully enrolled id \"\(zid.id)\" with controller \"\(zid.ztAPI)\"")

        trustCaIfNeeded(zid)
    }
    dispatchMain()
} else {
    // Enroll with JWT - handles both OTT and network JWTs
    Ziti.enroll(jwtFile!, onAuth: { url in
        print("Authenticate at: \(url)")
    }) { zid, zErr in
        guard let zid = zid else {
            fputs("Enrollment failed, \(String(describing: zErr))\n", stderr)
            exit(-1)
        }
        guard zid.save(outFile!) else {
            fputs("Unable to save to file \(outFile!)\n", stderr)
            exit(-1)
        }

        print("Successfully enrolled id \"\(zid.id)\" with controller \"\(zid.ztAPI)\"")

        trustCaIfNeeded(zid)
    }
    dispatchMain()
}

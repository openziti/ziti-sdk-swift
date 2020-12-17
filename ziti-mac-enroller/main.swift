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
import CZiti

func usage() {
    let nm = URL(fileURLWithPath: args[0]).lastPathComponent
    print("Usage: \(nm) file.jwt out.zid [--trustca]")
}

// CommandLine
let args = CommandLine.arguments
guard CommandLine.argc >= 3 else {
    usage()
    exit(-1)
}
if CommandLine.argc == 4 && args[3] != "--trustca" {
    usage()
    exit(-1)
}
let jwtFile = args[1]
let outFile = args[2]
let trustCa = (CommandLine.argc == 4)

// Enroll
Ziti.enroll(jwtFile) { zid, zErr in
    guard let zid = zid else {
        fputs("Invalid enrollment response, \(String(describing: zErr))\n", stderr)
        exit(-1)
    }
    guard zid.save(outFile) else {
        fputs("Unable to save to file \(outFile)\n", stderr)
        exit(-1)
    }
    
    print("Successfully enrolled id \"\(zid.id)\" with controller \"\(zid.ztAPI)\"")
        
    // Add the optional CA to keychain if not already trusted
    if trustCa, let ca = zid.ca {
        let zkc = ZitiKeychain(tag: zid.id)
        let certs = zkc.extractCerts(ca)
        
        // evalTrustForCertificates requires same DispatchQueue as caller, so force that to happen.
        // need to process the queue, block until done
        let dispQueue = DispatchQueue.main
        let dispGroup = DispatchGroup()
        
        dispGroup.enter()
        dispQueue.async {
            print("Evaluating trust for CA")
            let status = zkc.evalTrustForCertificates(certs, dispQueue) { secTrust, isTrusted, err in
                defer { dispGroup.leave() }
                
                print("CA already trusted? \(isTrusted)")
                
                // if not trusted, prompt to addTrustForCertificate
                if !isTrusted {
                    guard zkc.addCaPool(ca) else {
                        fputs("Unable to add CA pool to kechain\n", stderr)
                        return
                    }
                    print("Added CA pool to Keychain")
                    
                    // Might be configured still to not trust rootCA. Give user
                    // the change to mark as "Always Trust" (UI dialog will prompt for creds)
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
}

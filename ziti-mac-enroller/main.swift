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

// Logs the SDK version in use
ziti_debug_level = 3

// CommandLine
let args = CommandLine.arguments
guard CommandLine.argc == 2 else {
    let nm = URL(fileURLWithPath: args[0]).lastPathComponent
    print("Usage: \(nm) file.jwt")
    exit(-1)
}

let enroller = ZitiEnroller(args[1])
guard let subj = enroller.getSubj() else {
    fputs("Unable to extract sub from JWT file\n", stderr)
    exit(-1)
}

// Create private key
let zkc = ZitiKeychain(tag: subj)
guard let privKey = zkc.createPrivateKey() else {
    fputs("Unable to generate private key\n", stderr)
    exit(-1)
}
let pem = zkc.getKeyPEM(privKey)

// Enroll
enroller.enroll(privatePem: pem) { resp, _, err in
    guard let resp = resp else {
        fputs("Invalid enrollment response, \(String(describing: err))\n", stderr)
        exit(-1)
    }
    
    print("Enrolling id \"\(subj)\" with controller \"\(resp.ztAPI)\"")
    
    // Strip leading "pem:"s
    // let key = dropFirst("pem:", resp.id.key)
    let cert = dropFirst("pem:", resp.id.cert)
    var ca = resp.id.ca
    if let idCa = resp.id.ca {
        ca = dropFirst("pem:", idCa)
    }
        
    // store resp.ztAPI..
    if zkc.storeController(resp.ztAPI) != nil {
        fputs("Unable to store controller in keychain\n", stderr)
        exit(-1)
    }
    
    // Store certificate
    guard zkc.storeCertificate(fromPem: cert) == nil else {
        fputs("Unable to store certificate\n", stderr)
        exit(-1)
    }
    
    // Add the optional CA to keychain if not already trusted
    if let ca = ca {
        let certs = zkc.extractCerts(ca)
        
        // evalTrustForCertificates requires same DispatchQueue as caller, so force that to happen.
        // need to process the queue, block until done
        let dispQueue = DispatchQueue.main
        let dispGroup = DispatchGroup()
        
        dispGroup.enter()
        dispQueue.async {
            let status = zkc.evalTrustForCertificates(certs, dispQueue) { secTrust, isTrusted, err in
                defer { dispGroup.leave() }
                
                print("CA already trusted: \(isTrusted)")
                
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
                            print("User allowed trust of CA")
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
            // tell the user the application tag used to store the data in the keychain
            print("Successfully enrolled id \"\(subj)\" with controller \"\(resp.ztAPI)\"")
            exit(0)
        }
        dispatchMain()
    }
}

// Helper
func dropFirst(_ drop:String, _ str:String) -> String {
    var newStr = str
    if newStr.starts(with: drop) {
        newStr = String(newStr.dropFirst(drop.count))
    }
    return newStr
}

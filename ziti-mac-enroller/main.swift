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

// some logging...
ziti_debug_level = 3

let enroller = ZitiEnroller()
guard let subj = enroller.getSubj(args[1]) else {
    print("Unable to extract sub from JWT file")
    exit(-1)
}

// Create private key
let zkc = ZitiKeychain(tag: subj)
guard let privKey = zkc.createPrivateKey() else {
    print("Unable to generate private key")
    exit(-1)
}
let pem = zkc.getKeyPEM(privKey)

// Enroll
ZitiEnroller().enroll(jwtFile: args[1], privatePem: pem) { resp, subj, err in
    guard let resp = resp, let subj = subj else {
        print("Invalid enrollment response, \(String(describing: err))")
        exit(-1)
    }
    
    print("Enrolling id \"\(subj)\" with controller \"\(resp.ztAPI)\"")
    
#if false
    print("Identity JSON:" +
        "\nsubj: \(subj)" +
        "\nztAPI: \(resp.ztAPI)" +
        "\nid.key: \(resp.id.key)" +
        "\nid.cert: \(resp.id.cert)" +
        "\nid.ca: \(resp.id.ca ?? "")" +
        "\n")
#endif
    
    // Strip leading "pem:"s
    // let key = dropFirst("pem:", resp.id.key)
    let cert = dropFirst("pem:", resp.id.cert)
    var ca = resp.id.ca
    if let idCa = resp.id.ca {
        ca = dropFirst("pem:", idCa)
    }
    
    let zkc = ZitiKeychain(tag: subj)
    
    // store resp.ztAPI..
    if zkc.storeController(resp.ztAPI) != nil {
        print("Unable to store controller in keychain")
        exit(-1)
    }
    
    // Store certificate
    guard zkc.storeCertificate(fromPem: cert) == nil else {
        print("Unable to store certificate")
        exit(-1)
    }
    
    // See if we need to add trust for for the CA
    if let ca = ca {
        let certs = zkc.extractCerts(ca)
        
        // evalTrustForCertificates requires same DispatchQueue as caller, so force that to happen.
        // need to process the queue, block until done
        let dq = DispatchQueue.main
        let dg = DispatchGroup()
        
        dg.enter()
        dq.async {
            let status = zkc.evalTrustForCertificates(certs, dq) { secTrust, isTrusted, err in
                defer { dg.leave() }
                
                print("CA trusted: \(isTrusted)")
                if let err = err {
                    print("\(err as Error)")
                }
                
                // if not trusted, prompt to addTrustForCertificate
                if !isTrusted {
                    guard zkc.addTrustFromCaPool(ca) else {
                        print("Unable to add trust for CA")
                        return
                    }
                    print("Added trust for CA")
                }
            }
            guard status == errSecSuccess else {
                let errStr = SecCopyErrorMessageString(status, nil) as String? ?? "\(status)"
                print("Unable to evaluate trust for ca, err: \(status), \(errStr)")
                exit(status)
            }
        }
        
        dg.notify(queue: dq) {
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

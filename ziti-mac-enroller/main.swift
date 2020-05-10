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

// Enroll
ZitiEnroller().enroll(jwtFile: args[1]) { resp, subj, err in
    guard let resp = resp, let subj = subj else {
        print("Invalid enrollment response, \(String(describing: err))")
        exit(-1)
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
    
    // Strip leading "pem:"s
    let key = dropFirst("pem:", resp.id.key)
    let cert = dropFirst("pem:", resp.id.cert)
    var ca = resp.id.ca
    if let idCa = resp.id.ca {
        ca = dropFirst("pem:", idCa)
    }
    
    // Store private key
    guard key.starts(with: "-----BEGIN EC PRIVATE KEY-----") else {
        print("Only keys of type EC are currently supported")
        exit(-1)
    }
    
    let zkc = ZitiKeychain(tag: subj)
    guard zkc.storePrivateKey(fromPem: key, kSecAttrKeyTypeECSECPrimeRandom) == nil else {
        print("Unable to store private key")
        exit(-1)
    }
    
    // Store certificate
    guard zkc.storeCertificate(fromPem: cert) == nil else {
        print("Unable to store certificate")
        exit(-1)
    }
    
#if false
    // See if we need to add trust for for the CA
    if let ca = ca {
        let certs = ZitiKeychain.extractCerts(ca)
        
        // evalTrustForCertificates requires same DispatchQueue as caller, so force that to happen.
        // use condition to force every to block until we're ready to move on, else program will
        // exit...
        let dq = DispatchQueue(label: args[0])
        dq.async {
            let cond = NSCondition()
            var evalComplete = false
            
            let status = ZitiKeychain.evalTrustForCertificates(certs, dq) { secTrust, isTrusted, err in
                defer {
                    cond.lock()
                    evalComplete = true
                    cond.unlock()
                }
                
                print("CA trusted: \(isTrusted)")
                if let err = err {
                    print("\(err as Error)")
                }
                
                // if not trusted, prompt to addTrustForCertificate
                if !isTrusted {
                    // TODO: addTrustForCertificate is setup to only work for a Root CA, which we may
                    // not have. We could change that...
                    guard let rootCa = ZitiKeychain.extractRootCa(ca) else {
                        print("Unable to extract CA to add trust")
                        return
                    }
                    
                    let status = ZitiKeychain.addTrustForCertificate(rootCa)
                    guard status == errSecSuccess else {
                        let errStr = SecCopyErrorMessageString(status, nil) as String? ?? "\(status)"
                        print("Unable to add trust for ca, err: \(status), \(errStr)")
                        return
                    }
                }
            }
            guard status == errSecSuccess else {
                let errStr = SecCopyErrorMessageString(status, nil) as String? ?? "\(status)"
                print("Unable to evaluate trust for ca, err: \(status), \(errStr)")
                exit(status)
            }
            
            cond.lock()
            while !evalComplete {
                if !cond.wait(until: Date(timeIntervalSinceNow: 10.0))  {
                    print("timed-out waiting for trust evaluation")
                    cond.unlock()
                    break
                }
            }
            cond.unlock()
        }
    }
#else
    // TODO: addTrustForCertificate is setup to only work for a Root CA, which we may
    // not have. We could change that...
    if let ca = ca {
        guard let rootCa = zkc.extractRootCa(ca) else {
            print("Unable to extract CA to add trust")
            return
        }
        
        let status = zkc.addTrustForCertificate(rootCa)
        guard status == errSecSuccess else {
            let errStr = SecCopyErrorMessageString(status, nil) as String? ?? "\(status)"
            print("Unable to add trust for ca, err: \(status), \(errStr)")
            return
        }
    }
#endif
    
    // store resp.ztAPI somewhere in keychain..
    if zkc.storeController(resp.ztAPI) != nil {
        print("Unable to store controller in keychain")
        exit(-1)
    }
    
    // tell the user the application tag used to store the data in the keychain
    print("Successfully enrolled id \"\(subj)\" with controller \"\(resp.ztAPI)\"")
}

// Helper
func dropFirst(_ drop:String, _ str:String) -> String {
    var newStr = str
    if newStr.starts(with: drop) {
        newStr = String(newStr.dropFirst(drop.count))
    }
    return newStr
}

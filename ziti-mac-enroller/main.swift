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
    print("  \(nm) file.jwt out.zid [--enroll-to none|cert|token] [--trustca]")
    print("  \(nm) --url <url> out.zid [--enroll-to none|cert|token] [--trustca]")
    print("")
    print("Options:")
    print("  --enroll-to none    bootstrap only (CA + controller URL, no OIDC)")
    print("  --enroll-to cert    enrollToCert (OIDC + CSR, receive client certificate)")
    print("  --enroll-to token   enrollToToken (OIDC, auto-create identity, no certificate)")
    print("  --trustca           trust the CA bundle from enrollment")
    print("")
    print("Without --enroll-to, JWT files auto-detect: OTT gets standard enrollment,")
    print("network JWTs get bootstrap only (same as --enroll-to none).")
}

// Parse arguments
var isUrlMode = false
var urlStr:String?
var jwtFile:String?
var outFile:String?
var trustCa = false
var enrollTo:String?

var i = 1
while i < args.count {
    switch args[i] {
    case "--url":
        isUrlMode = true
        i += 1
        guard i < args.count else { usage(); exit(-1) }
        urlStr = args[i]
    case "--enroll-to":
        i += 1
        guard i < args.count else { usage(); exit(-1) }
        enrollTo = args[i]
        guard enrollTo == "none" || enrollTo == "cert" || enrollTo == "token" else {
            fputs("Invalid --enroll-to value: \(enrollTo!). Must be 'none', 'cert', or 'token'.\n", stderr)
            exit(-1)
        }
    case "--trustca":
        trustCa = true
    default:
        if outFile != nil {
            usage(); exit(-1)
        } else if !isUrlMode && jwtFile == nil {
            jwtFile = args[i]
        } else {
            outFile = args[i]
        }
    }
    i += 1
}
guard outFile != nil else { usage(); exit(-1) }
if isUrlMode { guard urlStr != nil else { usage(); exit(-1) } }
else { guard jwtFile != nil else { usage(); exit(-1) } }

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

let enrollHandler: (ZitiIdentity?, ZitiError?) -> Void = { zid, zErr in
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

let onAuth: (String) -> Void = { url in
    print("Authenticate at: \(url)")
}

if isUrlMode {
    switch enrollTo {
    case "cert":
        Ziti.enrollToCert(controllerURL: urlStr!, onAuth: onAuth, enrollHandler)
    case "token":
        Ziti.enrollToToken(controllerURL: urlStr!, onAuth: onAuth, enrollHandler)
    default:
        // none (or omitted) - bootstrap only
        Ziti.enroll(controllerURL: urlStr!, enrollHandler)
    }
} else {
    switch enrollTo {
    case "cert":
        Ziti.enrollToCert(jwtFile: jwtFile!, onAuth: onAuth, enrollHandler)
    case "token":
        Ziti.enrollToToken(jwtFile: jwtFile!, onAuth: onAuth, enrollHandler)
    default:
        // none (or omitted) - OTT auto-detects, network JWT bootstraps
        Ziti.enroll(jwtFile!, enrollHandler)
    }
}
dispatchMain()

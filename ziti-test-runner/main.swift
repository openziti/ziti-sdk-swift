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

// ziti-test-runner
//
// End-to-end integration test tool. Drives real enrollment and context bring-up
// against a live Ziti controller, producing a pass/fail exit code suitable for CI.
//
// Modes:
//   default      enroll (OTT/cert-jwt/token-jwt), save zid, load zid, run, verify
//   --only-run   load an existing zid from disk, run, verify (no enrollment)
//
// Exit codes:
//   0  success: received context event with status OK (and shutdown cleanly)
//   1  enrollment failed
//   2  identity load / run failed
//   3  context status != OK, or timeout reached
//   64 usage error (argv / input file)
//
// Known issue: macOS enrollment requires access to the data protection keychain,
// which fails under ad-hoc signing. Build with SWIFT_ACTIVE_COMPILATION_CONDITIONS
// containing CZITI_TEST_INSECURE_KEYS to have the SDK generate ephemeral keys and
// store them in the .zid file instead. NEVER ship such a build.

import Foundation
import CZiti

ZitiLog.setLogLevel(.INFO)

let args = CommandLine.arguments
let nm = URL(fileURLWithPath: args[0]).lastPathComponent

enum Mode: String {
    case ott, certJwt = "cert-jwt", tokenJwt = "token-jwt"
}

func usage() -> Never {
    print("""
    Usage:
      \(nm) [options] <jwt-file>             # enroll, save, load, run, verify
      \(nm) --only-run [options] <zid-file>  # load an existing zid and run

    Options:
      --mode <ott|cert-jwt|token-jwt>   Enrollment mode (default: ott, enroll modes only)
      --timeout <seconds>               Total test timeout (default: 60)
      --keep-zid <path>                 Keep enrolled .zid at this path (enroll modes only)
      --log-level <level>               WTF|ERROR|WARN|INFO|DEBUG|VERBOSE|TRACE (default: INFO)
      --only-run                        Input is a .zid file; skip enrollment
      -h, --help                        Show this message

    Exit codes:
      0   success
      1   enrollment failed
      2   identity load / run failed
      3   context status != OK, or timeout
      64  usage error
    """)
    exit(64)
}

// Parse args
var mode: Mode = .ott
var timeoutSeconds: Int = 60
var keepZid: String?
var onlyRun: Bool = false
var inputFile: String?

var i = 1
while i < args.count {
    switch args[i] {
    case "--mode":
        i += 1
        guard i < args.count, let m = Mode(rawValue: args[i]) else { usage() }
        mode = m
    case "--timeout":
        i += 1
        guard i < args.count, let n = Int(args[i]), n > 0 else { usage() }
        timeoutSeconds = n
    case "--keep-zid":
        i += 1
        guard i < args.count else { usage() }
        keepZid = args[i]
    case "--log-level":
        i += 1
        guard i < args.count, let lvl = ZitiLog.LogLevel(rawValue: levelFromString(args[i])) else { usage() }
        ZitiLog.setLogLevel(lvl)
    case "--only-run":
        onlyRun = true
    case "-h", "--help":
        usage()
    default:
        if inputFile == nil { inputFile = args[i] }
        else { usage() }
    }
    i += 1
}

func levelFromString(_ s: String) -> Int32 {
    switch s.uppercased() {
    case "WTF":     return -2
    case "ERROR":   return 1
    case "WARN":    return 2
    case "INFO":    return 3
    case "DEBUG":   return 4
    case "VERBOSE": return 5
    case "TRACE":   return 6
    default:        return 3
    }
}

guard let inputFile = inputFile else { usage() }
guard FileManager.default.fileExists(atPath: inputFile) else {
    fputs("error: input file not found: \(inputFile)\n", stderr)
    exit(64)
}

// Where the .zid lives during this test run.
// - In enroll mode: tmp path (or --keep-zid) to save the freshly enrolled identity.
// - In --only-run mode: the input file itself (we do not delete it on cleanup).
let zidPath: String = onlyRun
    ? inputFile
    : (keepZid ?? NSTemporaryDirectory() + "ziti-test-runner-\(UUID().uuidString).zid")

// Only clean up the zid in enroll mode when the user didn't ask to keep it.
func cleanupZidIfNeeded() {
    if !onlyRun && keepZid == nil {
        try? FileManager.default.removeItem(atPath: zidPath)
    }
}

let modeLabel = onlyRun ? "only-run" : mode.rawValue
print("ziti-test-runner: mode=\(modeLabel) input=\(inputFile) timeout=\(timeoutSeconds)s zid=\(zidPath)")

// `done` guards against double-exit if multiple events arrive.
var done = false
func finish(_ code: Int32, _ msg: String) {
    if done { return }
    done = true
    if code == 0 {
        print("PASS: \(msg)")
    } else {
        fputs("FAIL[\(code)]: \(msg)\n", stderr)
    }
    cleanupZidIfNeeded()
    exit(code)
}

/// Load a saved identity, run Ziti, and succeed once we've seen:
///   1. A ContextEvent with status OK (authenticated with the controller)
///   2. A ServiceEvent with at least one service in `added`
/// The second check verifies the service channel works end-to-end, not just auth.
/// CI must configure at least one service + service-policy for the test identity,
/// otherwise this will time out.
func runFromZidFile(_ zidPath: String) {
    guard let ziti = Ziti(fromFile: zidPath) else {
        finish(2, "failed to load Ziti identity from \(zidPath)")
        return
    }

    var contextOK = false
    var servicesSeen = false

    ziti.registerEventCallback({ event in
        guard !done, let event = event else { return }
        switch event.type {
        case .Context:
            guard let ctx = event.contextEvent else { return }
            if ctx.status == 0 {
                print("context authenticated")
                contextOK = true
            } else {
                let msg = ctx.err ?? "context error status=\(ctx.status)"
                finish(3, msg)
                ziti.shutdown()
                return
            }
        case .Service:
            guard let svc = event.serviceEvent, !svc.added.isEmpty else { return }
            let names = svc.added.compactMap { $0.name }.joined(separator: ", ")
            print("services received: [\(names)]")
            servicesSeen = true
        default:
            return
        }
        if contextOK && servicesSeen {
            finish(0, "context+service OK (id=\(ziti.id.id) ztAPI=\(ziti.id.ztAPI))")
            ziti.shutdown()
        }
    }, ZitiEvent.EventType.Context.rawValue | ZitiEvent.EventType.Service.rawValue)

    ziti.run { zErr in
        if let zErr = zErr {
            finish(2, "ziti.run init error: \(zErr.localizedDescription)")
            return
        }
        ziti.startTimer(UInt64(timeoutSeconds) * 1000, 0) { timer in
            ziti.endTimer(timer)
            if !done {
                let missing = [
                    contextOK ? nil : "context",
                    servicesSeen ? nil : "service"
                ].compactMap { $0 }.joined(separator: "+")
                finish(3, "timeout after \(timeoutSeconds)s waiting for: \(missing)")
                ziti.shutdown()
            }
        }
    }
}

if onlyRun {
    // Load the given zid directly and run - no enrollment.
    runFromZidFile(inputFile)
} else {
    // Enroll first, save the zid, then load+run.
    let onAuth: (String) -> Void = { url in
        print("Authenticate at: \(url)")
    }

    let enrollHandler: (ZitiIdentity?, ZitiError?) -> Void = { zid, zErr in
        guard let zid = zid else {
            finish(1, "enrollment failed: \(zErr?.localizedDescription ?? "unknown error")")
            return
        }
        guard zid.save(zidPath) else {
            finish(1, "failed to save enrolled identity to \(zidPath)")
            return
        }
        print("enrolled id=\"\(zid.id)\" ztAPI=\"\(zid.ztAPI)\"")
        runFromZidFile(zidPath)
    }

    switch mode {
    case .ott:
        Ziti.enroll(inputFile, enrollHandler)
    case .certJwt:
        Ziti.enrollToCert(jwtFile: inputFile, onAuth: onAuth, enrollHandler)
    case .tokenJwt:
        Ziti.enrollToToken(jwtFile: inputFile, onAuth: onAuth, enrollHandler)
    }
}

dispatchMain()

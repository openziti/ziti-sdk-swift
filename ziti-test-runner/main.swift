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
// Exit codes:
//   0  success: enrolled, loaded identity, received context event with status OK
//   1  enrollment failed
//   2  identity load / run failed
//   3  context status != OK, or timeout reached
//   64 usage error (argv / input file)
//
// Local use:
//   ./ziti-test-runner /path/to/ott.jwt
//
// Known issue: macOS enrollment requires access to the data protection keychain,
// which fails with -34018 (errSecMissingEntitlement) under ad-hoc signing. The
// tool currently fails the same way in `ziti-mac-enroller`. CI builds the tool
// to catch compile regressions but does not run it end-to-end until the keychain
// access problem is resolved (either by signing with a real team cert or by
// changing the SDK to fall back to file-based keys when no proper entitlement
// is available).

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
      \(nm) [options] <jwt-file>

    Options:
      --mode <ott|cert-jwt|token-jwt>   Enrollment mode (default: ott)
      --timeout <seconds>               Total test timeout (default: 60)
      --keep-zid <path>                 Keep the .zid file at this path (default: temp file, deleted)
      --log-level <level>               WTF|ERROR|WARN|INFO|DEBUG|VERBOSE|TRACE (default: INFO)

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
var jwtFile: String?

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
    case "-h", "--help":
        usage()
    default:
        if jwtFile == nil { jwtFile = args[i] }
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

guard let jwtFile = jwtFile else { usage() }
guard FileManager.default.fileExists(atPath: jwtFile) else {
    fputs("error: JWT file not found: \(jwtFile)\n", stderr)
    exit(64)
}

// Decide where to save the enrolled .zid file.
let zidPath: String = keepZid ?? {
    let tmp = NSTemporaryDirectory() + "ziti-test-runner-\(UUID().uuidString).zid"
    return tmp
}()

// Guard against leftover temp files if we're not keeping them.
func cleanupZidIfNeeded() {
    if keepZid == nil {
        try? FileManager.default.removeItem(atPath: zidPath)
    }
}

print("ziti-test-runner: mode=\(mode.rawValue) jwt=\(jwtFile) timeout=\(timeoutSeconds)s zid=\(zidPath)")

// We'll drive the whole test through Ziti's uv loop via dispatchMain + exit().
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

    // Load the saved identity and run.
    guard let ziti = Ziti(fromFile: zidPath) else {
        finish(2, "failed to load Ziti identity from \(zidPath)")
        return
    }

    // Register a context-event listener before calling run().
    ziti.registerEventCallback({ event in
        guard !done else { return }
        guard let event = event, event.type == .Context, let ctx = event.contextEvent else { return }
        if ctx.status == 0 {
            finish(0, "context authenticated (ztAPI=\(zid.ztAPI))")
            ziti.shutdown()
        } else {
            let msg = ctx.err ?? "context error status=\(ctx.status)"
            finish(3, msg)
            ziti.shutdown()
        }
    }, ZitiEvent.EventType.Context.rawValue)

    // Overall timeout - if we never see a context event, fail.
    ziti.run { zErr in
        if let zErr = zErr {
            finish(2, "ziti.run init error: \(zErr.localizedDescription)")
            return
        }
        ziti.startTimer(UInt64(timeoutSeconds) * 1000, 0) { timer in
            ziti.endTimer(timer)
            if !done {
                finish(3, "timeout after \(timeoutSeconds)s waiting for context event")
                ziti.shutdown()
            }
        }
    }
}

// Kick off enrollment in the chosen mode.
switch mode {
case .ott:
    Ziti.enroll(jwtFile, enrollHandler)
case .certJwt:
    Ziti.enrollToCert(jwtFile: jwtFile, onAuth: onAuth, enrollHandler)
case .tokenJwt:
    Ziti.enrollToToken(jwtFile: jwtFile, onAuth: onAuth, enrollHandler)
}

dispatchMain()

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

import XCTest
@testable import CZiti

class ZitiTunnelInterceptOnlyTests: XCTestCase {

    /// The tunneler's own flag, read on the loop thread
    private func tunnelerIsInterceptOnly(_ tunnel:ZitiTunnel) -> Bool {
        let read = expectation(description: "read on the loop")
        var interceptOnly = false
        tunnel.perform {
            interceptOnly = tunnel.tunnelerIsInterceptOnly
            read.fulfill()
        }
        wait(for: [read], timeout: 5)
        return interceptOnly
    }

    // one test: lwip initializes once per process, so a second ZitiTunnel can't be made. The reads off the loop are
    // made while no loop runs: before startZiti and after shutdownZiti completes
    func testInterceptOnlyAppliesAtStartSwitchesLiveAndStopsAtShutdown() {
        let tunnel = ZitiTunnel(nil, "100.64.0.1", "255.192.0.0", "100.64.0.2")

        tunnel.setInterceptOnly(true)
        tunnel.setInterceptOnly(false)
        tunnel.setInterceptOnly(true)
        XCTAssertFalse(tunnel.tunnelerIsInterceptOnly, "held until startZiti")

        let loaded = expectation(description: "loaded")
        tunnel.startZiti([], nil) { _ in loaded.fulfill() }
        wait(for: [loaded], timeout: 10)
        XCTAssertTrue(tunnelerIsInterceptOnly(tunnel), "the last value before startZiti applies when Ziti starts")

        tunnel.setInterceptOnly(false)
        XCTAssertFalse(tunnelerIsInterceptOnly(tunnel), "switched off on the loop")
        tunnel.setInterceptOnly(false)
        tunnel.setInterceptOnly(true)
        XCTAssertTrue(tunnelerIsInterceptOnly(tunnel), "the last switch wins")

        // from many threads at once, then all on: the loop ends up with the latest
        DispatchQueue.concurrentPerform(iterations: 200) { tunnel.setInterceptOnly($0 % 2 == 0) }
        DispatchQueue.concurrentPerform(iterations: 50) { _ in tunnel.setInterceptOnly(true) }
        XCTAssertTrue(tunnelerIsInterceptOnly(tunnel), "concurrent switches settle on the latest")

        // hold the loop so the first switch is still queued when the shutdown starts
        let gate = DispatchSemaphore(value: 0)
        tunnel.perform { gate.wait() }
        tunnel.setInterceptOnly(false)
        let down = expectation(description: "shut down")
        tunnel.shutdownZiti { down.fulfill() }
        tunnel.setInterceptOnly(false)
        gate.signal()
        wait(for: [down], timeout: 10)
        // the completion also comes on a timeout, with the loop still running
        XCTAssertEqual(tunnel.uvDG.wait(timeout: .now() + 5), .success, "the loop has exited")
        XCTAssertTrue(tunnel.tunnelerIsInterceptOnly, "a switch queued before the shutdown or made after it is ignored")
    }

    // a shutdown before the start thread gets going isn't undone: the stage stays shut down, so no switch reaches the
    // loop from then on
    func testStage_startedKeepsAShutdown() {
        XCTAssertEqual(ZitiTunnel.Stage.notStarted.started, .running)
        XCTAssertEqual(ZitiTunnel.Stage.running.started, .running)
        XCTAssertEqual(ZitiTunnel.Stage.shutDown.started, .shutDown)
    }
}

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
import CZitiPrivate
@testable import CZiti

/// Exercises `ZitiUrlProtocol` intercept bookkeeping against a real (but never connected) uv loop.
///
/// The loop is driven manually with `UV_RUN_NOWAIT` so each test controls exactly which callbacks run.
/// No test lets the loop run an idle phase while a request is queued, so nothing ever tries to dial.
class ZitiUrlProtocolTests: XCTestCase {
    var ziti:Ziti!

    // without a context nothing keeps the loop alive, and uv_run() returns without processing anything
    var keepAlive:UnsafeMutablePointer<uv_timer_t>!

    // set when a test detects freed memory linked into the loop, so tearDown() doesn't run it
    var loopCorrupted = false

    override func setUp() {
        super.setUp()
        ziti = Ziti("test-id", ["https://ctrl.example.com:443"], name: nil, caPool: nil)
        keepAlive = UnsafeMutablePointer<uv_timer_t>.allocate(capacity: 1)
        keepAlive.initialize(to: uv_timer_t())
        uv_timer_init(ziti.loop, keepAlive)
        uv_timer_start(keepAlive, { _ in }, 60_000, 0)
        ZitiUrlProtocol.ziti = ziti
        ZitiUrlProtocol.intercepts = [:]
        ZitiUrlProtocol.reqs = []
        ZitiIntercept.releasePending = []
    }

    override func tearDown() {
        if !loopCorrupted {
            ZitiUrlProtocol.intercepts.values.forEach { $0.close() }
            keepAlive.withMemoryRebound(to: uv_handle_t.self, capacity: 1) { uv_close($0, nil) }
            runLoopOnce()
            keepAlive.deinitialize(count: 1)
            keepAlive.deallocate()
        } // else leak the loop's handles rather than crash the test run
        ZitiUrlProtocol.intercepts = [:]
        ZitiUrlProtocol.reqs = []
        ZitiIntercept.releasePending = []
        ZitiUrlProtocol.ziti = nil
        ziti = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func runLoopOnce() {
        uv_run(ziti.loop, UV_RUN_NOWAIT)
    }

    private func isClosing(_ intercept:ZitiIntercept) -> Bool {
        return withUnsafeMutablePointer(to: &intercept.clt.proc) {
            $0.withMemoryRebound(to: uv_handle_t.self, capacity: 1) { uv_is_closing($0) != 0 }
        }
    }

    private func service(_ name:String, _ configs:String) throws -> ZitiService {
        let json = "{\"name\":\"\(name)\",\"id\":\"\(name)-id\",\"permFlags\":\(ZITI_CAN_DIAL),\(configs)}"
        return try JSONDecoder().decode(ZitiService.self, from: Data(json.utf8))
    }

    private func urlService(_ name:String, _ scheme:String, _ host:String, _ port:Int) throws -> ZitiService {
        return try service(name, "\"ziti-url-client.v1\":{\"scheme\":\"\(scheme)\",\"hostname\":\"\(host)\",\"port\":\(port)}")
    }

    private func interceptService(_ name:String, _ host:String, _ port:Int) throws -> ZitiService {
        return try service(name, """
            "intercept.v1":{"protocols":["tcp"],"addresses":["\(host)"],"portRanges":[{"low":\(port),"high":\(port)}]}
            """)
    }

    private func add(_ svc:ZitiService) {
        ZitiUrlProtocol.addOrUpdateService(svc, ziti, 10000)
    }

    /// runs client notifications, which `ZitiUrlProtocol` queues on the thread that called `startLoading()`
    private func runClientThread() {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
    }

    // MARK: - removeService (issue #343)

    func testRemoveServiceClosesRemovedIntercepts() throws {
        let svcA = try urlService("svcA", "http", "a.example.com", 8080)
        add(svcA)
        add(try interceptService("svcB", "b.example.com", 9000))

        let a = try XCTUnwrap(ZitiUrlProtocol.intercepts["http://a.example.com:8080"])
        let bHttp = try XCTUnwrap(ZitiUrlProtocol.intercepts["http://b.example.com:9000"])
        let bHttps = try XCTUnwrap(ZitiUrlProtocol.intercepts["https://b.example.com:9000"])

        ZitiUrlProtocol.removeService(svcA)

        XCTAssertNil(ZitiUrlProtocol.intercepts["http://a.example.com:8080"])
        XCTAssertTrue(isClosing(a), "removed intercept must close its uv handle before it is released")
        XCTAssertTrue(ZitiIntercept.releasePending.contains(a), "removed intercept must be kept alive until its close callback")

        XCTAssertFalse(isClosing(bHttp))
        XCTAssertFalse(isClosing(bHttps))
        XCTAssertEqual(ZitiUrlProtocol.intercepts.count, 2)

        runLoopOnce()
        XCTAssertFalse(ZitiIntercept.releasePending.contains(a), "close callback should release the intercept")
    }

    /// Issue #343: removing a service freed its intercept while the intercept's idle handle was still active
    /// in the loop, so the next iteration crashed in uv__run_idle.
    ///
    /// The use-after-free itself only reliably crashes under ASan, so this checks for the condition that causes it
    /// and does not run the loop if it is present.
    func testRemoveServiceDoesNotFreeInterceptWithActiveIdleHandle() throws {
        let svc = try urlService("svc", "http", "a.example.com", 8080)
        add(svc)

        // a queued request starts the intercept's idle handle
        let zup = ZitiUrlProtocol(request: URLRequest(url: URL(string: "http://a.example.com:8080/x")!),
                                  cachedResponse: nil, client: nil)
        zup.startLoading()
        runLoopOnce()

        weak var weakIntercept:ZitiIntercept?
        autoreleasepool {
            let intercept = ZitiUrlProtocol.intercepts["http://a.example.com:8080"]
            XCTAssertNotNil(intercept)
            if let intercept = intercept {
                XCTAssertTrue(withUnsafeMutablePointer(to: &intercept.clt.proc) {
                    $0.withMemoryRebound(to: uv_handle_t.self, capacity: 1) { uv_is_active($0) != 0 }
                }, "idle handle should be active with a queued request")
            }
            weakIntercept = intercept

            ZitiUrlProtocol.removeService(svc)
        }

        guard weakIntercept != nil else {
            loopCorrupted = true
            XCTFail("intercept was freed with its idle handle still in the loop. the next loop iteration would crash in uv__run_idle")
            return
        }
        autoreleasepool {
            XCTAssertTrue(isClosing(weakIntercept!), "intercept must close its idle handle before it is released")
        }

        // the intercept is released once the loop runs its close callback
        autoreleasepool { runLoopOnce() }
        XCTAssertNil(weakIntercept, "intercept should be released after its close callback")
    }

    func testRemoveServiceWithQueuedRequestCancelsAndReleasesRequest() throws {
        let svc = try urlService("svc", "http", "a.example.com", 8080)
        add(svc)

        // queue a request on the intercept. startLoading() dispatches to the loop, and the loop's idle phase
        // runs before the async ops are processed, so the request is left queued with the idle handle active
        let zup = ZitiUrlProtocol(request: URLRequest(url: URL(string: "http://a.example.com:8080/x")!),
                                  cachedResponse: nil, client: nil)
        zup.startLoading()
        runLoopOnce()
        XCTAssertTrue(zup.started)
        XCTAssertNotNil(zup.req)
        XCTAssertTrue(ZitiUrlProtocol.reqs.contains(zup))

        // this is the scenario from #343. without the fix the intercept is freed with an active idle handle
        // and the next loop iteration crashes in uv__run_idle
        ZitiUrlProtocol.removeService(svc)
        runLoopOnce()
        runLoopOnce()

        XCTAssertTrue(zup.finished, "request cancelled by intercept close should be marked finished")
        XCTAssertTrue(ZitiIntercept.releasePending.isEmpty)

        zup.stopLoading()
        runLoopOnce()
        XCTAssertFalse(ZitiUrlProtocol.reqs.contains(zup), "failed request should be released after stopLoading()")
    }

    // MARK: - interceptByHostAndPort

    func testInterceptByHostAndPortOnlyClosesReplacedScheme() throws {
        // https on port 80 can only come from a url config, and is not replaced by an intercept on port 80
        add(try urlService("svcUrl", "https", "h.example.com", 80))
        add(try urlService("svcOld", "http", "h.example.com", 80))
        let https80 = try XCTUnwrap(ZitiUrlProtocol.intercepts["https://h.example.com:80"])
        let oldHttp80 = try XCTUnwrap(ZitiUrlProtocol.intercepts["http://h.example.com:80"])

        add(try interceptService("svcTun", "h.example.com", 80))

        let newHttp80 = try XCTUnwrap(ZitiUrlProtocol.intercepts["http://h.example.com:80"])
        XCTAssertEqual(newHttp80.name, "svcTun")
        XCTAssertTrue(isClosing(oldHttp80), "replaced intercept should be closed")
        XCTAssertFalse(isClosing(newHttp80))

        let stillHttps80 = try XCTUnwrap(ZitiUrlProtocol.intercepts["https://h.example.com:80"])
        XCTAssertTrue(stillHttps80 === https80)
        XCTAssertEqual(stillHttps80.name, "svcUrl")
        XCTAssertFalse(isClosing(stillHttps80), "intercept that was not replaced must not be closed")
    }

    func testInterceptByHostAndPortReplacesBothSchemesOnNonStandardPort() throws {
        add(try interceptService("svcOld", "h.example.com", 8443))
        let oldHttp = try XCTUnwrap(ZitiUrlProtocol.intercepts["http://h.example.com:8443"])
        let oldHttps = try XCTUnwrap(ZitiUrlProtocol.intercepts["https://h.example.com:8443"])

        add(try interceptService("svcNew", "h.example.com", 8443))

        XCTAssertTrue(isClosing(oldHttp))
        XCTAssertTrue(isClosing(oldHttps))
        XCTAssertEqual(ZitiUrlProtocol.intercepts["http://h.example.com:8443"]?.name, "svcNew")
        XCTAssertEqual(ZitiUrlProtocol.intercepts["https://h.example.com:8443"]?.name, "svcNew")
        XCTAssertEqual(ZitiUrlProtocol.intercepts.values.filter { isClosing($0) }.count, 0)
    }

    // MARK: - startLoading

    func testStartLoadingWithoutInterceptFailsRequest() throws {
        let client = TestClient()
        let zup = ZitiUrlProtocol(request: URLRequest(url: URL(string: "http://a.example.com:8080/x")!),
                                  cachedResponse: nil, client: client)
        zup.startLoading()
        runLoopOnce()

        XCTAssertNil(zup.req)
        XCTAssertTrue(zup.finished, "request without an intercept should be marked finished")
        runClientThread()
        XCTAssertEqual((client.error as NSError?)?.code, Ziti.ZITI_SERVICE_UNAVAILABLE)

        zup.stopLoading()
        runLoopOnce()
        XCTAssertFalse(ZitiUrlProtocol.reqs.contains(zup), "failed request should be released after stopLoading()")
    }

    func testStartLoadingAfterServiceRemovedFailsRequest() throws {
        let svc = try urlService("svc", "http", "a.example.com", 8080)
        add(svc)

        let request = URLRequest(url: URL(string: "http://a.example.com:8080/x")!)
        XCTAssertTrue(ZitiUrlProtocol.canInit(with: request))

        // the service is removed after canInit() but before the loop runs the queued request
        let client = TestClient()
        let zup = ZitiUrlProtocol(request: request, cachedResponse: nil, client: client)
        zup.startLoading()
        ZitiUrlProtocol.removeService(svc)
        runLoopOnce()

        XCTAssertNil(zup.req)
        XCTAssertTrue(zup.finished)
        runClientThread()
        XCTAssertEqual((client.error as NSError?)?.code, Ziti.ZITI_SERVICE_UNAVAILABLE)
    }

    // MARK: - addOrUpdateService

    func testChangedServiceRemovesInterceptsNotInNewConfig() throws {
        add(try urlService("svc", "http", "a.example.com", 8080))
        let old = try XCTUnwrap(ZitiUrlProtocol.intercepts["http://a.example.com:8080"])

        add(try urlService("svc", "http", "b.example.com", 8080))

        XCTAssertNil(ZitiUrlProtocol.intercepts["http://a.example.com:8080"], "intercept from the old config should be removed")
        XCTAssertTrue(isClosing(old))
        XCTAssertEqual(ZitiUrlProtocol.intercepts["http://b.example.com:8080"]?.name, "svc")
        XCTAssertEqual(ZitiUrlProtocol.intercepts.count, 1)
    }

    func testChangedServiceFromInterceptToUrlConfigRemovesOtherScheme() throws {
        add(try interceptService("svc", "h.example.com", 8443))
        let oldHttp = try XCTUnwrap(ZitiUrlProtocol.intercepts["http://h.example.com:8443"])
        let oldHttps = try XCTUnwrap(ZitiUrlProtocol.intercepts["https://h.example.com:8443"])

        add(try urlService("svc", "https", "h.example.com", 8443))

        XCTAssertNil(ZitiUrlProtocol.intercepts["http://h.example.com:8443"], "http intercept is not in the new config")
        XCTAssertTrue(isClosing(oldHttp))
        XCTAssertTrue(isClosing(oldHttps))
        let https = try XCTUnwrap(ZitiUrlProtocol.intercepts["https://h.example.com:8443"])
        XCTAssertFalse(isClosing(https))
        XCTAssertEqual(ZitiUrlProtocol.intercepts.count, 1)
    }

    func testChangedServiceDoesNotRemoveOtherServices() throws {
        add(try urlService("svcA", "http", "a.example.com", 8080))
        add(try urlService("svcB", "http", "b.example.com", 8080))
        let b = try XCTUnwrap(ZitiUrlProtocol.intercepts["http://b.example.com:8080"])

        add(try urlService("svcA", "http", "c.example.com", 8080))

        XCTAssertTrue(ZitiUrlProtocol.intercepts["http://b.example.com:8080"] === b)
        XCTAssertFalse(isClosing(b))
        XCTAssertEqual(ZitiUrlProtocol.intercepts.count, 2)
    }
}

/// records the error reported to the client
private class TestClient: NSObject, URLProtocolClient {
    var error:Error?

    func urlProtocol(_ protocol: URLProtocol, didFailWithError error: Error) { self.error = error }
    func urlProtocol(_ protocol: URLProtocol, wasRedirectedTo request: URLRequest, redirectResponse: URLResponse) {}
    func urlProtocol(_ protocol: URLProtocol, cachedResponseIsValid cachedResponse: CachedURLResponse) {}
    func urlProtocol(_ protocol: URLProtocol, didReceive response: URLResponse, cacheStoragePolicy policy: URLCache.StoragePolicy) {}
    func urlProtocol(_ protocol: URLProtocol, didLoad data: Data) {}
    func urlProtocolDidFinishLoading(_ protocol: URLProtocol) {}
    func urlProtocol(_ protocol: URLProtocol, didReceive challenge: URLAuthenticationChallenge) {}
    func urlProtocol(_ protocol: URLProtocol, didCancel challenge: URLAuthenticationChallenge) {}
}

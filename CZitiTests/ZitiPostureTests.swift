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

class ZitiPostureQueryTests: XCTestCase {

    func testDecodeFullQuery() throws {
        let json = """
        {"isPassing":true,"queryType":"OS","id":"query-1","timeout":3600,"timeoutRemaining":3000}
        """
        let q = try JSONDecoder().decode(ZitiPostureQuery.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(q.isPassing, true)
        XCTAssertEqual(q.queryType, "OS")
        XCTAssertEqual(q.id, "query-1")
        XCTAssertEqual(q.timeout, 3600)
        XCTAssertEqual(q.timeoutRemaining, 3000)
    }

    func testDecodeAllOptionalsMissing() throws {
        let json = """
        {}
        """
        let q = try JSONDecoder().decode(ZitiPostureQuery.self, from: json.data(using: .utf8)!)
        XCTAssertNil(q.isPassing)
        XCTAssertNil(q.queryType)
        XCTAssertNil(q.id)
        XCTAssertNil(q.timeout)
        XCTAssertNil(q.timeoutRemaining)
    }

    func testDecodeNegativeTimeouts() throws {
        // -1 is used in the C SDK to indicate "not applicable"
        let json = """
        {"id":"x","timeout":-1,"timeoutRemaining":-1}
        """
        let q = try JSONDecoder().decode(ZitiPostureQuery.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(q.timeout, -1)
        XCTAssertEqual(q.timeoutRemaining, -1)
    }
}

class ZitiPostureQuerySetTests: XCTestCase {

    func testDecodeFullSet() throws {
        let json = """
        {
            "isPassing": true,
            "policyId": "policy-123",
            "policyType": "binding",
            "postureQueries": [
                {"isPassing": true, "queryType": "OS", "id": "q1", "timeout": 300, "timeoutRemaining": 250},
                {"isPassing": false, "queryType": "MFA", "id": "q2", "timeout": -1, "timeoutRemaining": -1}
            ]
        }
        """
        let s = try JSONDecoder().decode(ZitiPostureQuerySet.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(s.isPassing, true)
        XCTAssertEqual(s.policyId, "policy-123")
        XCTAssertEqual(s.policyType, "binding")
        XCTAssertEqual(s.postureQueries?.count, 2)
        XCTAssertEqual(s.postureQueries?[0].id, "q1")
        XCTAssertEqual(s.postureQueries?[1].queryType, "MFA")
    }

    func testDecodeWithoutPostureQueries() throws {
        let json = """
        {"isPassing":false,"policyId":"p","policyType":"t"}
        """
        let s = try JSONDecoder().decode(ZitiPostureQuerySet.self, from: json.data(using: .utf8)!)
        XCTAssertNil(s.postureQueries)
    }

    func testDecodeEmptyPostureQueriesArray() throws {
        let json = """
        {"postureQueries":[]}
        """
        let s = try JSONDecoder().decode(ZitiPostureQuerySet.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(s.postureQueries?.count, 0)
    }

    func testCodableRoundTrip() throws {
        let json = """
        {"isPassing":true,"policyId":"p1","postureQueries":[{"id":"q1","isPassing":true}]}
        """
        let original = try JSONDecoder().decode(ZitiPostureQuerySet.self, from: json.data(using: .utf8)!)
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ZitiPostureQuerySet.self, from: encoded)
        XCTAssertEqual(decoded.isPassing, original.isPassing)
        XCTAssertEqual(decoded.policyId, original.policyId)
        XCTAssertEqual(decoded.postureQueries?.count, original.postureQueries?.count)
    }
}

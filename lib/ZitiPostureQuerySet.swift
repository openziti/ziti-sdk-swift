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
import CZitiPrivate

/// Class encapsulating Ziti SDK C's posture query set
@objc public class ZitiPostureQuerySet : NSObject, Codable {
    private static let log = ZitiLog(ZitiPostureQuerySet.self)
    
    /// Indicates wheter or not this posture query set is passing
    public var isPassing:Bool?
    
    /// Policy identifier
    public var policyId:String?
    
    /// Policy type
    public var policyType:String?
    
    /// Listing of posture queries
    public var postureQueries:[ZitiPostureQuery]?
         
    init(_ cPQS:UnsafeMutablePointer<ziti_posture_query_set>) {
        isPassing = cPQS.pointee.is_passing
        policyId = cPQS.pointee.policy_id != nil ? String(cString: cPQS.pointee.policy_id) : ""
        policyType = cPQS.pointee.policy_type != nil ? String(cString:cPQS.pointee.policy_type) : ""
        
        if var pqPtr = cPQS.pointee.posture_queries {
            while let pq = pqPtr.pointee {
                if postureQueries == nil { postureQueries = [] }
                postureQueries?.append(ZitiPostureQuery(pq))
                pqPtr += 1
            }
        }
    }
}
